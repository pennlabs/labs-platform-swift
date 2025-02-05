//
//  AnalyticsContext.swift
//  LabsAnalytics
//
//  Created by Jonathan Melitski on 11/25/24.
//

import Foundation

public struct AnalyticsContext {
    let analytics: LabsPlatform.Analytics?
    let key: String
    
    public func logEvent(event: String, value: Int = 1) {
        guard let analytics else { return }
        analytics.record(AnalyticsValue(key: key, value: value, timestamp: Date.now))
    }
}
