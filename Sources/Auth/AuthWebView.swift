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
    
    init(url: URL, redirect: String, callback: @escaping (Result<URL, any Error>) -> ()) {
        self.url = url
        self.redirect = redirect
        self.callback = callback
    }
    
    var body: some View {
        AuthWebViewRepresentable(url: url, redirect: redirect, completion: callback)
    }
}


struct AuthWebViewRepresentable: UIViewRepresentable {
    let url: URL
    
    let nav: AuthNavigationDelegate
    let completion: (Result<URL, any Error>) -> ()
    
    init(url: URL, redirect: String, completion: @escaping (Result<URL, any Error>) -> ()) {
        self.url = url
        self.completion = completion
        self.nav = AuthNavigationDelegate(redirect: redirect, callback: completion)
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
    
    init(redirect: String, callback: @escaping (Result<URL, any Error>) -> Void) {
        self.redirect = redirect
        self.callback = callback
    }
    
    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        guard let url: URL = webView.url, let comps = URLComponents(string: url.absoluteString) else {
            return
        }
        
        if url.absoluteString.hasPrefix(redirect) {
            guard let code = comps.queryItems?.first(where: { $0.name == "code"})?.value, let state = comps.queryItems?.first(where: {$0.name == "state"})?.value else {
                callback(.failure(NSError(domain: "Invalid URL", code: 0, userInfo: nil)))
                return
            }
            callback(.success(url))
          }
      }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        callback(.failure(error))
    }
}
