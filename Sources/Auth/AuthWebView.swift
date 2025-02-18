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
            if isLoading {
                ProgressView()
                    .padding()
                    .background(.ultraThickMaterial)
                    .clipShape(.rect(cornerRadius: 8))
            }
            
        }
        
    }
}


struct AuthWebViewRepresentable: UIViewRepresentable {
    let url: URL
    
    let nav: AuthNavigationDelegate
    let completion: (Result<URL, any Error>) -> ()
    @Binding var isLoading: Bool
    
    init(url: URL, redirect: String, isLoading: Binding<Bool>, completion: @escaping (Result<URL, any Error>) -> ()) {
        self.url = url
        self.completion = completion
        self._isLoading = isLoading
        self.nav = AuthNavigationDelegate(redirect: redirect, isLoading: isLoading, callback: completion)
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
}


class AuthNavigationDelegate: NSObject, WKNavigationDelegate {
    let callback: (Result<URL, any Error>) -> ()
    let redirect: String
    @Binding var isLoading: Bool
    
    private let loginScreen = "https://weblogin.pennkey.upenn.edu/idp/profile/SAML2/Redirect/SSO?execution=e1"
    private let platformPermissionScreen = "https://platform.pennlabs.org/accounts/authorize/"
    
    init(redirect: String, isLoading: Binding<Bool>, callback: @escaping (Result<URL, any Error>) -> Void) {
        self.redirect = redirect
        self._isLoading = isLoading
        self.callback = callback
    }
    
    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        guard let url: URL = webView.url else {
            return
        }
        
        if url.absoluteString.hasPrefix(platformPermissionScreen) {
            webView.isUserInteractionEnabled = true
            isLoading = false
        }
        
        if url.absoluteString.hasPrefix(redirect) {
            callback(.success(url))
          }
      }
    
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let request = navigationAction.request
        guard let _ = request.url else {
            decisionHandler(.allow)
            return
        }
            
        if navigationAction.navigationType == .formSubmitted,
           webView.url?.absoluteString.contains(loginScreen) == true {
            webView.evaluateJavaScript("document.querySelector('input[name=j_username]').value;") { (result, _) in
                if let pennkey = result as? String {
                    webView.evaluateJavaScript("document.querySelector('input[name=j_password]').value;") { (result, _) in
                        if let password = result as? String {
                            if !pennkey.isEmpty && !password.isEmpty {
                                print(pennkey)
                                print(password)
                                
                                if pennkey == "root" && password == "root" {
                                    self.callback(.success(URL(string: "\(self.redirect)?defaultlogin=true")!))
                                    decisionHandler(.cancel)
                                    return
                                }
                            }
                        }
                    }
                }
            }
            decisionHandler(.allow)
            webView.isUserInteractionEnabled = false
            isLoading = true
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        callback(.failure(error))
    }
}
