//
//  LabsPlatformRequests.swift
//  LabsPlatformSwift
//
//  Created by Jonathan Melitski on 2/2/25.
//

// This file designed to be entirely exposed functions/enums/structs used to make web requests
import Foundation

public extension LabsPlatform {
    
    /// Applies the `Authorization` and `X-Authorization` headers with the token type of choice (JWT or legacy access token)
    func authorizedURLRequest(_ request: URLRequest, mode: PlatformAuthMode) async throws -> URLRequest {
        self.authState = await self.getRefreshedAuthState()
        guard case .loggedIn(let auth) = self.authState else {
            throw PlatformError.notLoggedIn
        }
        var newRequest = request
        switch mode {
        case .jwt:
            newRequest.allHTTPHeaderFields?["Authorization"] = "\(auth.tokenType) \(auth.idToken)"
            newRequest.allHTTPHeaderFields?["X-Authorization"] = "\(auth.tokenType) \(auth.idToken)"
            break
        case .legacy:
            newRequest.allHTTPHeaderFields?["Authorization"] = "\(auth.tokenType) \(auth.accessToken)"
            newRequest.allHTTPHeaderFields?["X-Authorization"] = "\(auth.tokenType) \(auth.accessToken)"
            break
        }
        
        return newRequest
    }
}

public enum PlatformError: Error {
    case notLoggedIn
}

public enum PlatformAuthMode {
    case legacy
    case jwt
}
