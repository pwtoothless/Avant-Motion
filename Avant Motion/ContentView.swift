//
//  ContentView.swift
//  Avant Motion
//
//  Created by Peyton Ward on 4/3/26.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedMenuItem: MenuItem = .settings
    @EnvironmentObject var bluetoothManager: BluetoothManager

    enum MenuItem: Hashable {
        case settings, bluetooth, servo, prosthetic
    }

    var body: some View {
        TabView(selection: $selectedMenuItem) {
            
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                SettingsView()
                    .environmentObject(bluetoothManager)
                    .background(LiquidGlassBackground())
            }
            
            Tab("Prosthetic", systemImage: "figure.walk", value: .prosthetic) {
                ProstheticLegView()
                    .environmentObject(bluetoothManager)
                    .background(LiquidGlassBackground())
            }

            Tab(value: .bluetooth) {
                BTContentView()
                    .environmentObject(bluetoothManager)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(LiquidGlassBackground())
            } label: {
                Label {
                    Text("Stats")
                } icon: {
                    Image(systemName: "chart.bar.xaxis.ascending")
                        .symbolEffect(.drawOn.individually, options: .nonRepeating)
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

struct SettingsView: View {
    @EnvironmentObject var bt: BluetoothManager
    //@EnvironmentObject var appSettings: AppSettings
    @ObservedObject private var health = HealthKitManager.shared
    
    var body: some View {
        List {
            Section {
                LegSettingsView()
            }
            
            Section("Cloud Connection") {
                HStack {
                    Label("Firebase Status", systemImage: "cloud.fill")
                    Spacer()
                    StatusBadge(
                        text: bt.cloudManager.isConnected ? "Connected" : "Disconnected",
                        color: bt.cloudManager.isConnected ? .green : .red
                    )
                }
                
                if let lastSync = bt.cloudManager.lastSyncTimestamp {
                    HStack {
                        Text("Last Sync")
                        Spacer()
                        Text(lastSync, style: .time)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if let error = bt.cloudManager.syncError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            
            Section("Health") {
                // Tapping the row will request authorization if needed
                Button(action: {
                    if !health.isAuthorized {
                        health.requestAuthorization()
                    }
                }) {
                    HStack {
                        Label("Apple Health", systemImage: "heart.fill")
                        Spacer()
                        StatusBadge(
                            text: health.isAuthorized ? "Authorized" : "Not Authorized",
                            color: health.isAuthorized ? .green : .orange
                        )
                    }
                }
                .buttonStyle(.plain)

                HStack {
                    Label("Prosthetic Steps", systemImage: "figure.walk")
                    Spacer()
                    Text("\(health.prostheticStepCount)")
                        .foregroundStyle(.secondary)
                }

                if let last = health.lastWriteDate {
                    HStack {
                        Text("Last Health Sync")
                        Spacer()
                        Text(last, style: .time)
                            .foregroundStyle(.secondary)
                    }
                }

                if health.lastWrittenDelta > 0 {
                    HStack {
                        Text("Last Write Delta")
                        Spacer()
                        Text("+\(health.lastWrittenDelta)")
                            .foregroundStyle(.secondary)
                    }
                }

                if let err = health.lastError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            
            Section("Hardware Status") {
                HStack {
                    Label("Battery", systemImage: "battery.100")
                    Spacer()
                    Text("\(bt.batteryPercentage)%")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Settings")
    }
}

struct StatusBadge: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// Background
struct LiquidGlassBackground: View {
    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(hex: "#ffac0a"),
                Color(hex: "#800000")
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .opacity(0.8)
        .ignoresSafeArea()
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue:  Double(b) / 255, opacity: Double(a) / 255)
    }
}

