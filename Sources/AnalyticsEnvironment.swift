//
//  AnalyticsEnvironment.swift
//  LabsAnalytics
//
//  Created by Jonathan Melitski on 11/25/24.
//

import SwiftUI

public struct LabsAnalyticsKey: EnvironmentKey {
    public static let defaultValue: LabsAnalytics? = nil
}

public struct LabsAnalyticsPathKey: EnvironmentKey {
    public static let defaultValue: String = ""
}

public extension EnvironmentValues {
    var labsAnalytics: LabsAnalytics? {
        get { self[LabsAnalyticsKey.self] }
        set { self[LabsAnalyticsKey.self] = newValue }
    }
    
    var labsAnalyticsPath: String {
        get { self[LabsAnalyticsPathKey.self] }
        set { self[LabsAnalyticsPathKey.self] = newValue }
    }
}
