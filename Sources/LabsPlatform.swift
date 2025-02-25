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
    @Published var webViewUrl: URL?
    
    var authState: PlatformAuthState = .idle {
        didSet {
            switch authState {
            case .loggedOut:
                webViewUrl = nil
                webViewCheckedContinuation = nil
                
                // Note, don't reset the stored analytics queue in UserDefaults, because they
                // may log back in and we would want to submit them then (assuming
                // the transactions haven't timed out)
                LabsKeychain.clearPlatformCredential()
                LabsKeychain.deletePennkey()
                LabsKeychain.deletePassword()
                
                self.loginHandler(false)
            case .loggedIn(auth: let auth):
                self.webViewUrl = nil
                self.webViewCheckedContinuation = nil
                
                LabsKeychain.savePlatformCredential(auth)
                if auth == PlatformAuthCredentials.defaultValue {
                    self.defaultLoginHandler?()
                } else {
                    self.loginHandler(true)
                }
            default:
                break
            }
            
        }
    }
    let clientId: String
    let authRedirect: String
    let loginHandler: (Bool) -> ()
    let defaultLoginHandler: (() -> ())?
    var webViewCheckedContinuation: CheckedContinuation<PlatformAuthState, any Error>?
    
    
    public init(clientId: String, redirectUrl: String, loginHandler: @escaping (Bool) -> (), defaultLoginHandler: (() -> ())? = nil) {
        self.clientId = clientId
        self.authRedirect = redirectUrl
        self.loginHandler = loginHandler
        self.defaultLoginHandler = defaultLoginHandler
        self.analytics = Analytics()
        self.authState = getCurrentAuthState()
        LabsPlatform.shared = self
        self.loginHandler(isLoggedIn())
    }
    
    public func isLoggedIn() -> Bool {
        if case .loggedOut = self.authState {
            return false
        } else {
            return true
        }
    }
}

struct PlatformProvider<Content: View>: View {
    @StateObject var platform: LabsPlatform
    @Environment(\.scenePhase) var scenePhase
    let content: Content
    let analyticsRoot: String
    
    init(analyticsRoot: String, clientId: String, redirectUrl: String, loginHandler: @escaping (Bool) -> (), defaultLoginHandler: (() -> ())? = nil, @ViewBuilder content: @escaping () -> Content) {
        self._platform = StateObject(wrappedValue: LabsPlatform(clientId: clientId, redirectUrl: redirectUrl, loginHandler: loginHandler, defaultLoginHandler: defaultLoginHandler))
        self.analyticsRoot = analyticsRoot
        self.content = content()
    }
    

    var body: some View {
        let showSheet = Binding(get: { platform.webViewUrl != nil }) { new in
            if platform.webViewUrl != nil && !new {
                platform.cancelLogin()
            }
        }
        
        
        content
            .environment(\.labsAnalyticsPath, analyticsRoot)
            .sheet(isPresented: showSheet) {
                ZStack {
                    HStack {
                        Spacer()
                        Text("PennKey Login")
                            .bold()
                            .padding(.vertical, 24)
                            .padding(.horizontal)
                        Spacer()
                    }
                    HStack {
                        Spacer()
                        Button("Cancel") {
                            platform.cancelLogin()
                        }
                        .padding(.vertical, 24)
                        .padding(.horizontal)
                    }
                }
                .background(.thickMaterial)
                AuthWebView(url: platform.webViewUrl!, redirect: platform.authRedirect, callback: platform.urlCallbackFunction)
            }
            .onChange(of: scenePhase) { _ in
                Task {
                    await platform.analytics.focusChanged(scenePhase)
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
    ///     - loginHandler(loggedIn: Bool): a function that will be called whenever the Platform goes to either the logged-in state or the logged-out state. This includes
    ///             uses of the [`LabsPlatform.logoutPlatform()`](x-source-tag://logoutPlatform) function (will always be `false`)
    ///
    /// - Returns: The original view with a `LabsPlatform.Analytics` environment object. The  `LabsPlatform` instance can be accessed as a singleton: `LabsPlatform.shared`, though this is not recommended except for cases when logging in or out.
    /// - Tag: enableLabsPlatform
    @ViewBuilder func enableLabsPlatform(analyticsRoot: String, clientId: String, redirectUrl: String, defaultLoginHandler: (() -> ())? = nil, _ loginHandler: @escaping (Bool) -> ()) -> some View {
        PlatformProvider(analyticsRoot: analyticsRoot, clientId: clientId, redirectUrl: redirectUrl, loginHandler: loginHandler, defaultLoginHandler: defaultLoginHandler) {
            self
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
