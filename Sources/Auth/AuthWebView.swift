//
//  AuthWebView.swift
//  LabsPlatformSwift
//
//  Created by Jonathan Melitski on 1/31/25.
//

import SwiftUI
import Foundation
import WebKit

struct AuthWebView: View {
    
    let url: URL
    let redirect: String
    let callback: (Result<URL, any Error>) -> ()
    @State var isLoading: Bool = false
    
    init(url: URL, redirect: String, callback: @escaping (Result<URL, any Error>) -> ()) {
        self.url = url
        self.redirect = redirect
        self.callback = callback
    }
    
    var body: some View {
        ZStack {
            AuthWebViewRepresentable(url: url, redirect: redirect, isLoading: $isLoading, completion: callback)
        }
    }
}


struct AuthWebViewRepresentable: UIViewRepresentable {
    let url: URL
    let redirect: String
    let completion: (Result<URL, any Error>) -> ()
    @Binding var isLoading: Bool
    
    init(url: URL, redirect: String, isLoading: Binding<Bool>, completion: @escaping (Result<URL, any Error>) -> ()) {
        self.url = url
        self.redirect = redirect
        self.completion = completion
        self._isLoading = isLoading
    }
    
    func makeCoordinator() -> AuthNavigationDelegate {
        AuthNavigationDelegate(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        updateUIView(view, context: context)
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.load(URLRequest(url: url))
        uiView.navigationDelegate = context.coordinator
        
        context.coordinator.parent = self
    }
}

@MainActor
class AuthNavigationDelegate: NSObject, WKNavigationDelegate {
    var parent: AuthWebViewRepresentable
    
    private let loginScreen = "https://weblogin.pennkey.upenn.edu/idp/profile/SAML2/Redirect/SSO"
    private let mfaScreen = "https://api-ecae067e.duosecurity.com/frame/v4/auth"
    private let platformPermissionScreen = "https://platform.pennlabs.org/accounts/authorize/"
    
    init(parent: AuthWebViewRepresentable) {
        self.parent = parent
    }
    
    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        guard let url: URL = webView.url else {
            return
        }
        
        if url.absoluteString.hasPrefix(mfaScreen) {
            webView.isUserInteractionEnabled = true
            parent.isLoading = false
        }
        
        if url.absoluteString.hasPrefix(parent.redirect) {
            parent.completion(.success(url))
        }
    }
    
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            let request = navigationAction.request
            guard let _ = request.url else {
                decisionHandler(.allow)
                return
            }
            
            Task {
                // Some Penn Mobile features require certain cookies given during the login process.
                let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
                UserDefaults.standard.savePlatformHTTPCookies(cookies)
                cookies.forEach { cookie in
                    HTTPCookieStorage.shared.setCookie(cookie)
                }
                
                guard navigationAction.navigationType == .formSubmitted,
                      webView.url?.absoluteString.contains(self.loginScreen) == true else {
                    decisionHandler(.allow)
                    return
                }
                
                if let pennkey = try? await webView.evaluateJavaScript("document.querySelector('input[name=j_username]').value;") as? String,
                   let password = try? await webView.evaluateJavaScript("document.querySelector('input[name=j_password]').value;") as? String,
                   !(pennkey.isEmpty || password.isEmpty) {
                    if pennkey == "root" && password == "root" {
                        // Indicate the default login using a query parameter
                        // This makes it so the default login is handled elsewhere
                        parent.completion(.success(URL(string: "\(parent.redirect)?defaultlogin=true")!))
                        // Might get rid of this
                        decisionHandler(.allow)
                        return
                    }
                    
                    LabsKeychain.savePennkey(pennkey)
                    LabsKeychain.savePassword(password)
                    
                    webView.isUserInteractionEnabled = false
                    parent.isLoading = true
                }
                decisionHandler(.allow)
            }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        parent.completion(.failure(error))
    }
}
