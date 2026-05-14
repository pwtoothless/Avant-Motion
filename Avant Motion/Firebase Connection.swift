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

    /// Pushes X, Y, and Z values to Firebase for gyros G1, G2, G3, battery status, and firmware version.
    func pushData(
        gyro1: (x: String, y: String, z: String)?,
        gyro2: (x: String, y: String, z: String)?,
        gyro3: (x: String, y: String, z: String)?,
        battery: Int,
        firmwareVersion: String? // Added firmwareVersion parameter
    ) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            var updates: [String: Any] = [:]
            let timestamp = ServerValue.timestamp()

            // Prepare the main "gyro_status" node
            var gyroStatusData: [String: Any] = [:]

            // Add G1 data if available
            if let g1 = gyro1 {
                gyroStatusData["G1"] = [
                    "x": g1.x,
                    "y": g1.y,
                    "z": g1.z,
                    "timestamp": timestamp
                ]
            }

            // Add G2 data if available
            if let g2 = gyro2 {
                gyroStatusData["G2"] = [
                    "x": g2.x,
                    "y": g2.y,
                    "z": g2.z,
                    "timestamp": timestamp
                ]
            }

            // Add G3 data if available
            if let g3 = gyro3 {
                gyroStatusData["G3"] = [
                    "x": g3.x,
                    "y": g3.y,
                    "z": g3.z,
                    "timestamp": timestamp
                ]
            }
            
            // Only update gyro status if there's actual gyro data
            if !gyroStatusData.isEmpty {
                updates["/gyro_status"] = gyroStatusData
                print("[Firebase SYNC] Preparing gyroStatusData: \(gyroStatusData) for path /gyro_status")
            }

            // Prepare battery data
            let batteryData: [String: Any] = [
                "battery_percent": battery,
                "timestamp": timestamp
            ]
            updates["/battery_status"] = batteryData
            print("[Firebase SYNC] Preparing batteryData: \(batteryData) for path /battery_status")

            // Prepare firmware version data
            if let fw = firmwareVersion {
                let firmwareData: [String: Any] = [
                    "version": fw,
                    "timestamp": timestamp
                ]
                updates["/firmware_status"] = firmwareData // Store in a dedicated path
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
