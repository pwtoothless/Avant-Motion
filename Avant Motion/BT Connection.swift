//
//  BT Connection.swift
//  Avant Motion
//
//  Created by Peyton Ward on 4/3/26.
//

import Foundation
import CoreBluetooth
import SwiftUI
internal import Combine


final class BluetoothManager: NSObject, ObservableObject {
    @Published var isScanning = false
    private var centralManager: CBCentralManager!

    override init() {
        super.init()
        self.centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        if !isScanning {
            isScanning = true
            centralManager.scanForPeripherals(withServices: nil, options: nil)
        }
    }

    func stopScanning() {
        if isScanning {
            isScanning = false
            centralManager.stopScan()
        }
    }
}

extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // Optionally auto-start when powered on
        if central.state == .poweredOn {
            // startScanning()
        } else {
            stopScanning()
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // Handle discovered peripherals here
        // print("Discovered: \(peripheral.identifier) - \(peripheral.name ?? "Unknown")")
    }
}

struct BTContentView: View {
    @EnvironmentObject var bt: BluetoothManager

    var body: some View {
        VStack(spacing: 16) {
            Text("Bluetooth Scanner")
                .font(.title)
            Button(bt.isScanning ? "Stop Scanning" : "Start Scanning") {
                bt.isScanning ? bt.stopScanning() : bt.startScanning()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

@main
struct BTConnection: App {
    @StateObject private var bluetoothManager = BluetoothManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bluetoothManager)
        }
    }
}
