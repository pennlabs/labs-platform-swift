//
//  AnalyticsContext.swift
//  LabsAnalytics
//
//  Created by Jonathan Melitski on 11/25/24.
//

import Foundation
import SwiftUI

@MainActor
public struct AnalyticsContext {
    let platform = LabsPlatform.shared
    let key: String
    
    public func logEvent(event: String, value: String = "1") {
        Task {
            guard let analytics = platform?.analytics, event != "" else { return }
            await analytics.record(AnalyticsValue(key: "\(key).event.\(event)", value: value, timestamp: Date.now))
        }
    }
    
    public func beginTimedOperation(operation: String, cancelOnScenePhase: [ScenePhase] = [.background, .inactive]) {
        guard let analytics = platform?.analytics, operation != "" else { return }
        Task {
            await analytics.addTimedOperation(AnalyticsTimedOperation(fullKey: "\(key).operation.\(operation)", cancelOnScenePhase: cancelOnScenePhase))
        }
    }
    
    public func finishTimedOperation(operation: String) {
        Task {
            guard let platform, let oper = await findOperation(key: key, operation: operation) else {
                return
            }
            await platform.analytics?.completeTimedOperation(oper)
        }
    }
    
    private func findOperation(key: String, operation: String) async -> AnalyticsTimedOperation? {
        let path = key.split(separator: ".")
        for i in stride(from: path.count, to: 0, by: -1) {
            var subpath: [Substring] = []
            for j in 0..<i {
                subpath.append(path[j])
            }
            let trialPath = subpath.joined(separator: ".")
            if let oper = await platform?.analytics?.getTimedOperation("\(trialPath).operation.\(operation)") {
                return oper
            }
        }
        return nil
    }
}
