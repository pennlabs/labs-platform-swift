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
public extension URLSession {
    convenience init(authenticationMode: PlatformAuthMode, config: URLSessionConfiguration = .default) async throws {
        guard let platform = await LabsPlatform.shared else {
            throw PlatformError.platformNotEnabled
        }
        
        let authState = await platform.getRefreshedAuthState()
        guard case .loggedIn(let auth) = authState else {
            throw PlatformError.notLoggedIn
        }
        if case .jwt = authenticationMode, auth.idToken == nil {
            throw PlatformError.jwtNotFound
        }
        var configuration = config
        switch authenticationMode {
        case .jwt:
            config.httpAdditionalHeaders = [
                "Authorization": "\(auth.tokenType) \(auth.idToken!)",
                "X-Authorization": "\(auth.tokenType) \(auth.idToken!)"
            ]
        case .accessToken:
            config.httpAdditionalHeaders = [
                "Authorization": "\(auth.tokenType) \(auth.accessToken)",
                "X-Authorization": "\(auth.tokenType) \(auth.accessToken)"
            ]
        }
        self.init(configuration: configuration)
    }
}

extension LabsPlatform {
    
    /// Applies the `Authorization` and `X-Authorization` headers with the token type of choice (JWT or legacy access token)
    func authorizedURLRequest(_ request: URLRequest, mode: PlatformAuthMode) async throws -> URLRequest {
        self.authState = await self.getRefreshedAuthState()
        guard case .loggedIn(let auth) = self.authState else {
            throw PlatformError.notLoggedIn
        }
        if case .jwt = mode, auth.idToken == nil {
            throw PlatformError.jwtNotFound
        }
        var newRequest = request
        switch mode {
        case .jwt:
            newRequest.setValue("\(auth.tokenType) \(auth.idToken!)", forHTTPHeaderField: "Authorization")
            newRequest.setValue("\(auth.tokenType) \(auth.idToken!)", forHTTPHeaderField: "X-Authorization")
            break
        case .accessToken:
            newRequest.setValue("\(auth.tokenType) \(auth.accessToken)", forHTTPHeaderField: "Authorization")
            newRequest.setValue("\(auth.tokenType) \(auth.accessToken)", forHTTPHeaderField: "X-Authorization")
            break
        }
        
        return newRequest
    }
    
    func authorizedURLRequest(url: URL, mode: PlatformAuthMode) async throws -> URLRequest {
        return try await authorizedURLRequest(URLRequest(url: url), mode: mode)
    }
}

public enum PlatformError: Error {
    case notLoggedIn
    case jwtNotFound
    case platformNotEnabled
}

public enum PlatformAuthMode: Int, Sendable {
    case accessToken = 0
    case jwt = 1
}
