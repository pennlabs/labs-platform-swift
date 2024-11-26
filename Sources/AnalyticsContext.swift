//
//  AnalyticsContext.swift
//  LabsAnalytics
//
//  Created by Jonathan Melitski on 11/25/24.
//

public struct AnalyticsContext {
    let analytics: LabsAnalytics?
    let key: String
    
    func logEvent(event: String, value: Int = 1) {
        guard let analytics else { return }
        analytics.scheduleAnalyticsPost(AnalyticsValue(key: key, value: value, timestamp: Date.now))
    }
    
}
