//
//  LabsPlatformAuth.swift
//  LabsPlatformSwift
//
//  Created by Jonathan Melitski on 1/31/25.
//

import Foundation
import SwiftUI

extension LabsPlatform {
    /// Handles the authentication flow with Platform.
    /// Defined in the scope of the `LabsPlatform` environment object created by [`View.enableLabsPlatform()`](x-source-tag://enableLabsPlatform)
    ///
    /// - Tag: loginWithPlatform
    public func loginWithPlatform() {
        let phases: [() async throws -> PlatformAuthState] = [
            prepareLogin,
            fetchAccessCode,
            fetchToken,
        ]
        
        Task {
            do {
                for phase in phases {
                    self.authState = try await phase()
                    if case .loggedOut = await self.authState {
                        break
                    }
                    
                    // Correctly handle default login
                    if case .loggedIn(_) = await self.authState {
                        break
                    }
                }
            } catch {
                self.authState = .loggedOut
            }
            
            if case .loggedIn(let credential) = self.authState {
                return
            } else {
                self.authState = .loggedOut
            }
        }
    }
    
    /// Tells the client to log out of Platform and remove cached login credentials
    /// and details (except for Analytic tokens, which will time out separately)
    /// Will always run the `loginHandler` function with the boolean argument being `false`.
    ///
    /// - Tag: logoutPlatform
    public func logoutPlatform() {
        self.authState = .loggedOut
    }
    
    
// MARK: Top-level Auth Flow Functions
    func prepareLogin() throws -> PlatformAuthState {
        let verifier: String = AuthUtilities.codeVerifier()
        let state: String = AuthUtilities.stateString()
        guard let url = URL(string:
                                "\(LabsPlatform.authEndpoint.absoluteString)?response_type=code&code_challenge=\(AuthUtilities.codeChallenge(from: verifier))&code_challenge_method=S256&client_id=\(self.clientId)&redirect_uri=\(self.authRedirect)&scope=openid%20read%20introspection&state=\(state)") else { throw PlatformAuthError.invalidUrl }
        return .newLogin(url: url, state: state, verifier: verifier)
    }
    
    func fetchAccessCode() async throws -> PlatformAuthState {
        guard case .newLogin(let url, let state, let verifier) = self.authState else {
            throw PlatformAuthError.illegalState
        }
        
        await MainActor.run {
            self.webViewUrl = url
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            self.webViewCheckedContinuation = continuation
        }
    }
    
    func fetchToken() async throws -> PlatformAuthState {
        guard case .codeAcquired(let authCode, let verifier) = self.authState else {
            throw PlatformAuthError.illegalState
        }
        
        let parameters: [String: String] = [
            "grant_type": "authorization_code",
            "code": authCode.authCode,
            "redirect_uri": "\(self.authRedirect)",
            "client_id": self.clientId,
            "code_verifier": verifier,
        ]
        
        let req = await tokenPostRequest(parameters)
        if case .failure(let error) = req {
            throw error
        }
        
        guard case .success(let data) = req else {
            throw PlatformAuthError.illegalState
        }
        
        return .loggedIn(auth: data)
    }
    
    func cancelLogin() {
        self.authState = .loggedOut
    }
    
    func completeDefaultLogin() {
        self.authState = .loggedIn(auth: PlatformAuthCredentials.defaultValue)
    }
    
// MARK: Other functions
    func urlCallbackFunction(callbackResult: Result<URL, any Error>) {
        if case .loggedIn(_) = self.authState {
            self.webViewCheckedContinuation?.resume(returning: self.authState)
            self.webViewCheckedContinuation = nil
            return
        }
        
        guard case .success(let url) = callbackResult,
              case .newLogin(_, let currentState, let verifier) = self.authState,
              let comps = URLComponents(string: url.absoluteString) else {
            self.cancelLogin()
            self.webViewCheckedContinuation?.resume(throwing: PlatformAuthError.invalidCallback)
            self.webViewCheckedContinuation = nil
            return
        }
        
        if let defaultLogin = comps.queryItems?.first(where: {$0.name == "defaultlogin"})?.value,
           defaultLogin == "true" {
            self.completeDefaultLogin()
            self.webViewCheckedContinuation?.resume(returning: self.authState)
            self.webViewCheckedContinuation = nil
            return
        }
        
        guard let code = comps.queryItems?.first(where: { $0.name == "code"})?.value,
              let state = comps.queryItems?.first(where: {$0.name == "state"})?.value,
              currentState == state else {
            self.cancelLogin()
            self.webViewCheckedContinuation?.resume(throwing: PlatformAuthError.invalidCallback)
            self.webViewCheckedContinuation = nil
            return
        }
        
        self.webViewUrl = nil
        self.webViewCheckedContinuation?.resume(returning: .codeAcquired(result: AuthCompletionResult(authCode: code, state: state), verifier: verifier))
        self.webViewCheckedContinuation = nil
        return
    }
    
// MARK: Setup + Refresh
    func getCurrentAuthState() -> PlatformAuthState {
        let credential: PlatformAuthCredentials
        if case .loggedIn(let cred) = self.authState {
            credential = cred
        } else if let cred = LabsKeychain.loadPlatformCredential() {
                credential = cred
        } else {
                return .loggedOut
        }
        
        
        
        if credential.issuedAt.addingTimeInterval(TimeInterval(credential.expiresIn)) < Date.now {
            return .needsRefresh(auth: credential)
        } else {
            return .loggedIn(auth: credential)
        }
    }
    
