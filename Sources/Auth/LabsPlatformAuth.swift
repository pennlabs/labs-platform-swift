//
//  LabsPlatformAuth.swift
//  LabsPlatformSwift
//
//  Created by Jonathan Melitski on 1/31/25.
//

import Foundation

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
    
    func fetchToken(authCode: AuthCompletionResult) {
        guard case .newLogin(let currentState, let verifier) = authState, currentState == authCode.state else {
            authState = .loggedOut
            print("OAuth state did not match! This could be a bug, or a sign of a highly sophisticated CSRF attack.")
            exit(1)
        }
        
        let parameters: [String: String] = [
            "grant_type": "authorization_code",
            "code": authCode.authCode,
            "redirect_uri": self.redirectUrl.absoluteString,
            "client_id": self.clientId,
            "code_verifier": verifier,
            "state": authCode.state
        ]
        let parameterArray = parameters.map { "\($0.key)=\($0.value)" }
        let postString = parameterArray.joined(separator: "&")
        
        let postData =  postString.data(using: .utf8)

        var request = URLRequest(url: LabsPlatform.tokenEndpoint)
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        request.httpBody = postData

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
          guard let data = data else {
            print(String(describing: error))
            return
          }
          print(String(data: data, encoding: .utf8)!)
        }

        task.resume()
        //form post request
        
        //also cache
        
        //TEMPORARY
        authState = .loggedOut
        print(authCode)
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
    case refreshing(state: String)
    case needsRefresh(auth: PlatformAuthCredentials)
    case loggedIn(auth: PlatformAuthCredentials)
    
    var showWebViewSheet: Bool {
        switch self {
        case .newLogin(_,_):
            return true
        default:
            return false
        }
    }
}
