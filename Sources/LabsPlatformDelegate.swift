//
//  LabsPlatformDelegate.swift
//  LabsPlatformSwift
//
//  Created by Jonathan Melitski on 4/5/26.
//

import Foundation

/// Receives events from the `LabsPlatform` singleton.
///
/// Every method has a default implementation, so adopters only implement the events they care about.
/// All methods are invoked on the main actor. Assign a delegate via
/// [`View.enableLabsPlatform(...)`](x-source-tag://enableLabsPlatform) or by setting `LabsPlatform.shared?.delegate`.
///
/// - Tag: LabsPlatformDelegate
@MainActor
public protocol LabsPlatformDelegate: AnyObject {
    // MARK: Auth-related Delegate Events

    /// Called whenever the platform settles into a logged-in or logged-out state, and once when the delegate is first attached.
    ///
    /// - Parameters:
    ///     - state: `loggedIn` is `true` for any valid session. `isDefaultLogin` is `true` when the session was created with the
    ///              App Store review credentials (see `LabsPlatform.Configuration.defaultAccount`). In that case no real Platform
    ///              credential exists, so authenticated requests will fail; apps should present mock data instead.
    func labsPlatformAuth(didUpdateLoggedInState state: (loggedIn: Bool, isDefaultLogin: Bool), platform: LabsPlatform)

    /// Called when an interactive login attempt started by `loginWithPlatform()` fails. A user cancelling the login sheet is not a failure.
    /// The platform always transitions to `loggedOut` after this call.
    func labsPlatformAuth(loginFlowFailedWithError error: any Error, platform: LabsPlatform)

    /// Called when the login web view intercepts the default (App Store review) credentials.
    ///
    /// - Returns: `true` to accept the default login and enter a logged-in state with `isDefaultLogin == true`;
    ///            `false` to reject it, which cancels the login and leaves the platform logged out. Defaults to `true`.
    func labsPlatformAuth(didReceiveDefaultLoginCredentials credentials: (username: String, password: String), platform: LabsPlatform) -> Bool

    /// Called immediately before a token refresh request is sent to the Platform token endpoint. Useful for logging.
    func labsPlatformAuth(willPerformRefreshRequest request: URLRequest, platform: LabsPlatform)

    /// Called when a token refresh fails. The return value decides what happens to the session.
    ///
    /// The default implementation returns `RefreshFlowFailedResult.default(for:)`: stay logged in on network or decoding
    /// errors (the refresh token is presumed still valid), log out on anything else (e.g. the server rejected the token).
    /// `tryAgain` is retried up to `LabsPlatform.maxRefreshAttempts` times before the platform gives up and logs out.
    func labsPlatformAuth(refreshFlowFailedWithError error: any Error, platform: LabsPlatform) -> RefreshFlowFailedResult

    // MARK: URLRequest-related Delegate Events

    /// Called after the platform has attached authorization headers to a request created via `URLRequest(url:mode:)`
    /// or `URLSession.data(for:mode:)`, and before it is sent. Return the request to send (modified or not).
    ///
    /// Library-internal traffic (login, token refresh, analytics) does not pass through this method.
    func labsPlatformRequests(willSendRequest request: URLRequest, platform: LabsPlatform) -> URLRequest

    /// Called when a request performed via `URLSession.data(for:mode:)` or `URLSession.data(from:mode:)` completes,
    /// whether it succeeded or threw. Requests created with `URLRequest(url:mode:)` and sent by the app directly
    /// do not report here, since the platform never sees their response.
    func labsPlatformRequests(didCompleteRequest request: URLRequest, result: Result<(Data, URLResponse), any Error>, platform: LabsPlatform)

    // MARK: Analytics-related Delegate Events

    /// Called once per analytics push cycle in which at least one transaction failed to submit. Failed transactions
    /// remain queued and are retried on the next cycle, so this is informational (e.g. for logging).
    func labsPlatformAnalytics(pushFailedWithErrors errors: [any Error], platform: LabsPlatform)
}

/// What the platform should do after a failed token refresh.
public enum RefreshFlowFailedResult: Sendable {
    /// Keep the current credential and leave the session in `needsRefresh`. The next authenticated request will try to refresh again.
    case stayLoggedIn
    /// Immediately retry the refresh request.
    case tryAgain
    /// Discard the credential and transition to `loggedOut`.
    case logOut

    /// The platform's built-in policy, used when no delegate is set or the delegate does not implement
    /// `labsPlatformAuth(refreshFlowFailedWithError:platform:)`.
    public static func `default`(for error: any Error) -> RefreshFlowFailedResult {
        switch error {
        case PlatformAuthError.noConnection:
            // The user has no connection, so the refresh token is presumed still valid.
            return .stayLoggedIn
        case is DecodingError:
            // Platform responded but with something we could not read; do not throw away a possibly-valid session.
            return .stayLoggedIn
        default:
            return .logOut
        }
    }
}

/// Errors raised while pushing analytics transactions.
public enum PlatformAnalyticsError: Error, Sendable {
    /// The transaction could not be encoded as JSON.
    case encodingFailed
    /// The analytics endpoint returned a non-200 status code.
    case badStatusCode(Int)
    /// The response could not be interpreted as an HTTP response.
    case invalidResponse
}

public extension LabsPlatformDelegate {
    func labsPlatformAuth(didUpdateLoggedInState state: (loggedIn: Bool, isDefaultLogin: Bool), platform: LabsPlatform) { }
    func labsPlatformAuth(loginFlowFailedWithError error: any Error, platform: LabsPlatform) { }
    func labsPlatformAuth(didReceiveDefaultLoginCredentials credentials: (username: String, password: String), platform: LabsPlatform) -> Bool { true }
    func labsPlatformAuth(willPerformRefreshRequest request: URLRequest, platform: LabsPlatform) { }
    func labsPlatformAuth(refreshFlowFailedWithError error: any Error, platform: LabsPlatform) -> RefreshFlowFailedResult { .default(for: error) }

    func labsPlatformRequests(willSendRequest request: URLRequest, platform: LabsPlatform) -> URLRequest { request }
    func labsPlatformRequests(didCompleteRequest request: URLRequest, result: Result<(Data, URLResponse), any Error>, platform: LabsPlatform) { }

    func labsPlatformAnalytics(pushFailedWithErrors errors: [any Error], platform: LabsPlatform) { }
}
