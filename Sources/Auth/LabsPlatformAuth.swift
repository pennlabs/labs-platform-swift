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
        switch authState {
        case .loggedOut:
            self.authState = .newLogin(state: AuthUtilities.stateString(), verifier: AuthUtilities.codeVerifier())
            break
        case .newLogin(_, _), .refreshing(_):
            break
        default:
            break
//        case .needsRefresh(auth: let auth):
//            <#generate state#>
//        case .loggedIn(auth: let auth):
//            <#prompt logout?#>
        }
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
        
        //form post request
        
        //also cache
    }
    
    
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
