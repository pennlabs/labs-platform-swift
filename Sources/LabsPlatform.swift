//
//  LabsPlatform.swift
//  LabsPlatformSwift
//
//  Created by Jonathan Melitski on 12/6/24.
//

import Foundation
import SwiftUI
import UIKit

@MainActor
public final class LabsPlatform: ObservableObject {
    public static var authEndpoint = URL(string: "https://platform.pennlabs.org/accounts/authorize")!
    public static var tokenEndpoint = URL(string: "https://platform.pennlabs.org/accounts/token/")!
    public static var defaultAccount = "root"
    public static var defaultPassword = "root"
    
    public private(set) static var shared: LabsPlatform?
    
    @Published var analytics: Analytics
    @Published var authState: PlatformAuthState = .loggedOut
    @State var webViewUrl: URL?
    let clientId: String
    let authRedirect: String
    var loginTask: Task<Void, Never>?
    let defaultLoginHandler: (() -> ())?
    
    public init(clientId: String, redirectUrl: String, defaultLoginHandler: (() -> ())? = nil) {
        self.clientId = clientId
        self.authRedirect = redirectUrl
        self.defaultLoginHandler = defaultLoginHandler
        self.analytics = Analytics()
        self.authState = getCurrentAuthState()
        LabsPlatform.shared = self
    }
    
}

struct PlatformProvider<Content: View>: View {
    @ObservedObject var platform: LabsPlatform
    var content: () -> Content
    
    init(clientId: String, redirectUrl: String, defaultLoginHandler: (() -> ())? = nil, content: @escaping () -> Content) {
        self.platform = LabsPlatform(clientId: clientId, redirectUrl: redirectUrl, defaultLoginHandler: defaultLoginHandler)
        self.content = content
    }

    var body: some View {
        let showSheet = Binding { platform.webViewUrl != nil } set: { new in
            if platform.webViewUrl != nil && !new {
                platform.cancelLogin()
            }
        }
        
        content()
            .environmentObject(platform)
            .sheet(isPresented: showSheet) {
                if platform.webViewUrl != nil {
                    AuthWebView(url: platform.webViewUrl!, redirect: platform.authRedirect, callback: platform.handleCallback)
                } else {
                    PlatformAuthLoadingView()
                }
            }
    }
}

public extension View {
    /// Enables Labs Platform for all subviews.
    ///
    /// > Note: This should be called on the highest SwiftUI View in the view hierarchy, regardless of whether there is a guest mode or not.
    /// > That is, call this method at the highest view in the viewport, then at the time of login, call [`LabsPlatform.loginWithPlatform()`](x-source-tag://loginWithPlatform)
    ///
    /// - Parameters:
    ///     - clientId: A Platform-granted clientId that has permission to get JWTs
    ///     - redirectUrl: A valid redirect URI (allowed by the Platform application)
    ///     - defaultLoginHandler: A function that should be called when the login flow intercepts the default login credentials (user and password both "root", by default)
    ///
    /// - Returns: The original view with a `LabsPlatform.Analytics` environment object. The  `LabsPlatform` instance can be accessed as a singleton: `LabsPlatform.instance`.
    /// - Tag: enableLabsPlatform
    func enableLabsPlatform(clientId: String, redirectUrl: String, defaultLoginHandler: (() -> ())? = nil) -> some View {
        return PlatformProvider(clientId: clientId, redirectUrl: redirectUrl, defaultLoginHandler: defaultLoginHandler) {
            self
        }
    }
}
