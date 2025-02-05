//
//  AuthWebView.swift
//  LabsPlatformSwift
//
//  Created by Jonathan Melitski on 1/31/25.
//

import SwiftUI
import WebKit


// TODO: This should probably be refactored
struct AuthWebView: View {
    
    var url: URL?
    
    @ObservedObject var platform: LabsPlatform
    
    init(platform: LabsPlatform) {
        self.platform = platform
        if case .newLogin(let state, let verifier) = platform.authState {
            self.url = URL(string:
                            "\(LabsPlatform.authEndpoint)?response_type=code&code_challenge=\(AuthUtilities.codeChallenge(from: verifier))&code_challenge_method=S256&client_id=\(platform.clientId)&redirect_uri=\(platform.redirectUrl.absoluteString)&scope=openid%20read&state=\(state)")
        }
    }
    
    
    
    var body: some View {
        if let authUrl = url {
            AuthWebViewRepresentable(url: authUrl) { res in
                switch res {
                case .success(let authCode):
                    Task {
                        await platform.fetchToken(authCode: authCode)
                    }
                    break
                case .failure(let err):
                    platform.authState = .loggedOut
                    break
                }
            }
        }
        
    }
}

struct AuthWebViewRepresentable: UIViewRepresentable {
    let url: URL
    
    let nav = AuthNavigationDelegate()
    let completion: (Result<AuthCompletionResult, Error>) -> ()
    
    init(url: URL, completion: @escaping (Result<AuthCompletionResult, Error>) -> ()) {
        self.url = url
        self.completion = completion
        // This probably isn't great practice, passing a completion closure down to children
        nav.completion = completion
    }

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.load(URLRequest(url: url))
        view.navigationDelegate = nav
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.load(URLRequest(url: url))
    }
    
    
    
    class AuthNavigationDelegate: NSObject, WKNavigationDelegate {
        var completion: (Result<AuthCompletionResult, Error>) -> () = { _ in }
        
        func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
            guard let url: URL = webView.url, let comps = URLComponents(string: url.absoluteString) else {
                return
            }
            
            if url.absoluteString.hasPrefix("https://pennlabs.org/pennmobile/ios/callback/") {
                guard let code = comps.queryItems?.first(where: { $0.name == "code"})?.value, let state = comps.queryItems?.first(where: {$0.name == "state"})?.value else {
                    completion(.failure(NSError(domain: "Invalid URL", code: 0, userInfo: nil)))
                    return
                }
                                                          
                completion(.success(AuthCompletionResult(authCode: code, state: state)))
              }
          }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            completion(.failure(error))
        }
    }
    
}


