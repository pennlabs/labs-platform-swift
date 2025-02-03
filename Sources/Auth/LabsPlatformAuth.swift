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
        beginLogin()
    }
    
    func beginLogin() {
        self.authState = .newLogin(state: AuthUtilities.stateString(), verifier: AuthUtilities.codeVerifier())
    }
    
    func fetchToken(authCode: AuthCompletionResult) async {
        guard case .newLogin(let currentState, let verifier) = authState, currentState == authCode.state else {
            authState = .loggedOut
            print("OAuth state did not match! This could be a bug, or a sign of a highly sophisticated CSRF attack.")
            exit(1)
        }
        
        self.authState = .fetchingJwt(state: currentState, verifier: verifier)
        
        let parameters: [String: String] = [
            "grant_type": "authorization_code",
            "code": authCode.authCode,
            "redirect_uri": self.redirectUrl.absoluteString,
            "client_id": self.clientId,
            "code_verifier": verifier,
        ]
        
        guard case .success(let credentials) = await tokenPostRequest(parameters) else {
            self.authState = .loggedOut
            return
        }
        
        self.authState = .loggedIn(auth: credentials)
        LabsKeychain.savePlatformCredential(credentials)
    }
    
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
            //return .success(PlatformAuthCredentials(accessToken: "", expiresIn: 0, tokenType: "", refreshToken: "", idToken: ""))
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
}

enum PlatformAuthState {
    case loggedOut
    case newLogin(state: String, verifier: String)
    case fetchingJwt(state: String, verifier: String)
    case refreshing(state: String)
    case needsRefresh(auth: PlatformAuthCredentials)
    case loggedIn(auth: PlatformAuthCredentials)
    
    var showWebViewSheet: Bool {
        switch self {
        case .newLogin(_,_), .fetchingJwt(_, _):
            return true
        default:
            return false
        }
    }
}
