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
import Network

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
    @Published var authState: PlatformAuthState = .idle {
        didSet { authStateDidChange(from: oldValue) }
    }
    @Published var globalLoading = false

    let clientId: String
    let authRedirect: String

    let configuration: Configuration

    var loginTask: Task<Void, Never>?
    var refreshTask: Task<Void, Never>?
    var webAuthenticationSession: WebAuthenticationSession?

    private let pathMonitor = NWPathMonitor()
    private var pathTask: Task<Void, Never>?
    /// Mirrors `NWPathMonitor`; token refreshes are skipped while `false`.
    public internal(set) var isNetworkAvailable = true

    /// How many times a `RefreshFlowFailedResult.tryAgain` is honored before the platform logs out.
    public static let maxRefreshAttempts = 3

    /// Receives auth, request, and analytics events. Held weakly. Attaching reports the current logged-in state immediately.
    public weak var delegate: (any LabsPlatformDelegate)? {
        didSet {
            guard oldValue !== delegate, let delegate, let state = loggedInState(for: authState) else { return }
            delegate.labsPlatformAuth(didUpdateLoggedInState: state, platform: self)
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

        pathTask = Task { [weak self, pathMonitor] in
            for await path in pathMonitor.paths() {
                self?.isNetworkAvailable = path.status == .satisfied
            }
        }
    }

    deinit {
        pathTask?.cancel()
    }

    public var isLoggedIn: Bool {
        switch self.authState {
        case .loggedIn(_), .needsRefresh(_), .refreshing(_):
            return true
        default:
            return false
        }
    }

    /// `true` when the session was created with the default (App Store review) credentials.
    public var isDefaultLogin: Bool {
        switch self.authState {
        case .loggedIn(let auth), .needsRefresh(let auth):
            return auth == PlatformAuthCredentials.defaultValue
        default:
            return false
        }
    }

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

    /// Persists credentials and notifies the delegate when `authState` settles. Equality is by case, so a refreshed
    /// credential in the same case is persisted but not re-announced.
    private func authStateDidChange(from oldValue: PlatformAuthState) {
        switch authState {
        case .loggedOut:
            LabsKeychain.clearPlatformCredential()
            LabsKeychain.deletePennkey()
            LabsKeychain.deletePassword()
        case .loggedIn(let auth), .needsRefresh(let auth):
            LabsKeychain.savePlatformCredential(auth)
        default:
            return
        }

        guard oldValue != authState, let state = loggedInState(for: authState) else { return }
        delegate?.labsPlatformAuth(didUpdateLoggedInState: state, platform: self)
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
    let delegate: (any LabsPlatformDelegate)?

    init(analyticsRoot: String, clientId: String, redirectUrl: String, configuration: LabsPlatform.Configuration, delegate: (any LabsPlatformDelegate)?, @ViewBuilder content: @escaping () -> Content) {
        if LabsPlatform.shared == nil {
            _ = LabsPlatform(clientId: clientId, redirectUrl: redirectUrl, configuration: configuration)
        }
        self._platform = ObservedObject(initialValue: LabsPlatform.shared!)
        self.analyticsRoot = analyticsRoot
        self.content = content()
        self.delegate = delegate
    }


    var body: some View {
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
            .onChange(of: scenePhase) {
                Task {
                    await platform.analytics?.focusChanged(scenePhase)
                }
            }
            .onAppear {
                platform.setWebAuthenticationSession(webAuthenticationSession)
                if let delegate {
                    platform.delegate = delegate
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
    ///     - delegate: Receives auth, request, and analytics events (see [`LabsPlatformDelegate`](x-source-tag://LabsPlatformDelegate)).
    ///             Held weakly, so keep it alive (e.g. as a `@StateObject`). Attached on appear, at which point the current
    ///             login state is reported via `labsPlatformAuth(didUpdateLoggedInState:platform:)`.
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
