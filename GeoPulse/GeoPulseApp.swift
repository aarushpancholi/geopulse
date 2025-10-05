//
//  GeoPulseApp.swift
//  GeoPulse
//
//  Created by Aarush Pancholi on 10/4/25.
//

import SwiftUI

@main
struct GeoPulseApp: App {
    @StateObject private var app = AppState()
    var body: some Scene {
        WindowGroup {
            WelcomeOnboardingView()
                .environmentObject(app)
                .tint(.yellow)
                .preferredColorScheme(.dark)
        }
    }
}

