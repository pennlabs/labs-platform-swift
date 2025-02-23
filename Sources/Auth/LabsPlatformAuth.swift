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
            fetchToken
        ]
        
        Task {
            for phase in phases {
                do {
                    self.authState = try await phase()
                    //                    if case .cancelled = self.authState {
                    //                        break
                    //                    }
                } catch {
                    self.authState = .loggedOut
                    self.loginHandler(false)
                }
            }
            
            if case .loggedIn(let credential) = self.authState {
                LabsKeychain.savePlatformCredential(credential)
                self.loginHandler(true)
            }
        }
    }
    
// MARK: Top-level Auth Flow Functions
    func prepareLogin() throws -> PlatformAuthState {
        let verifier: String = AuthUtilities.codeVerifier()
        let state: String = AuthUtilities.stateString()
        guard let url = URL(string:
                                "\(LabsPlatform.authEndpoint.absoluteString)?response_type=code&code_challenge=\(AuthUtilities.codeChallenge(from: verifier))&code_challenge_method=S256&client_id=\(self.clientId)&redirect_uri=\(self.authRedirect)&scope=openid%20read&state=\(state)") else { throw PlatformAuthError.invalidUrl }
        return .newLogin(url: url, state: state, verifier: verifier)
    }
    
    func fetchAccessCode() async throws -> PlatformAuthState {
        guard case .newLogin(let url, let state, let verifier) = self.authState else {
            throw PlatformAuthError.illegalState
        }
        
        await MainActor.run {
            self.webViewUrl = url
        }
        
        // Timeout login request after 2 minutes
        let startTime = Date.now
        
        let taskLoop = Task {
            while Date.now.timeIntervalSince(startTime) < 120 {
                if case .codeAcquired(let code) = self.authState {
                    return PlatformAuthState.fetchingJwt(code: code.authCode, state: state, verifier: verifier)
                }
                
                // Default login case (handled in the completeDefaultLogin function)
                if case .loggedIn(_) = self.authState {
                    return self.authState
                }
            }
            throw PlatformAuthError.authTimeout
        }
        
        return try await taskLoop.value
        
    }
    
    func fetchToken() async throws -> PlatformAuthState {
        guard case .fetchingJwt(let code, _, let verifier) = self.authState else {
            throw PlatformAuthError.illegalState
        }
        
        let parameters: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
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
        self.webViewUrl = nil
        self.authState = .cancelled
    }
    
    func completeDefaultLogin() {
        self.webViewUrl = nil
        self.defaultLoginHandler?()
        self.authState = .loggedIn(auth: PlatformAuthCredentials.defaultValue)
    }
    
// MARK: Other functions
    func handleCallback(callbackResult: Result<URL, any Error>) {
        guard case .success(let url) = callbackResult,
              case .newLogin(_, let currentState, _) = self.authState,
              let comps = URLComponents(string: url.absoluteString) else {
            self.cancelLogin()
            return
        }
        
        if let defaultLogin = comps.queryItems?.first(where: {$0.name == "defaultlogin"})?.value,
           defaultLogin == "true" {
            self.completeDefaultLogin()
            return
        }
        
        guard let code = comps.queryItems?.first(where: { $0.name == "code"})?.value,
              let state = comps.queryItems?.first(where: {$0.name == "state"})?.value,
              currentState == state else {
            self.cancelLogin()
            return
        }
        
        self.authState = .codeAcquired(result: AuthCompletionResult(authCode: code, state: state))
    }
    
// MARK: Setup + Refresh
    func getCurrentAuthState() -> PlatformAuthState {
        guard let credential = LabsKeychain.loadPlatformCredential() else {
            return .loggedOut
        }
        
        if credential.issuedAt.addingTimeInterval(TimeInterval(credential.expiresIn)) < Date.now {
            return .needsRefresh(auth: credential)
        } else {
            return .loggedIn(auth: credential)
        }
    }
    
    func getRefreshedAuthState() async -> PlatformAuthState {
        if case .needsRefresh(let auth) = getCurrentAuthState() {
            if case .success(let newCredential) = await tokenRefresh(auth) {
                LabsKeychain.savePlatformCredential(newCredential)
            } else {
                LabsKeychain.clearPlatformCredential()
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


struct PlatformAuthCredentials: Codable {
    let accessToken: String
    let expiresIn: Int
    let tokenType: String
    let refreshToken: String
    let idToken: String
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
    case loggedOut
    case newLogin(url: URL, state: String, verifier: String)
    case codeAcquired(result: AuthCompletionResult)
    case fetchingJwt(code: String, state: String, verifier: String)
    case refreshing(state: String)
    case needsRefresh(auth: PlatformAuthCredentials)
    case loggedIn(auth: PlatformAuthCredentials)
    case cancelled
}

enum PlatformAuthError: Error {
    case invalidUrl
    case illegalState
    case authTimeout
}

struct AuthCompletionResult {
    let authCode: String
    let state: String
}
