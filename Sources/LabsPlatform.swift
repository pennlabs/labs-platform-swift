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
    @Published var webViewUrl: URL?
    @Published var authState: PlatformAuthState = .idle {
        didSet { authStateDidChange(from: oldValue) }
    }
    @Published var authWebViewState: AuthWebViewState = .disabled
    @Published var alertText: String? = nil
    @Published var globalLoading = false
    
    let clientId: String
    let authRedirect: String
    
    let configuration: Configuration
    
    var refreshTask: Task<PlatformAuthState, Never>? = nil
    
    /// How many times a `RefreshFlowFailedResult.tryAgain` from the delegate is honored before the platform logs out.
    public static let maxRefreshAttempts = 3
    
    /// Receives auth, request, and analytics events. See [`LabsPlatformDelegate`](x-source-tag://LabsPlatformDelegate).
    ///
    /// Assigning a new delegate immediately reports the current logged-in state to it (if the platform is not mid-login).
    public weak var delegate: (any LabsPlatformDelegate)? {
        didSet {
            guard oldValue !== delegate, let delegate else { return }
            if let state = loggedInState(for: authState) {
                delegate.labsPlatformAuth(didUpdateLoggedInState: state, platform: self)
            }
        }
    }
    
    
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
    
    /// `true` when the current session was created with the default (App Store review) credentials.
    public var isDefaultLogin: Bool {
        switch self.authState {
        case .loggedIn(let auth), .needsRefresh(let auth):
            return auth == PlatformAuthCredentials.defaultValue
        default:
            return false
        }
    }
    
    /// The delegate-facing view of a settled auth state, or `nil` while an auth flow is in progress.
    private func loggedInState(for state: PlatformAuthState) -> (loggedIn: Bool, isDefaultLogin: Bool)? {
        switch state {
        case .loggedOut:
            return (loggedIn: false, isDefaultLogin: false)
        case .loggedIn(let auth), .needsRefresh(let auth):
            return (loggedIn: true, isDefaultLogin: auth == PlatformAuthCredentials.defaultValue)
        default:
            return nil
        }
    }
    
    /// Persists credentials and notifies the delegate whenever `authState` settles into a new logged-in/logged-out state.
    private func authStateDidChange(from oldValue: PlatformAuthState) {
        // PlatformAuthState equality only compares the case, so a refreshed credential in the same
        // state does not re-notify. Refresh persists its own credential.
        guard oldValue != authState else { return }
        
        switch authState {
        case .loggedOut:
            // Note, don't reset the stored analytics queue in UserDefaults, because they
            // may log back in and we would want to submit them then (assuming
            // the transactions haven't timed out)
            LabsKeychain.clearPlatformCredential()
            LabsKeychain.deletePennkey()
            LabsKeychain.deletePassword()
        case .loggedIn(let auth), .needsRefresh(let auth):
            LabsKeychain.savePlatformCredential(auth)
        default:
            // Do not run anything in the event that we are in the
            // middle of an auth flow
            return
        }
        
        self.authWebViewState = .disabled
        
        if let state = loggedInState(for: authState) {
            delegate?.labsPlatformAuth(didUpdateLoggedInState: state, platform: self)
        }
    }
}

struct PlatformProvider<Content: View>: View {
    @ObservedObject var platform: LabsPlatform
    @Environment(\.scenePhase) var scenePhase
    let content: Content
    let analyticsRoot: String
    

    init(analyticsRoot: String, clientId: String, redirectUrl: String, configuration: LabsPlatform.Configuration, delegate: (any LabsPlatformDelegate)?, @ViewBuilder content: @escaping () -> Content) {
        if LabsPlatform.shared == nil {
            _ = LabsPlatform(clientId: clientId, redirectUrl: redirectUrl, configuration: configuration)
        }
        self._platform = ObservedObject(initialValue: LabsPlatform.shared!)
        self.analyticsRoot = analyticsRoot
        self.content = content()
        if let delegate {
            LabsPlatform.shared!.delegate = delegate
        }
    }
    

    var body: some View {
        let authURL = Binding<URL?>(get: {
            if case let .enabled(url, _) = platform.authWebViewState {
                return url
            }
            return nil
        }) { new in
            if case .enabled(_, _) = platform.authWebViewState {
                if new == nil {
                    platform.cancelLogin()
                }
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
            .sheet(item: authURL) { url in
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
                AuthWebView(url: url, redirect: platform.authRedirect, callback: platform.urlCallbackFunction)
            }
            .onChange(of: scenePhase) { _ in
                DispatchQueue.main.async {
                    Task {
                        await platform.analytics?.focusChanged(scenePhase)
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
    ///     - configuration: An overridden configuration object (for when specific behavior modification is desired)
    ///     - delegate: An object receiving auth, request, and analytics events. See [`LabsPlatformDelegate`](x-source-tag://LabsPlatformDelegate).
    ///             The platform holds it weakly, so the caller must keep it alive (e.g. as a `@StateObject`).
    ///             Login state changes, including [`LabsPlatform.logoutPlatform()`](x-source-tag://logoutPlatform), are reported via
    ///             `labsPlatformAuth(didUpdateLoggedInState:platform:)`, and the current state is reported as soon as the delegate is attached.
    ///
    /// - Returns: The original view with a `LabsPlatform.Analytics` environment object. The  `LabsPlatform` instance can be accessed as a singleton: `LabsPlatform.shared`, though this is not recommended except for cases when logging in or out.
    /// - Tag: enableLabsPlatform
    @ViewBuilder func enableLabsPlatform(analyticsRoot: String, clientId: String, redirectUrl: String, configuration: LabsPlatform.Configuration = LabsPlatform.Configuration(), delegate: (any LabsPlatformDelegate)? = nil) -> some View {
        PlatformProvider(analyticsRoot: analyticsRoot, clientId: clientId, redirectUrl: redirectUrl, configuration: configuration, delegate: delegate) {
            self
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
