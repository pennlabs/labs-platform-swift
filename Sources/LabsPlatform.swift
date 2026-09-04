//
//  LabsPlatform.swift
//  LabsPlatformSwift
//
//  Created by Jonathan Melitski on 12/6/24.
//

import Foundation
import SwiftUI
import UIKit
import AuthenticationServices

@MainActor
public final class LabsPlatform: ObservableObject {
    public struct Configuration: Sendable {
        let authEndpoint: URL
        let tokenEndpoint: URL
        let defaultAccount: String
        let defaultPassword: String
        
        let analyticsConfiguration: Analytics.Configuration?
        
        public init(authEndpoint: URL = URL(string: "https://platform.pennlabs.org/accounts/authorize")!,
                    tokenEndpoint: URL = URL(string: "https://platform.pennlabs.org/accounts/token/")!,
                    defaultAccount: String = "root",
                    defaultPassword: String = "root",
                    analyticsConfiguration: Analytics.Configuration? = Analytics.Configuration()) {
            self.authEndpoint = authEndpoint
            self.tokenEndpoint = tokenEndpoint
            self.defaultAccount = defaultAccount
            self.defaultPassword = defaultPassword
            self.analyticsConfiguration = analyticsConfiguration
        }
    }
    
    public private(set) static var shared: LabsPlatform?
    
    @Published var analytics: Analytics?
    @Published var authState: PlatformAuthState = .idle
    @Published var alertText: String? = nil
    @Published var globalLoading = false
    
    let clientId: String
    let authRedirect: String
    
    let configuration: Configuration
    
    var refreshTask: Task<PlatformAuthState, Never>? = nil
    var webAuthenticationSession: WebAuthenticationSession? = nil
    
    
    public init(clientId: String, redirectUrl: String, configuration: Configuration = Configuration()) {
        self.clientId = clientId
        self.authRedirect = redirectUrl
        self.configuration = configuration
        
        self.authState = getCurrentAuthState()
        self.analytics = try? Analytics(configuration: configuration.analyticsConfiguration)
        
        LabsPlatform.shared = self
        UserDefaults.standard.loadPlatformHTTPCookies()
    }
    
    public var isLoggedIn: Bool {
        switch self.authState {
        case .loggedIn(_), .needsRefresh(_), .refreshing(_):
            return true
        default:
            return false
        }
    }
    
    internal func setWebAuthenticationSession(_ session: WebAuthenticationSession) {
        self.webAuthenticationSession = session
    }
}

struct PlatformProvider<Content: View>: View {
    @ObservedObject var platform: LabsPlatform
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    let content: Content
    let analyticsRoot: String
    let loginHandler: (Bool) -> ()
    let defaultLoginHandler: (() -> ())?
    

    init(analyticsRoot: String, clientId: String, redirectUrl: String, configuration: LabsPlatform.Configuration, loginHandler: @escaping (Bool) -> (), defaultLoginHandler: (() -> ())? = nil, @ViewBuilder content: @escaping () -> Content) {
        if LabsPlatform.shared == nil {
            _ = LabsPlatform(clientId: clientId, redirectUrl: redirectUrl, configuration: configuration)
        }
        self._platform = ObservedObject(initialValue: LabsPlatform.shared!)
        self.analyticsRoot = analyticsRoot
        self.content = content()
        self.loginHandler = loginHandler
        self.defaultLoginHandler = defaultLoginHandler
    }
    

    var body: some View {
        let showAlert = Binding(get: { platform.alertText != nil }) { new in
            if platform.alertText != nil && !new {
                platform.alertText = nil
            }
        }
        
        ZStack {
            content
            if platform.globalLoading {
                Color.black.opacity(0.1)
                    .ignoresSafeArea()

                ProgressView()
                    .tint(nil)
                    .scaleEffect(1.6)
                    .frame(width: 100, height: 100)
                    .background(.thickMaterial)
                    .cornerRadius(16)
            }
        }
            .environment(\.labsAnalyticsPath, analyticsRoot)
            .alert(isPresented: showAlert) {
                Alert(title: Text("Error"), message: Text(platform.alertText ?? "There was an error."))
            }
            .onChange(of: scenePhase) {
                DispatchQueue.main.async {
                    Task {
                        await platform.analytics?.focusChanged(scenePhase)
                    }
                }
            }
            .onChange(of: platform.authState) { oldValue, newValue in
                if platform.authState == oldValue {
                    return
                }
                
                var result = false
                var defaultLogin = false
                
                switch platform.authState {
                case .loggedOut:
                    // Note, don't reset the stored analytics queue in UserDefaults, because they
                    // may log back in and we would want to submit them then (assuming
                    // the transactions haven't timed out)
                    LabsKeychain.clearPlatformCredential()
                    LabsKeychain.deletePennkey()
                    LabsKeychain.deletePassword()
                    
                case .loggedIn(auth: let auth), .needsRefresh(auth: let auth):
                    LabsKeychain.savePlatformCredential(auth)
                    if auth == PlatformAuthCredentials.defaultValue {
                        self.defaultLoginHandler?()
                        defaultLogin = true
                    } else {
                        result = true
                    }
                    
                default:
                    // Do not run anything in the event that we are in the
                    // middle of an auth flow
                    return
                }
                
                if !defaultLogin {
                    self.loginHandler(result)
                }

            }
            .onAppear {
                self.loginHandler(platform.isLoggedIn)
                self.platform.setWebAuthenticationSession(webAuthenticationSession)
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
    ///     - configuration: An overridden configuration object (for when specific behavior modification is desired)
    ///     - defaultLoginHandler: A function that should be called when the login flow intercepts the default login credentials (user and password both "root", by default)
    ///     - loginHandler(loggedIn: Bool): a function that will be called whenever the Platform goes to either the logged-in state or the logged-out state. This includes
    ///             uses of the [`LabsPlatform.logoutPlatform()`](x-source-tag://logoutPlatform) function (will always be `false`)
    ///
    /// - Returns: The original view with a `LabsPlatform.Analytics` environment object. The  `LabsPlatform` instance can be accessed as a singleton: `LabsPlatform.shared`, though this is not recommended except for cases when logging in or out.
    /// - Tag: enableLabsPlatform
    @ViewBuilder func enableLabsPlatform(analyticsRoot: String, clientId: String, redirectUrl: String, configuration: LabsPlatform.Configuration = LabsPlatform.Configuration(), defaultLoginHandler: (() -> ())? = nil, _ loginHandler: @escaping (Bool) -> ()) -> some View {
        PlatformProvider(analyticsRoot: analyticsRoot, clientId: clientId, redirectUrl: redirectUrl, configuration: configuration, loginHandler: loginHandler, defaultLoginHandler: defaultLoginHandler) {
            self
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
