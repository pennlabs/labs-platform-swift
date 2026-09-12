//
//  LabsPlatformDelegate.swift
//  LabsPlatformSwift
//
//  Created by Jonathan Melitski on 4/5/26.
//

import Foundation

/// Receives auth, request, and analytics events from `LabsPlatform`. Every method has a default implementation.
/// - Tag: LabsPlatformDelegate
@MainActor
public protocol LabsPlatformDelegate: AnyObject {
    // MARK: Auth
    
    /// Called when the platform settles into a logged-in or logged-out state, and once when the delegate is attached.
    func labsPlatformAuth(didUpdateLoggedInState state: (loggedIn: Bool, isDefaultLogin: Bool), platform: LabsPlatform)
    
    /// Called when an interactive login fails. The platform shows no UI of its own, so present `error` here if appropriate.
    /// Cancelling the login is not a failure.
    func labsPlatformAuth(loginFlowFailedWithError error: PlatformAuthFlowError, platform: LabsPlatform)
    
    /// Called when the login callback carries the default (App Store review) credentials. Return `false` to reject them.
    func labsPlatformAuth(didReceiveDefaultLoginCredentials credentials: (username: String, password: String), platform: LabsPlatform) -> Bool
    
    /// Called immediately before a token refresh request is sent.
    func labsPlatformAuth(willPerformRefreshRequest request: URLRequest, platform: LabsPlatform)
    
    /// Called when a token refresh fails. The result decides what happens to the session; defaults to `RefreshFlowFailedResult.default(for:)`.
    func labsPlatformAuth(refreshFlowFailedWithError error: PlatformAuthFlowError, platform: LabsPlatform) -> RefreshFlowFailedResult
    
    // MARK: Requests
    
    /// Called after authorization headers are attached to a request created via `URLRequest(url:mode:)`. Return the request to use.
    func labsPlatformRequests(willSendRequest request: URLRequest, platform: LabsPlatform) -> URLRequest
    
    // MARK: Analytics
    
    /// Called once per push cycle in which at least one transaction failed. Failed transactions stay queued and are retried.
    func labsPlatformAnalytics(pushFailedWithErrors errors: [PlatformAnalyticsError], platform: LabsPlatform)
}

/// What the platform does after a failed token refresh.
public enum RefreshFlowFailedResult: Sendable {
    /// Keep the credential in `needsRefresh`; the next request after connectivity returns retries.
    case stayLoggedIn
    /// Retry now, up to `LabsPlatform.maxRefreshAttempts` times with a growing delay.
    case tryAgain
    /// Discard the credential and log out.
    case logOut
    
    /// Stay logged in when the device is offline or the response was unreadable; log out otherwise.
    public static func `default`(for error: PlatformAuthFlowError) -> RefreshFlowFailedResult {
        switch error {
        case .platformError(.noConnection), .decodingError:
            return .stayLoggedIn
        case .platformError, .other:
            return .logOut
        }
    }
}

/// A login or refresh failure, classified so delegates can match on the common cases.
public enum PlatformAuthFlowError: Error, Sendable {
    case platformError(PlatformAuthError)
    case decodingError(DecodingError)
    case other(any Error)
    
    init(_ error: any Error) {
        switch error {
        case let error as PlatformAuthFlowError: self = error
        case let error as PlatformAuthError: self = .platformError(error)
        case let error as DecodingError: self = .decodingError(error)
        default: self = .other(error)
        }
    }
}

/// A failure while pushing one analytics transaction.
public enum PlatformAnalyticsError: Error, Sendable {
    /// The request could not be authorized (e.g. not logged in, or offline with an expired token).
    case platformError(PlatformError)
    case encodingFailed
    case badStatusCode(Int)
    case invalidResponse
    case other(any Error)
}

public extension LabsPlatformDelegate {
    func labsPlatformAuth(didUpdateLoggedInState state: (loggedIn: Bool, isDefaultLogin: Bool), platform: LabsPlatform) { }
    func labsPlatformAuth(loginFlowFailedWithError error: PlatformAuthFlowError, platform: LabsPlatform) { }
    func labsPlatformAuth(didReceiveDefaultLoginCredentials credentials: (username: String, password: String), platform: LabsPlatform) -> Bool { true }
    func labsPlatformAuth(willPerformRefreshRequest request: URLRequest, platform: LabsPlatform) { }
    func labsPlatformAuth(refreshFlowFailedWithError error: PlatformAuthFlowError, platform: LabsPlatform) -> RefreshFlowFailedResult { .default(for: error) }
    
    func labsPlatformRequests(willSendRequest request: URLRequest, platform: LabsPlatform) -> URLRequest { request }
    
    func labsPlatformAnalytics(pushFailedWithErrors errors: [PlatformAnalyticsError], platform: LabsPlatform) { }
}
