#if os(iOS)
import Foundation
import Combine
import WatchConnectivity

/// Manages connectivity from the iPhone to the Apple Watch and mirrors Bluetooth data.
final class PhoneConnectivityManager: NSObject, ObservableObject {
    private var cancellables = Set<AnyCancellable>()
    private var session: WCSession?

    override init() {
        super.init()
        configureSession()
    }

    private func configureSession() {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        s.delegate = self
        s.activate()
        session = s
    }

    /// Call once with a reference to the BluetoothManager to forward its updates to the watch.
    func bind(to bluetooth: BluetoothManager) {
        // Combine gyro and battery updates and push to watch with a small debounce to avoid spamming.
        Publishers.CombineLatest3(bluetooth.$gyro1Values, bluetooth.$gyro2Values, bluetooth.$gyro3Values)
            .combineLatest(bluetooth.$batteryPercentage)
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] triple, battery in
                let (g1, g2, g3) = triple
                self?.sendState(gyro1: g1, gyro2: g2, gyro3: g3, battery: battery)
            }
            .store(in: &cancellables)
    }

    private func sendState(gyro1: [String], gyro2: [String], gyro3: [String], battery: Int) {
        guard let session = session, session.isPaired, session.isWatchAppInstalled else { return }
        let context: [String: Any] = [
            "battery": battery,
            "g1": gyro1,
            "g2": gyro2,
            "g3": gyro3
        ]
        do {
            try session.updateApplicationContext(context)
        } catch {
            print("[PhoneConnectivity] Failed to update application context: \(error)")
        }
    }
}

extension PhoneConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("[PhoneConnectivity] Activation error: \(error)")
        } else {
            print("[PhoneConnectivity] Activation state: \(activationState.rawValue)")
        }
    }

    // iOS only
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
#endif
