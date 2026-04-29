//
//  BT Connection.swift
//  Avant Motion
//
//  Created by Peyton Ward on 4/3/26.
//

import Foundation
import CoreBluetooth
import SwiftUI
import Combine

final class BluetoothManager: NSObject, ObservableObject {
    @Published var isScanning = false
    @Published var connectedPeripheral: CBPeripheral?
    
    // Gyro data for G1, G2, G3
    @Published var gyro1Values: [String] = ["0.00", "0.00", "0.00"]
    @Published var gyro2Values: [String] = ["0.00", "0.00", "0.00"]
    @Published var gyro3Values: [String] = ["0.00", "0.00", "0.00"]
    
    @Published var batteryPercentage: Int = 0
    @Published var battPercent: [String] = ["0.00"] {
        didSet {
            syncToCloud()
        }
    }
    
    @Published var currentServoDegree: Int = 0
    
    private var centralManager: CBCentralManager!
    private let targetServiceUUID = CBUUID(string: "19B10000-E8F2-537E-4F6C-D104768A1214")
    
    let servoCharacteristicUUID = CBUUID(string: "19B10001-E8F2-537E-4F6C-D104768A1214")
    
    public var servoCharacteristic: CBCharacteristic?

    let cloudManager = FirebaseCloudManager()

    override init() {
        super.init()
        let btQueue = DispatchQueue(label: "BluetoothQueue", qos: .userInitiated)
        self.centralManager = CBCentralManager(delegate: self, queue: btQueue)
    }
    
    /// Synchronizes current sensor data to the cloud.
    private func syncToCloud() {
        // Prepare gyro data tuples, only including valid data
        let gyro1Data = gyro1Values.count == 3 ? (x: gyro1Values[0], y: gyro1Values[1], z: gyro1Values[2]) : nil
        let gyro2Data = gyro2Values.count == 3 ? (x: gyro2Values[0], y: gyro2Values[1], z: gyro2Values[2]) : nil
        let gyro3Data = gyro3Values.count == 3 ? (x: gyro3Values[0], y: gyro3Values[1], z: gyro3Values[2]) : nil
        
        // Check if there's any gyro data to send
        if gyro1Data != nil || gyro2Data != nil || gyro3Data != nil {
            cloudManager.pushData(
                gyro1: gyro1Data,
                gyro2: gyro2Data,
                gyro3: gyro3Data,
                battery: batteryPercentage
            )
        } else {
             print("[BT Sync] No gyro data available to sync.")
        }
    }

    func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        if !isScanning {
            DispatchQueue.main.async {
                self.isScanning = true
            }
            centralManager.scanForPeripherals(withServices: [targetServiceUUID], options: nil)
        }
    }

    func stopScanning() {
        DispatchQueue.main.async {
            self.isScanning = false
        }
        centralManager.stopScan()
    }
    
    func disconnect() {
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }
    
    func sendServoCommand(degree: Int) {
        guard let peripheral = connectedPeripheral else {
            print("Not connected to a peripheral.")
            return
        }
        guard let servoCharacteristic = servoCharacteristic else {
            print("Servo characteristic not discovered yet or is nil.")
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let clampedDegree = max(0, min(270, degree))
            let commandString = "D:\(clampedDegree)"
            guard let data = commandString.data(using: .utf8) else {
                print("Failed to encode servo command string.")
                return
            }
            
            if servoCharacteristic.properties.contains(.writeWithoutResponse) {
                peripheral.writeValue(data, for: servoCharacteristic, type: .withoutResponse)
                print("Sent servo command (without response): \(commandString)")
            } else if servoCharacteristic.properties.contains(.write) {
                peripheral.writeValue(data, for: servoCharacteristic, type: .withResponse)
                print("Sent servo command (with response): \(commandString)")
            } else {
                print("Servo characteristic does not support writing.")
            }
            
            // Update currentServoDegree immediately after sending command
            DispatchQueue.main.async {
                self.currentServoDegree = clampedDegree
            }
        }
    }
    
    func updateServoDegree(from data: Data) {
        if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
            if str.hasPrefix("D:") {
                let degreeString = str.dropFirst(2)
                if let degree = Int(degreeString) {
                    DispatchQueue.main.async {
                        self.currentServoDegree = degree
                    }
                }
            }
        }
    }
    
    // Helper function to parse gyro data
    private func parseGyroData(prefix: String, dataString: String) -> [String] {
        if dataString.hasPrefix(prefix) {
            let components = dataString.dropFirst(prefix.count)
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            
            // Ensure we have exactly 3 components (X, Y, Z)
            if components.count == 3 {
                return components
            }
        }
        return ["0.00", "0.00", "0.00"] // Return default if parsing fails
    }
}

extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn {
            DispatchQueue.main.async {
                self.stopScanning()
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        central.stopScan()
        DispatchQueue.main.async {
            self.isScanning = false
            self.connectedPeripheral = peripheral
        }
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([targetServiceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        DispatchQueue.main.async {
            self.connectedPeripheral = nil
            self.gyro1Values = ["0.00", "0.00", "0.00"] // Resetting G1
            self.gyro2Values = ["0.00", "0.00", "0.00"] // Resetting G2
            self.gyro3Values = ["0.00", "0.00", "0.00"] // Resetting G3
            self.batteryPercentage = 0
            self.servoCharacteristic = nil
            self.currentServoDegree = 0
        }
    }
}

extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            if characteristic.properties.contains(.notify) || characteristic.properties.contains(.read) {
                peripheral.setNotifyValue(true, for: characteristic)
                peripheral.readValue(for: characteristic)
            }
            
            if characteristic.uuid == servoCharacteristicUUID {
                DispatchQueue.main.async {
                    self.servoCharacteristic = characteristic
                }
                print("Found servo characteristic: \(characteristic.uuid.uuidString)")
                
                if characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse) {
                    print("Servo characteristic supports writing.")
                } else {
                    print("WARNING: Servo characteristic does not support writing.")
                }
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        
        if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
            // Handling gyro data for G1, G2, G3
            if str.hasPrefix("G1:") {
                DispatchQueue.main.async {
                    self.gyro1Values = self.parseGyroData(prefix: "G1:", dataString: str)
                }
            } else if str.hasPrefix("G2:") {
                DispatchQueue.main.async {
                    self.gyro2Values = self.parseGyroData(prefix: "G2:", dataString: str)
                }
            } else if str.hasPrefix("G3:") {
                DispatchQueue.main.async {
                    self.gyro3Values = self.parseGyroData(prefix: "G3:", dataString: str)
                }
            }
            // Handling battery data
            else if str.hasPrefix("B:") {
                let batteryString = str.dropFirst(2)
                if let batteryValue = Double(batteryString) {
                    DispatchQueue.main.async {
                        self.batteryPercentage = Int(batteryValue)
                        self.syncToCloud()
                    }
                }
            }
            // Handling servo data
            else if str.hasPrefix("D:") {
                updateServoDegree(from: data)
            }
            // Handling prosthetic step count data (cumulative)
            else if str.hasPrefix("S:") {
                let stepString = str.dropFirst(2)
                if let steps = Int(stepString) {
                    // Forward the cumulative step count to HealthKit manager
                    HealthKitManager.shared.receiveProstheticStepCount(steps)
                }
            }
        } else {
            // Fallback for raw byte data that might represent battery percentage
            if data.count == 1 {
                let batteryValue = Int(data.first ?? 0)
                DispatchQueue.main.async {
                    self.batteryPercentage = batteryValue
                    self.syncToCloud()
                }
            }
        }
    }
}

struct BTContentView: View {
    @EnvironmentObject var bt: BluetoothManager

    var body: some View {
        VStack(spacing: 30) {
            Text("Bluetooth Scanner")
                .font(.title.bold())
            
            Button(action: {
                if bt.connectedPeripheral != nil {
                    bt.disconnect()
                } else {
                    bt.isScanning ? bt.stopScanning() : bt.startScanning()
                }
            }) {
                Text(bt.connectedPeripheral != nil ? "Disconnect" : (bt.isScanning ? "Stop Scanning" : "Start Scanning"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(bt.connectedPeripheral != nil ? .red : .blue)

            if bt.connectedPeripheral != nil {
                // Gyro Data display for G1, G2, G3
                VStack(spacing: 20) {
                    Text("Gyro Data")
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                    
                    // G1 Data
                    HStack(spacing: 15) {
                        GyroValueBox(label: "G1 X", value: bt.gyro1Values.indices.contains(0) ? bt.gyro1Values[0] : "0.0")
                        GyroValueBox(label: "G1 Y", value: bt.gyro1Values.indices.contains(1) ? bt.gyro1Values[1] : "0.0")
                        GyroValueBox(label: "G1 Z", value: bt.gyro1Values.indices.contains(2) ? bt.gyro1Values[2] : "0.0")
                    }
                    // G2 Data
                    HStack(spacing: 15) {
                        GyroValueBox(label: "G2 X", value: bt.gyro2Values.indices.contains(0) ? bt.gyro2Values[0] : "0.0")
                        GyroValueBox(label: "G2 Y", value: bt.gyro2Values.indices.contains(1) ? bt.gyro2Values[1] : "0.0")
                        GyroValueBox(label: "G2 Z", value: bt.gyro2Values.indices.contains(2) ? bt.gyro2Values[2] : "0.0")
                    }
                    // G3 Data
                    HStack(spacing: 15) {
                        GyroValueBox(label: "G3 X", value: bt.gyro3Values.indices.contains(0) ? bt.gyro3Values[0] : "0.0")
                        GyroValueBox(label: "G3 Y", value: bt.gyro3Values.indices.contains(1) ? bt.gyro3Values[1] : "0.0")
                        GyroValueBox(label: "G3 Z", value: bt.gyro3Values.indices.contains(2) ? bt.gyro3Values[2] : "0.0")
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))

            } else if bt.isScanning {
                ProgressView("Searching for Arduino...")
                    .padding()
            }
            
            Spacer()
        }
        .padding()
        .animation(.spring(), value: bt.connectedPeripheral)
        .animation(.interactiveSpring(), value: bt.gyro1Values)
        .animation(.interactiveSpring(), value: bt.gyro2Values)
        .animation(.interactiveSpring(), value: bt.gyro3Values)
    }
}

// GyroValueBox struct remains the same
struct GyroValueBox: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.system(.title3, design: .monospaced))
                .fontWeight(.black)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.1))
                .cornerRadius(10)
        }
        .frame(maxWidth: .infinity)
    }
}

