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
    @available(*, deprecated, message: "Switch to analytics(_:logViewAppearances:)")
    @ViewBuilder public func analytics(_ subkey: String?, logViewAppearances: Bool) -> some View {
        AnalyticsView(subkey: subkey, logViewAppearances: logViewAppearances ? .enabled : .disabled) {
            self
        }
    }
    
    @ViewBuilder public func analytics(_ subkey: String?, logViewAppearances: ViewAppearanceLoggingMode) -> some View {
        AnalyticsView(subkey: subkey, logViewAppearances: logViewAppearances) {
            self
        }
    }
}

private struct AnalyticsView<Content: View>: View {
    @Environment(\.labsAnalyticsPath) var path: String
    let content: Content
    let logViewAppearances: ViewAppearanceLoggingMode
    let subkey: String?
    @State var key: String = ""
    @State var onScreen: Bool = false
    let platform = LabsPlatform.shared
    init(subkey: String?, logViewAppearances: ViewAppearanceLoggingMode, @ViewBuilder _ content: () -> Content) {
        self.content = content()
        self.subkey = subkey
        self.logViewAppearances = logViewAppearances
    }
    
    var body: some View {
        Group {
            if case .enabled = logViewAppearances {
                content
                    .onAppear {
                        onScreen = true
                    }
                    .onDisappear {
                        onScreen = false
                    }
            } else if case .enabledExpensive = logViewAppearances {
                content
                    .background {
                        GeometryReader { proxy in
                            Color.clear
                                .onChange(of: proxy.frame(in: .global)) {
                                    let frame = proxy.frame(in: .global)
                                    let intersects = frame.intersects(.init(x: 0, y: 0, width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height))
                                    if intersects != onScreen {
                                        onScreen = intersects
                                    }
                                }
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
        .onChange(of: onScreen) {
            Task {
                await platform?.analytics?.record(AnalyticsValue(key: "\(key).\(onScreen ? "appear" : "disappear")", value: "1", timestamp: Date.now))
            }
        }
    }
}

public enum ViewAppearanceLoggingMode {
    case disabled, enabled, enabledExpensive
    
    // enabledExpensive for more accurate processing, such as for portal posts where we actually want to be sure that it was on screen, instead of just in the VStack
}