    func getRefreshedAuthState() async -> PlatformAuthState {
        let state = getCurrentAuthState()
        if case .needsRefresh(let auth) = state {
            if case .success(let newCredential) = await tokenRefresh(auth) {
                LabsKeychain.savePlatformCredential(newCredential)
            } else {
                return state
            }
            
            return await getRefreshedAuthState()
        }
        
        return getCurrentAuthState()
    }
    
    
}

// MARK: Internal Network Requests
extension LabsPlatform {
    func tokenPostRequest(_ parameters: [String:String]) async -> Result<PlatformAuthCredentials, any Error> {
        let parameterArray = parameters.map { "\($0.key)=\($0.value)" }
        let postString = parameterArray.joined(separator: "&")
        
        let postData =  postString.data(using: .utf8)

        var request = URLRequest(url: LabsPlatform.tokenEndpoint)
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        request.httpBody = postData

        guard let (data, response) = try? await URLSession.shared.data(for: request), let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 else {
            return .failure(CancellationError())
        }
        
        let json = JSONDecoder()
        json.keyDecodingStrategy = .convertFromSnakeCase
        
        guard let data = try? json.decode(PlatformAuthCredentials.self, from: data) else {
            return .failure(DecodingError.valueNotFound(PlatformAuthCredentials.self, DecodingError.Context(codingPath: [], debugDescription: "Could not decode credentials")))
        }
        
        return .success(data)
    }
    
    func tokenRefresh(_ auth: PlatformAuthCredentials) async -> Result<PlatformAuthCredentials, any Error> {
        let parameters: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": auth.refreshToken,
            "client_id": self.clientId
        ]
        let parameterArray = parameters.map { "\($0.key)=\($0.value)" }
        let postString = parameterArray.joined(separator: "&")
        
        let postData =  postString.data(using: .utf8)
        
        var request = URLRequest(url: LabsPlatform.tokenEndpoint)
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        request.httpBody = postData
        
        guard let (data, response) = try? await URLSession.shared.data(for: request), let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 else {
            return .failure(CancellationError())
        }
        
        let json = JSONDecoder()
        json.keyDecodingStrategy = .convertFromSnakeCase
        
        guard let data = try? json.decode(PlatformAuthCredentials.self, from: data) else {
            return .failure(DecodingError.valueNotFound(PlatformAuthCredentials.self, DecodingError.Context(codingPath: [], debugDescription: "Could not decode credentials")))
        }
        
        return .success(data)
    }
}

struct PlatformAuthLoadingView: View {
    var body: some View {
        VStack(alignment: .center) {
            Text("Penn Labs")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Loading your account details...")
                .italic()
            ProgressView()
        }
    }
}


struct PlatformAuthCredentials: Codable, Equatable {
    let accessToken: String
    let expiresIn: Int
    let tokenType: String
    let refreshToken: String
    let idToken: String?
    let issuedAt: Date
    
    private init(accessToken: String, expiresIn: Int, tokenType: String, refreshToken: String, idToken: String, issuedAt: Date) {
        self.tokenType = tokenType
        self.idToken = idToken
        self.accessToken = accessToken
        self.expiresIn = expiresIn
        self.issuedAt = issuedAt
        self.refreshToken = refreshToken
    }
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.accessToken = try container.decode(String.self, forKey: .accessToken)
        self.expiresIn = try container.decode(Int.self, forKey: .expiresIn)
        self.tokenType = try container.decode(String.self, forKey: .tokenType)
        self.refreshToken = try container.decode(String.self, forKey: .refreshToken)
        self.idToken = try container.decode(String.self, forKey: .idToken)
        
        // IssuedAt time calculated this way because an auth credential can also be decoded from Keychain
        // and doing so would cause the date to change. This way, we use the date in the struct unless it doesn't exist.
        self.issuedAt = (try? container.decode(Date.self, forKey: .issuedAt)) ?? Date.now
    }
    
    static let defaultValue: PlatformAuthCredentials = .init(
        accessToken: "",
        expiresIn: Int.max,
        tokenType: "",
        refreshToken: "",
        idToken: "",
        issuedAt: Date.now
    )
    
    
    
}

enum PlatformAuthState: Sendable {
    case idle
    case loggedOut
    case newLogin(url: URL, state: String, verifier: String)
    case codeAcquired(result: AuthCompletionResult, verifier: String)
    case refreshing(state: String)
    case needsRefresh(auth: PlatformAuthCredentials)
    case loggedIn(auth: PlatformAuthCredentials)
}

enum PlatformAuthError: Error {
    case invalidUrl
    case invalidCallback
    case illegalState
    case authTimeout
}

struct AuthCompletionResult {
    let authCode: String
    let state: String
}
