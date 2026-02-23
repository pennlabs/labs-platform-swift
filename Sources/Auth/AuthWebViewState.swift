//
//  AuthWebViewState.swift
//  LabsPlatformSwift
//
//  Created by Jonathan Melitski on 2/23/26.
//
import Foundation

enum AuthWebViewState: Equatable {
    static func == (lhs: AuthWebViewState, rhs: AuthWebViewState) -> Bool {
        if case let .disabled = lhs,
           case let .disabled = rhs {
            return true
        }
        if case let .enabled(_, _) = lhs,
           case let .enabled(_, _) = rhs {
            return true
        }
        
        return false
    }
    
    case disabled
    case enabled(url: URL, continuation: CheckedContinuation<PlatformAuthState, any Error>)
}
