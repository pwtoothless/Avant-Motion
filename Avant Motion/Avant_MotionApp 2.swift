// In Avant_MotionApp.swift, within the body's WindowGroup:
WindowGroup {
    ContentView()
        .environmentObject(bluetoothManager)
        .environmentObject(legStore)
        .environmentObject(AppSettings.shared) // Make sure AppSettings.shared is initialized and provided
}
