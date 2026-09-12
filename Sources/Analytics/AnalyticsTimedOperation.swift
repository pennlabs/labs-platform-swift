//
//  AnalyticsTimedOperation.swift
//  LabsPlatformSwift
//
//  Created by Jonathan Melitski on 2/24/25.
//

import Foundation
import SwiftUI

public extension Task where Success == Void, Failure == Never {
    static func timedAnalyticsOperation(name: String, removeOnDuplicateName: Bool = false, addUniqueIdentifier: Bool = true, cancelOnScenePhase: [ScenePhase] = [.background, .inactive], _ operation: @Sendable @escaping () async -> Void) {
        Task {
            let suffix = addUniqueIdentifier ? ".\(UUID().uuidString.prefix(8).lowercased())" : ""
            let analytic = AnalyticsTimedOperation(fullKey: "global.operation.\(name)\(suffix)", cancelOnScenePhase: cancelOnScenePhase)
            await LabsPlatform.shared?.analytics?.addTimedOperation(analytic, removeDuplicates: removeOnDuplicateName)
            await operation()
            await LabsPlatform.shared?.analytics?.completeTimedOperation(analytic)
        }
    }
}

struct AnalyticsTimedOperation: Sendable, Equatable, Identifiable {
    let id = UUID()
    let fullKey: String
    let cancelOnScenePhase: [ScenePhase]
    let start = ContinuousClock.now

    static func == (lhs: AnalyticsTimedOperation, rhs: AnalyticsTimedOperation) -> Bool {
        lhs.id == rhs.id
    }

    func finish() -> AnalyticsValue {
        let milliseconds = Int((ContinuousClock.now - start) / .milliseconds(1))
        return AnalyticsValue(key: fullKey, value: String(milliseconds), timestamp: .now)
    }
}
