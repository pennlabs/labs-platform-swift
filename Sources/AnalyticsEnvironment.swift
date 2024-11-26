//
//  AnalyticsEnvironment.swift
//  LabsAnalytics
//
//  Created by Jonathan Melitski on 11/25/24.
//

import SwiftUI

public struct LabsAnalyticsPathKey: EnvironmentKey {
    public static let defaultValue: String = ""
}

public extension EnvironmentValues {
    var labsAnalyticsPath: String {
        get { self[LabsAnalyticsPathKey.self] }
        set { self[LabsAnalyticsPathKey.self] = newValue }
    }
}
