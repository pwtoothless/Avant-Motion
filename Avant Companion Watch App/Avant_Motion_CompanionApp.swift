//
//  Avant_Motion_CompanionApp.swift
//  Avant Motion Companion Watch App
//
//  Created by Peyton Ward on 4/17/26.
//

import SwiftUI

@main
struct Avant_Motion_Companion_Watch_AppApp: App {
    @StateObject private var sessionManager = WatchSessionManager()

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(sessionManager)
        }
    }
}
