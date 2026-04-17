import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject var session: WatchSessionManager

    var body: some View {
        // Using a ZStack ensures the gradient background is always visible, 
        // preventing the "black background" issue that can occur if the view 
        // is not hosted within a NavigationStack or TabView context.
        ZStack {
            LiquidGlassBackground()
                .ignoresSafeArea()

            List {
                Section("Battery") {
                    HStack {
                        Image(systemName: "battery.100")
                        Text("\(session.battery)%")
                    }
                }

                Section("Gyro G1") {
                    WatchGyroBoxRow(values: session.g1)
                }

                Section("Gyro G2") {
                    WatchGyroBoxRow(values: session.g2)
                }

                Section("Gyro G3") {
                    WatchGyroBoxRow(values: session.g3)
                }
                
                Section("Servo") {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                        Text("Angle:")
                        Spacer()
                        Text("\(session.currentServoDegree)°")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            // This modifier is required to remove the default system background of the List,
            // allowing the gradient in the ZStack to show through.
            .scrollContentBackground(.hidden)
        }
        // Applying containerBackground as well for modern watchOS optimization.
        // This allows system elements like the toolbar and title to blend with the gradient.
        .containerBackground(for: .navigation) {
            LiquidGlassBackground()
        }
    }
}

/// A row containing three "glassy" boxes for X, Y, and Z sensor data.
struct WatchGyroBoxRow: View {
    let values: [String]
    
    var body: some View {
        HStack(spacing: 6) {
            WatchValueBox(label: "X", value: values.indices.contains(0) ? values[0] : "0.00")
            WatchValueBox(label: "Y", value: values.indices.contains(1) ? values[1] : "0.00")
            WatchValueBox(label: "Z", value: values.indices.contains(2) ? values[2] : "0.00")
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        .listRowBackground(Color.clear) // Transparent row background to allow material boxes to pop
    }
}

/// A single glassy box using ultraThinMaterial to create the "Liquid Glass" effect.
struct WatchValueBox: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Shared background component that provides the gradient for the "Liquid Glass" look.
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

#Preview {
    let mockSessionManager = WatchSessionManager()
    mockSessionManager.battery = 80
    mockSessionManager.g1 = ["1.2", "3.4", "-5.6"]
    mockSessionManager.g2 = ["-7.8", "9.0", "1.2"]
    mockSessionManager.g3 = ["3.4", "-5.6", "7.8"]
    mockSessionManager.currentServoDegree = 90

    return NavigationStack {
        WatchContentView()
            .environmentObject(mockSessionManager)
    }
}
