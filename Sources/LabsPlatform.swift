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
    @Published var authState: PlatformAuthState = .idle
    @Published var alertText: String? = nil
    @Published var globalLoading = false
    
    let clientId: String
    let authRedirect: String
    var webViewCheckedContinuation: CheckedContinuation<PlatformAuthState, any Error>?
    
    
    public init(clientId: String, redirectUrl: String) {
        self.clientId = clientId
        self.authRedirect = redirectUrl
        self.analytics = Analytics()
        self.authState = getCurrentAuthState()
        LabsPlatform.shared = self
        UserDefaults.standard.loadPlatformHTTPCookies()
    }
    
    public var isLoggedIn: Bool {
        switch self.authState {
        case .loggedIn(_), .needsRefresh(_):
            return true
        default:
            return false
        }
    }
}

struct PlatformProvider<Content: View>: View {
    @StateObject var platform: LabsPlatform
    @Environment(\.scenePhase) var scenePhase
    let content: Content
    let analyticsRoot: String
    let loginHandler: (Bool) async -> ()
    let defaultLoginHandler: (() -> ())?
    
    init(analyticsRoot: String, clientId: String, redirectUrl: String, loginHandler: @escaping (Bool) async -> (), defaultLoginHandler: (() -> ())? = nil, @ViewBuilder content: @escaping () -> Content) {
        self._platform = StateObject(wrappedValue: LabsPlatform(clientId: clientId, redirectUrl: redirectUrl))
        self.analyticsRoot = analyticsRoot
        self.content = content()
        self.loginHandler = loginHandler
        self.defaultLoginHandler = defaultLoginHandler
    }
    

    var body: some View {
        let showSheet = Binding(get: { platform.webViewUrl != nil }) { new in
            if platform.webViewUrl != nil && !new {
                platform.cancelLogin()
            }
        }
        
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
                DispatchQueue.main.async {
                    Task {
                        await platform.analytics.focusChanged(scenePhase)
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
                
                platform.webViewUrl = nil
                platform.webViewCheckedContinuation = nil
                
                if !defaultLogin {
                    DispatchQueue.main.async {
                        Task {
                            await self.loginHandler(result)
                        }
                    }
                }

            }
            .onAppear {
                DispatchQueue.main.async {
                    Task {
                        await self.loginHandler(platform.isLoggedIn)
                    }
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
    @ViewBuilder func enableLabsPlatform(analyticsRoot: String, clientId: String, redirectUrl: String, defaultLoginHandler: (() -> ())? = nil, _ loginHandler: @escaping (Bool) async -> ()) -> some View {
        PlatformProvider(analyticsRoot: analyticsRoot, clientId: clientId, redirectUrl: redirectUrl, loginHandler: loginHandler, defaultLoginHandler: defaultLoginHandler) {
            self
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
