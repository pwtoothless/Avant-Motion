import SwiftUI

struct ProstheticLegView: View {
    @EnvironmentObject var bt: BluetoothManager
    @EnvironmentObject var legs: LegStore
    @EnvironmentObject var appSettings: AppSettings
    
    @State private var showUpdateSheet = false
    
    var selectedLeg: ProstheticLeg? {
        legs.leg(with: legs.selectedLegId)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Top dropdown to select leg
                HStack {
                    Text("Select Leg:")
                    Spacer()
                    Picker("Leg", selection: Binding(get: { legs.selectedLegId ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000") }, set: { newId in
                        if let valid = newId, valid.uuidString != "00000000-0000-0000-0000-000000000000" {
                            legs.selectedLegId = valid
                        } else {
                            legs.selectedLegId = nil
                        }
                    })) {
                        Text("None").tag(UUID?(nilLiteral: ()))
                        ForEach(legs.legs) { leg in
                            Text("\(leg.name) (\(leg.side.rawValue))").tag(UUID?(leg.id))
                        }
                    }
                    .pickerStyle(.menu)
                }
                .padding(.horizontal)
                .onChange(of: legs.selectedLegId) { _ in
                    // Start connection process when a leg is chosen
                    bt.connect(to: selectedLeg)
                }
                
                // Main graphic with battery indicator and dotted connector
                GeometryReader { geo in
                    ZStack {
                        // Centered stylized prosthetic leg graphic
                        LegGraphic()
                            .frame(width: min(geo.size.width, geo.size.height) * 0.35,
                                   height: min(geo.size.width, geo.size.height) * 0.6)
                            .position(x: geo.size.width * 0.45, y: geo.size.height * 0.5)
                        
                        // Battery indicator on the right
                        let batteryX = geo.size.width * 0.8
                        let batteryY = geo.size.height * 0.4
                        BatteryIndicatorView(level: bt.batteryPercentage)
                            .position(x: batteryX, y: batteryY)
                        
                        // Dotted connector line with dots at ends
                        let legPoint = CGPoint(x: geo.size.width * 0.55, y: geo.size.height * 0.5)
                        DottedConnector(start: legPoint, end: CGPoint(x: batteryX, y: batteryY))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: 350)
                .padding()
                
                // Info row: Battery, Firmware, Update button
                HStack(spacing: 12) {
                    Label("Battery: \(bt.batteryPercentage)%", systemImage: "battery.100")
                        .foregroundStyle(.primary)
                    Divider()
                    Label("Firmware: \(bt.firmwareVersion ?? "Unknown")", systemImage: "gear")
                        .foregroundStyle(.primary)
                    Spacer()
                    Button("Update") { showUpdateSheet = true }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("Prosthetic")
            .sheet(isPresented: $showUpdateSheet) {
                FirmwareUpdateView(currentVersion: bt.firmwareVersion)
                    .environmentObject(appSettings)
            }
        }
    }
}

private struct LegGraphic: View {
    var body: some View {
        ZStack {
            // Shin
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(colors: [.gray.opacity(0.6), .gray.opacity(0.9)], startPoint: .top, endPoint: .bottom))
            // Knee joint
            Circle()
                .fill(.black.opacity(0.8))
                .frame(width: 24, height: 24)
                .offset(y: -40)
            // Foot
            Capsule()
                .fill(.gray.opacity(0.8))
                .frame(width: 80, height: 22)
                .offset(y: 110)
        }
    }
}

private struct BatteryIndicatorView: View {
    let level: Int
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: batterySymbol(for: level))
                .font(.title2)
                .foregroundStyle(color(for: level))
            Text("\(level)%")
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func color(for level: Int) -> Color {
        switch level {
        case 0...20: return .red
        case 21...50: return .orange
        default: return .green
        }
    }
    
    private func batterySymbol(for level: Int) -> String {
        switch level {
        case 0...10: return "battery.0"
        case 11...25: return "battery.25"
        case 26...50: return "battery.50"
        case 51...75: return "battery.75"
        default: return "battery.100"
        }
    }
}

private struct DottedConnector: View {
    let start: CGPoint
    let end: CGPoint
    var body: some View {
        Path { path in
            path.move(to: start)
            path.addLine(to: end)
        }
        .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 6]))
        .foregroundStyle(.primary)
        .overlay(
            ZStack {
                Circle().fill(.primary).frame(width: 6, height: 6).position(start)
                Circle().fill(.primary).frame(width: 6, height: 6).position(end)
            }
        )
        .opacity(0.8)
    }
}
