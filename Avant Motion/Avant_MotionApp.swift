//
//  Avant_MotionApp.swift
//  Avant Motion
//
//  Created by Peyton Ward on 4/3/26.
//

import SwiftUI
import FirebaseCore

@main
struct Avant_MotionApp: App {
    @StateObject private var bluetoothManager = BluetoothManager()
    
    init() {
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bluetoothManager)
        }
    }
}
