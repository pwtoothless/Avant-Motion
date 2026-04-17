import Foundation
import WatchConnectivity
import Combine

/// Receives mirrored state from the iPhone and publishes it for the watch UI.
final class WatchSessionManager: NSObject, ObservableObject {
    @Published var battery: Int = 0
    @Published var g1: [String] = ["0.00", "0.00", "0.00"]
    @Published var g2: [String] = ["0.00", "0.00", "0.00"]
    @Published var g3: [String] = ["0.00", "0.00", "0.00"]
    @Published var currentServoDegree: Int = 0 // Add this property to store the servo degree

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

    private func apply(context: [String: Any]) {
        if let b = context["battery"] as? Int { self.battery = b }
        if let v = context["g1"] as? [String], v.count == 3 { self.g1 = v }
        if let v = context["g2"] as? [String], v.count == 3 { self.g2 = v }
        if let v = context["g3"] as? [String], v.count == 3 { self.g3 = v }
        // Add logic to handle the servo degree
        if let servoDegree = context["servo"] as? Int {
            self.currentServoDegree = servoDegree
        }
    }
}

extension WatchSessionManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("[WatchSession] Activation error: \(error)")
        }
        if activationState == .activated, session.isReachable {
            // Optionally request current context from the phone if needed in future.
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.apply(context: applicationContext)
        }
    }
}

