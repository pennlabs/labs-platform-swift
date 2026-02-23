//
//  AnalyticsContextProvider.swift
//  LabsAnalytics
//
//  Created by Jonathan Melitski on 11/25/24.
//

import SwiftUI



/*
  
 var body: some View {
 
    AnalyticsContextProvider { context in
        Text("Hello")
            .onTapGesture {
                context.log("text")
            }
    }
 
 
    DiningDetailView()
        .analytics("commons")
 
 }
 
 */

public struct AnalyticsContextProvider<Content: View>: View {
    @Environment(\.labsAnalyticsPath) var path: String

    public var content: (AnalyticsContext) -> Content

    public init(@ViewBuilder content: @escaping (AnalyticsContext) -> Content) {
        self.content = content
    }

    public var body: some View {
        content(AnalyticsContext(key: path))
    }
}

extension View {
    @ViewBuilder public func analytics(_ subkey: String?, logViewAppearances: Bool) -> some View {
        AnalyticsView(subkey: subkey, logViewAppearances: logViewAppearances) {
            self
        }
    }
}

private struct AnalyticsView<Content: View>: View {
    @Environment(\.labsAnalyticsPath) var path: String
    let content: Content
    let logViewAppearances: Bool
    let subkey: String?
    @State var key: String = ""
    let platform = LabsPlatform.shared
    init(subkey: String?, logViewAppearances: Bool, @ViewBuilder _ content: () -> Content) {
        self.content = content()
        self.subkey = subkey
        self.logViewAppearances = logViewAppearances
    }
    
    var body: some View {
        Group {
            if logViewAppearances {
                content
                    .onAppear {
                        guard let platform else { return }
                        Task {
                            await platform.analytics?.record(AnalyticsValue(key: "\(key).appear", value: "1", timestamp: Date.now))
                        }
                    }
                    .onDisappear {
                        guard let platform else { return }
                        Task {
                            await platform.analytics?.record(AnalyticsValue(key: "\(key).disappear", value: "1", timestamp: Date.now))
                        }
                    }
            } else {
                content
            }
        }
        .environment(\.labsAnalyticsPath, key)
        .onAppear {
            self.key = subkey == nil ? path : "\(path).\(subkey!)"
        }
    }
}
