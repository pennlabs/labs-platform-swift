//
//  AnalyticsTimedOperation.swift
//  LabsPlatformSwift
//
//  Created by Jonathan Melitski on 2/24/25.
//

import Foundation
import SwiftUI
import Combine

public extension Task where Success == Void, Failure == Never {
    static func timedAnalyticsOperation(name: String, cancelOnScenePhase: [ScenePhase] = [.background, .inactive], _ operation: @escaping () async -> Void) async {
        let analytic = AnalyticsTimedOperation(fullKey: "global.operation.\(name)", cancelOnScenePhase: cancelOnScenePhase)
        await LabsPlatform.shared?.analytics.addTimedOperation(analytic)
        await operation()
        await LabsPlatform.shared?.analytics.completeTimedOperation(analytic)
    }
}

actor AnalyticsTimedOperation: Equatable, Identifiable {
    static func == (lhs: AnalyticsTimedOperation, rhs: AnalyticsTimedOperation) -> Bool {
        return lhs.id == rhs.id
    }
    let id: UUID = UUID()
    var time: Int = 0
    let fullKey: String
    let cancelOnScenePhase: [ScenePhase]
    let startTime: DispatchTime
    
    init(fullKey: String, cancelOnScenePhase: [ScenePhase] = [.background, .inactive]) {
        self.fullKey = fullKey
        self.cancelOnScenePhase = cancelOnScenePhase
        self.startTime = DispatchTime.now()
    }
    
    
    func cancel() {}
    
    func finish() -> AnalyticsValue {
        cancel()
        let totalTime = startTime.distance(to: DispatchTime.now())
        if case .nanoseconds(let nano) = totalTime {
            return AnalyticsValue(key: fullKey, value: String(nano / 1000000), timestamp: Date.now)
        } else {
            return AnalyticsValue(key: fullKey, value: "undefined", timestamp: Date.now)
        }
    }
}
