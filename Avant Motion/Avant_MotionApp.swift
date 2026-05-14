#if os(iOS)
import SwiftUI
import FirebaseCore

@main
struct Avant_MotionApp: App {
    @StateObject private var bluetoothManager = BluetoothManager()
    @StateObject private var legStore = LegStore()
    @StateObject private var appSettings = AppSettings()
    
    init() {
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bluetoothManager)
                .environmentObject(legStore)
                .environmentObject(appSettings)
        }
    }
}

#endif

