//
//  AuthWebViewState.swift
//  LabsPlatformSwift
//
//  Created by Jonathan Melitski on 2/23/26.
//
import Foundation

enum AuthWebViewState: Equatable {
    static func == (lhs: AuthWebViewState, rhs: AuthWebViewState) -> Bool {
        switch (lhs, rhs) {
        case (.disabled, .disabled):
            return true
        case (.enabled(_, _), .enabled(_, _)):
            return true
        default:
            return false
        }
    }
    
    case disabled
    case enabled(url: URL, continuation: CheckedContinuation<PlatformAuthState, any Error>)
}
