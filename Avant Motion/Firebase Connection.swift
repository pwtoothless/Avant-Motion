//
//  Arduino_Cloud_Connection.swift
//  Avant Motion
//
//  Created by Peyton Ward on 4/3/26.
//

import Foundation
import Combine
import FirebaseDatabase

class FirebaseCloudManager: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var lastSyncTimestamp: Date?
    @Published var syncError: String?
    @Published var batteryPercentage: Int = 0 // New property to store battery percentage

    // If your database is NOT in us-central1, use: Database.database(url: "YOUR_URL").reference()
    private let dbRef = Database.database().reference()
    private var connectivityHandle: DatabaseHandle?

    init() {
        observeConnectivity()
    }

    /// Monitors the connection state to Firebase servers
    private func observeConnectivity() {
        connectivityHandle = Database.database().reference(withPath: ".info/connected").observe(.value) { [weak self] snapshot in
            DispatchQueue.main.async {
                self?.isConnected = snapshot.value as? Bool ?? false
            }
        }
    }

    /// Pushes battery status and firmware version to Firebase.
    func pushData(
        battery: Int,
        firmwareVersion: String?
    ) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            var updates: [String: Any] = [:]
            let timestamp = ServerValue.timestamp()

            let batteryData: [String: Any] = [
                "battery_percent": battery,
                "timestamp": timestamp
            ]
            updates["/battery_status"] = batteryData
            print("[Firebase SYNC] Preparing batteryData: \(batteryData) for path /battery_status")

            if let fw = firmwareVersion {
                let firmwareData: [String: Any] = [
                    "version": fw,
                    "timestamp": timestamp
                ]
                updates["/firmware_status"] = firmwareData
                print("[Firebase SYNC] Preparing firmwareData: \(firmwareData) for path /firmware_status")
            }

            // Perform all updates in a single transaction for efficiency and atomicity
            if !updates.isEmpty {
                self.dbRef.updateChildValues(updates) { error, _ in
                    DispatchQueue.main.async {
                        if let error = error {
                            self.syncError = "Firebase sync error: \(error.localizedDescription)"
                            print("Firebase sync error: \(error.localizedDescription)")
                        } else {
                            self.syncError = nil
                            self.lastSyncTimestamp = Date()
                            print("[Firebase SYNC] All data successfully synced to Firebase.")
                        }
                    }
                }
            } else {
                print("[Firebase SYNC] No data to update.")
            }
        }
    }
    
    deinit {
        if let handle = connectivityHandle {
            Database.database().reference(withPath: ".info/connected").removeObserver(withHandle: handle)
        }
    }
}
