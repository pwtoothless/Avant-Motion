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
        case settings, bluetooth, servo
    }

    var body: some View {
        TabView(selection: $selectedMenuItem) {
            
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                SettingsView()
                    .environmentObject(bluetoothManager)
                    .background(LiquidGlassBackground())
            }

            Tab("Bluetooth", systemImage: "dot.radiowaves.left.and.right", value: .bluetooth) {
                BTContentView()
                    .environmentObject(bluetoothManager)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(LiquidGlassBackground())
            }
            
            Tab("Servo", systemImage: "arrow.triangle.2.circlepath.camera", value: .servo) {
                ServoControlView()
                    .environmentObject(bluetoothManager)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(LiquidGlassBackground())
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

struct SettingsView: View {
    @EnvironmentObject var bt: BluetoothManager
    
    var body: some View {
        List {
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
            
            Section("Hardware Status") {
                HStack {
                    Label("Bluetooth", systemImage: "bolt.fill")
                    Spacer()
                    StatusBadge(
                        text: bt.connectedPeripheral != nil ? "Active" : "Idle",
                        color: bt.connectedPeripheral != nil ? .blue : .gray
                    )
                }
                
                HStack {
                    Label("Battery", systemImage: "battery.100")
                    Spacer()
                    Text("\(bt.batteryPercentage)%")
                        .foregroundStyle(.secondary)
                }
                
                // Updated to show the current servo degree, assuming it can go up to 270
                HStack {
                    Label("Servo", systemImage: "arrow.triangle.2.circlepath.camera")
                    Spacer()
                    Text("\(bt.currentServoDegree)°") // Displaying the current degree
                        .foregroundStyle(.secondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Settings")
    }
}

struct ServoControlView: View {
    @EnvironmentObject var bt: BluetoothManager
    @State private var servoDegreeInput: String = ""
    @FocusState private var isInputFocused: Bool

    // Define the maximum servo degree based on your servo's capability
    let maxServoDegree = 270
    let minServoDegree = 0

    var body: some View {
        VStack(spacing: 20) {
            Text("Servo Control")
                .font(.title.bold())

            // --- Slider for Servo Angle ---
            VStack {
                Text("Sweep Servo Angle")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                
                Slider(value: Binding<Double>(
                    get: { Double(bt.currentServoDegree) },
                    set: { newValue in
                        let clampedValue = max(Double(minServoDegree), min(Double(maxServoDegree), newValue))
                        bt.currentServoDegree = Int(clampedValue)
                        bt.sendServoCommand(degree: bt.currentServoDegree)
                    }
                ), in: Double(minServoDegree)...Double(maxServoDegree))
                .accentColor(.green) // You can change this color
            }
            .padding(.horizontal)
            // --- End Slider ---


            HStack {
                Text("D:")
                    .font(.title2)
                    .fontWeight(.bold)
                TextField("Enter degree (\(minServoDegree)-\(maxServoDegree))", text: $servoDegreeInput)
                    .keyboardType(.numberPad)
                    .focused($isInputFocused)
                    .padding()
                    .background(Color.black.opacity(0.1))
                    .cornerRadius(10)
                    .frame(maxWidth: .infinity)
                    .onChange(of: servoDegreeInput) { newValue in
                        // Basic validation to keep input within numerical bounds
                        let filteredNewValue = newValue.filter { $0.isNumber }
                        if let degree = Int(filteredNewValue), degree >= minServoDegree, degree <= maxServoDegree {
                            // Valid input, no immediate action needed here as it's bound to state
                        } else if filteredNewValue.isEmpty {
                            // Allow empty string for clearing
                        } else {
                          
                            // If it's not empty and not a valid number/range, you might want to revert or warn.
                            // For now, let it be, and validate on button press.
                        }
                    }
            }
            .padding(.horizontal)

            Button("Set Servo Position") {
                if let degree = Int(servoDegreeInput) {
                    // Ensure the degree is within the valid range before sending
                    let clampedDegree = max(minServoDegree, min(maxServoDegree, degree))
                    bt.sendServoCommand(degree: clampedDegree)
                    servoDegreeInput = "\(clampedDegree)" // Update text field to reflect clamped value
                    bt.currentServoDegree = clampedDegree // Update the displayed degree immediately
                }
                isInputFocused = false // Dismiss keyboard after setting
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(bt.connectedPeripheral == nil || bt.servoCharacteristic == nil)

            // Display current servo degree if available and within the 0-270 range
            if bt.currentServoDegree != 0 || (bt.currentServoDegree >= minServoDegree && bt.currentServoDegree <= maxServoDegree) {
                Text("Current Servo Degree: \(bt.currentServoDegree)°")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .onTapGesture {
            isInputFocused = false // Dismiss keyboard when tapping outside
        }
        .onAppear {
            // Initialize servoDegreeInput with the current servo degree when the view appears
            servoDegreeInput = "\(bt.currentServoDegree)"
        }
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

