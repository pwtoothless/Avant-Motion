#if os(iOS)
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

#endif
