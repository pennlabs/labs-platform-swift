//
//  LabsPlatformRequests.swift
//  LabsPlatformSwift
//
//  Created by Jonathan Melitski on 2/2/25.
//

// This file designed to be entirely exposed functions/enums/structs used to make web requests
import Foundation

public extension URLRequest {
    /// Applies the `Authorization` and `X-Authorization` headers with the token type of choice (JWT or legacy access token)
    init(url: URL, mode: PlatformAuthMode) async throws {
        guard let platform = await LabsPlatform.shared else {
            throw PlatformError.platformNotEnabled
        }
        self = try await platform.authorizedURLRequest(url: url, mode: mode)
    }
}

/// Provides a `URLSession` with authenticated header fields depending on the `authenticationMode` (JWT or Legacy).
///
/// > Note: Requests sent through a session created this way do not pass through the
/// > `LabsPlatformDelegate` request hook, since the headers are applied at the session level.
public extension URLSession {
    convenience init(authenticationMode: PlatformAuthMode, config: URLSessionConfiguration = .default) async throws {
        guard let platform = await LabsPlatform.shared else {
            throw PlatformError.platformNotEnabled
        }
        config.httpAdditionalHeaders = try await platform.authorizationHeaders(mode: authenticationMode)
        self.init(configuration: config)
    }
}

extension LabsPlatform {
    /// Applies the `Authorization` and `X-Authorization` headers with the token type of choice (JWT or legacy access token).
    /// App-originated requests (`notifyDelegate == true`) pass through the delegate's `willSendRequest` hook.
    func authorizedURLRequest(_ request: URLRequest, mode: PlatformAuthMode, notifyDelegate: Bool = true) async throws -> URLRequest {
        var newRequest = request
        for (field, value) in try await authorizationHeaders(mode: mode) {
            newRequest.setValue(value, forHTTPHeaderField: field)
        }
        if notifyDelegate, let delegate {
            newRequest = delegate.labsPlatformRequests(willSendRequest: newRequest, platform: self)
        }
        return newRequest
    }

    func authorizedURLRequest(url: URL, mode: PlatformAuthMode, notifyDelegate: Bool = true) async throws -> URLRequest {
        try await authorizedURLRequest(URLRequest(url: url), mode: mode, notifyDelegate: notifyDelegate)
    }

    func authorizationHeaders(mode: PlatformAuthMode) async throws -> [String: String] {
        let auth: PlatformAuthCredentials
        switch await getRefreshedAuthState() {
        case .loggedIn(let credential):
            auth = credential
        case .needsRefresh:
            throw PlatformError.refreshUnavailable
        default:
            throw PlatformError.notLoggedIn
        }

        let token: String
        switch mode {
        case .accessToken:
            token = auth.accessToken
        case .jwt:
            guard let idToken = auth.idToken else { throw PlatformError.jwtNotFound }
            token = idToken
        }
        let value = "\(auth.tokenType) \(token)"
        return ["Authorization": value, "X-Authorization": value]
    }
}

public enum PlatformError: Int, LocalizedError {
    case notLoggedIn = 10
    case jwtNotFound = 11
    /// The session is valid but the token has expired and the device is offline, so it cannot be refreshed yet.
    case refreshUnavailable = 12
    case platformNotEnabled = -1

    public var errorDescription: String? {
        let baseStr = switch self {
        case .notLoggedIn:
            "Your login credentials are invalid (or you are not logged in)."
        case .jwtNotFound:
            "Unable to send this request."
        case .refreshUnavailable:
            "Your session needs to be refreshed, but the network is unavailable."
        case .platformNotEnabled:
            "Connection to the Penn Labs Platform is not correctly configured."
        }

        return "\(baseStr) [error code \(self.rawValue)]"
    }
}

public enum PlatformAuthMode: Int, Sendable {
    case accessToken = 0
    case jwt = 1
}
