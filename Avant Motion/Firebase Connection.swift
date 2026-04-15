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

    /// Pushes X, Y, and Z values to Firebase for gyros G1, G2, G3 and battery status
    func pushData(
        gyro1: (x: String, y: String, z: String)?,
        gyro2: (x: String, y: String, z: String)?,
        gyro3: (x: String, y: String, z: String)?,
        battery: Int
    ) {
        // Prepare the main "gyro_status" node
        var gyroStatusData: [String: Any] = [:]

        // Add G1 data if available
        if let g1 = gyro1 {
            gyroStatusData["G1"] = [
                "x": g1.x,
                "y": g1.y,
                "z": g1.z,
                "timestamp": ServerValue.timestamp()
            ]
        }

        // Add G2 data if available
        if let g2 = gyro2 {
            gyroStatusData["G2"] = [
                "x": g2.x,
                "y": g2.y,
                "z": g2.z,
                "timestamp": ServerValue.timestamp()
            ]
        }

        // Add G3 data if available
        if let g3 = gyro3 {
            gyroStatusData["G3"] = [
                "x": g3.x,
                "y": g3.y,
                "z": g3.z,
                "timestamp": ServerValue.timestamp()
            ]
        }

        // Prepare battery data
        let batteryData: [String: Any] = [
            "battery_percent": battery,
            "timestamp": ServerValue.timestamp()
        ]
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            print("[Firebase SYNC] Pushing gyroStatusData: \(gyroStatusData) at \(Date())")
            // Use update to merge data, preventing overwriting if one push fails
            let gyroRef = self?.dbRef.child("gyro_status")
            gyroRef?.updateChildValues(gyroStatusData) { error, _ in
                if let error = error {
                    DispatchQueue.main.async {
                        self?.syncError = "Gyro sync error: \(error.localizedDescription)"
                    }
                } else {
                    print("[Firebase SYNC] Pushing batteryData: \(batteryData) at \(Date())")
                    let batteryRef = self?.dbRef.child("battery_status")
                    batteryRef?.setValue(batteryData) { batteryError, _ in
                        DispatchQueue.main.async {
                            if let batteryError = batteryError {
                                self?.syncError = "Battery sync error: \(batteryError.localizedDescription)"
                            } else {
                                // Only clear error and update timestamp if both (or relevant parts) succeed
                                self?.syncError = nil
                                self?.lastSyncTimestamp = Date()
                            }
                        }
                    }
                }
            }
        }
    }
    
    deinit {
        if let handle = connectivityHandle {
            Database.database().reference(withPath: ".info/connected").removeObserver(withHandle: handle)
        }
    }
}
