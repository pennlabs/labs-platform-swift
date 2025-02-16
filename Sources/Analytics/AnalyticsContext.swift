//
//  AnalyticsContext.swift
//  LabsAnalytics
//
//  Created by Jonathan Melitski on 11/25/24.
//

import Foundation

@MainActor
public struct AnalyticsContext {
    let platform = LabsPlatform.shared
    let key: String
    
    public func logEvent(event: String, value: String = "1") {
        Task {
            guard let analytics = platform?.analytics else { return }
            await analytics.record(AnalyticsValue(key: "\(key).event.\(event)", value: value, timestamp: Date.now))
        }
    }
}
