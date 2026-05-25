import SwiftUI
import Combine
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
                .environmentObject(appSettings) // Pass it down
        }
    }
}

final class AppSettings: ObservableObject {
    // The `objectWillChange` publisher is automatically provided by the ObservableObject protocol.
    // You can add published settings properties here in the future, for example:
    // @Published var isNotificationsEnabled: Bool = true
}
