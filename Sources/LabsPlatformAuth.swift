//
//  LabsPlatformAuth.swift
//  LabsPlatformSwift
//
//  Created by Jonathan Melitski on 1/31/25.
//



struct PlatformAuthCredentials: Codable {
    let accessToken: String
    let expiresIn: Int
    let tokenType: String
    let refreshToken: String
    let idToken: String
}

enum PlatformAuthState {
    case loggedOut
    case newLogin(state: String)
    case refreshing(state: String)
    case needsRefresh(auth: PlatformAuthCredentials)
    case loggedIn(auth: PlatformAuthCredentials)
}
