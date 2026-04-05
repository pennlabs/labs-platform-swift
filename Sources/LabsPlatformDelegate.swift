//
//  LabsPlatformDelegate.swift
//  LabsPlatformSwift
//
//  Created by Jonathan Melitski on 4/5/26.
//

import Foundation

public protocol LabsPlatformDelegate: AnyObject {
    // MARK: Auth-related Delegate Events
    func labsPlatformAuth(didUpdateLoggedInState state: (Bool, Bool), platform: LabsPlatform) -> Void
    func labsPlatformAuth(loginFlowFailedWithError error: any Error, platform: LabsPlatform) -> Void
    func labsPlatformAuth(didReceiveDefaultLoginCredentials credentials: (String, String), platform: LabsPlatform) -> Bool
    func labsPlatformAuth(willPerformRefreshRequest request: URLRequest, platform: LabsPlatform) -> Void
    func labsPlatformAuth(refreshFlowFailedWithError error: any Error, platform: LabsPlatform) -> RefreshFlowFailedResult
    
    // MARK: URLRequest-related Delegate Events
    func labsPlatformRequests()
}

public enum RefreshFlowFailedResult {
    case stayLoggedIn, tryAgain, logOut
}

public extension LabsPlatformDelegate {
    func labsPlatformAuth(didUpdateLoggedInState state: (Bool, Bool), platform: LabsPlatform) -> Void { }
}
