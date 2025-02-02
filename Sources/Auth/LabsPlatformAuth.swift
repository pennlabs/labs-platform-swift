//
//  LabsPlatformAuth.swift
//  LabsPlatformSwift
//
//  Created by Jonathan Melitski on 1/31/25.
//

import Foundation

extension LabsPlatform {
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
