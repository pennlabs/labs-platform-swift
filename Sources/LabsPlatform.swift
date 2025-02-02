//
//  LabsPlatform.swift
//  LabsPlatformSwift
//
//  Created by Jonathan Melitski on 12/6/24.
//

import Foundation
import SwiftUI
import UIKit
import CommonCrypto

public class LabsPlatform: ObservableObject {
    public static let authEndpoint = URL(string: "https://platform.pennlabs.org/accounts/authorize")!
    public static let tokenEndpoint = URL(string: "https://platform.pennlabs.org/accounts/token/")!
    
    @Published var authState: PlatformAuthState = .loggedOut
    let clientId: String
    let redirectUrl: URL
    var verifier: String?
    
    
    
    public init(clientId: String, redirectUrl: URL) {
        // get initial state from cache
        self.clientId = clientId
        self.redirectUrl = redirectUrl
    }
    
    
    func beginLogin() {
        switch authState {
        case .loggedOut:
            let alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ123456789"
            
            let state = alphabet.shuffled().prefix(8).compactMap { String($0) }.joined()
            self.authState = .newLogin(state: state)
            self.verifier = LabsPlatform.newCodeVerifier()
            break
        case .newLogin(_), .refreshing(_):
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
    
    
    static func newCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    static func codeChallenge(from verifier: String) -> String {
        let data = verifier.data(using: .utf8)!
        var buffer = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        _ = data.withUnsafeBytes {
            CC_SHA256($0.baseAddress, CC_LONG(data.count), &buffer)
        }
        let hash = Data(buffer)
        return hash.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

struct PlatformProvider<Content: View>: View {
    @ObservedObject var platform: LabsPlatform

    var content: () -> Content

    init(_ platform: LabsPlatform, @ViewBuilder content: @escaping () -> Content) {
        self.platform = platform
        self.content = content
    }
    
    

    var body: some View {
        let showSheet = Binding {
            if case .newLogin(_) = platform.authState, let _ = platform.verifier {
                return true
            }
            return false
        } set: { new in
            platform.authState = new ? platform.authState : .loggedOut
        }
        
        content()
            .environmentObject(platform)
            .onTapGesture(perform: platform.beginLogin)
            .sheet(isPresented: showSheet) {
                AuthWebView(platform: platform, challenge: LabsPlatform.codeChallenge(from: platform.verifier!))
            }
    }
}

public extension View {
    func enableLabsPlatform(clientId: String,
                            redirectUrl: URL) -> some View {
        let platform = LabsPlatform(clientId: clientId, redirectUrl: redirectUrl)
        
        return (
            PlatformProvider(platform) {
                self
            }
        )
            
    }
}


#Preview {
    Text("Hello, World!")
        .enableLabsPlatform(clientId: "REDACTED", redirectUrl: URL(string: "https://pennlabs.org/pennmobile/ios/callback/")!)
}
