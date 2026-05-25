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
import NetworkExtension

final class BluetoothManager: NSObject, ObservableObject {
    @Published var isScanning = false
    @Published var connectedPeripheral: CBPeripheral?
    @Published var batteryPercentage: Int = 0
    @Published var firmwareVersion: String? = nil
    @Published var battPercent: [String] = ["0.00"] {
        didSet {
            syncToCloud()
        }
    }
    
    @Published var currentServoDegree: Int = 0
    
    // MARK: - OTA Properties
    @Published var otaStatus: OTAStatus = .idle // Tracks the current status of the OTA update
    @Published var otaProgress: Double = 0.0 // Tracks numerical progress (e.g., for file download/upload)
    @Published var otaError: String? = nil // Stores any error messages during OTA
    
    private var centralManager: CBCentralManager!
    private var desiredPeripheralId: UUID? = nil
    private let targetServiceUUID = CBUUID(string: "19B10000-E8F2-537E-4F6C-D104768A1214")
    
    let servoCharacteristicUUID = CBUUID(string: "19B10001-E8F2-537E-4F6C-D104768A1214")
    
    public var servoCharacteristic: CBCharacteristic?

    let cloudManager = FirebaseCloudManager()
    
    // MARK: - OTA Manager Instance
    // This will be initialized with a strong reference and will perform the Wi-Fi and HTTP parts.
    private lazy var otaManager = OTAManager()

    override init() {
        super.init()
        let btQueue = DispatchQueue(label: "BluetoothQueue", qos: .userInitiated)
        self.centralManager = CBCentralManager(delegate: self, queue: btQueue)
        
        // Observe OTA Manager's published properties
        otaManager.$otaStatus
            .receive(on: DispatchQueue.main)
            .assign(to: &$otaStatus)
        otaManager.$otaProgress
            .receive(on: DispatchQueue.main)
            .assign(to: &$otaProgress)
        otaManager.$otaError
            .receive(on: DispatchQueue.main)
            .assign(to: &$otaError)
    }
    
    /// Attempts to connect to a specific prosthetic leg. If the leg has a known peripheralId, attempts to retrieve and connect. Otherwise, starts scanning.
    func connect(to leg: ProstheticLeg?) {
        desiredPeripheralId = leg?.peripheralId
        guard centralManager.state == .poweredOn else { return }
        if let id = desiredPeripheralId {
            let peripherals = centralManager.retrievePeripherals(withIdentifiers: [id])
            if let p = peripherals.first {
                DispatchQueue.main.async { self.isScanning = false }
                self.connectedPeripheral = p
                p.delegate = self
                centralManager.connect(p, options: nil)
                return
            }
        }
        startScanning()
    }
    
    /// Synchronizes current battery and firmware data to the cloud.
    private func syncToCloud() {
        // Only push if there's battery or firmware data to send
        if firmwareVersion != nil || batteryPercentage != 0 {
            cloudManager.pushData(
                battery: batteryPercentage,
                firmwareVersion: firmwareVersion
            )
        } else {
             print("[BT Sync] No data available to sync.")
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

    private func sendBluetoothCommand(_ commandString: String) {
        guard let peripheral = connectedPeripheral else {
            print("Not connected to a peripheral.")
            return
        }
        guard let characteristic = servoCharacteristic else { // Assuming a single characteristic for commands
            print("Command characteristic not discovered yet or is nil.")
            return
        }
    }
    
    func initiateFirmwareUpdate(githubOwner: String, repoName: String, firmwareFileName: String) {
        let rawGitHubURLString = "https://raw.githubusercontent.com/pwtoothless/Avant-Firmware/main/\(firmwareFileName)"
        guard let downloadURL = URL(string: rawGitHubURLString) else {
            otaError = "Invalid firmware URL."
            otaStatus = .failed
            return
        }

        initiateFirmwareUpdate(downloadURL: downloadURL, fileName: firmwareFileName, targetVersion: nil)
    }

    func initiateFirmwareUpdate(downloadURL: URL, fileName: String, targetVersion: String?) {
        guard connectedPeripheral != nil else {
            otaError = "Not connected to a Bluetooth peripheral."
            otaStatus = .failed
            return
        }
        
        otaStatus = .downloadingFirmware
        otaProgress = 0.0
        otaError = nil
        
        Task {
            do {
                // 1. Download Firmware (must happen before Wi-Fi disconnect)
                let firmwareURL = try await otaManager.downloadFirmware(from: downloadURL, suggestedFileName: fileName)
                
                DispatchQueue.main.async { self.otaStatus = .sendingOtaCommand }
                
                // 2. Trigger Arduino OTA via Bluetooth
                // Ensure this is called on the correct queue for CoreBluetooth
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.async {
                        self.sendBluetoothCommand("D:OTA") // Send the OTA trigger command
                        continuation.resume()
                    }
                }

                // Give the board time to reboot and start its OTA hotspot before joining.
                try await Task.sleep(nanoseconds: 4_000_000_000)
                
                DispatchQueue.main.async { self.otaStatus = .connectingToWifi }
                
                // 3. Connect to Arduino's Wi-Fi network
                try await otaManager.connectToOTAHotspot()
                
                DispatchQueue.main.async { self.otaStatus = .uploadingFirmware }
                
                // 4. Upload Firmware via HTTP POST
                try await otaManager.uploadFirmware(fileURL: firmwareURL)
                
                DispatchQueue.main.async { self.otaStatus = .reconnectingBluetooth }
                
                // 5. Re-establish Bluetooth connection (e.g., call connect(to:) with the last known peripheral ID)
                // For simplicity, we'll just disconnect and let the app handle reconnection logic elsewhere
                // or if the desiredPeripheralId is persistent, connect(to:) might work.
                self.disconnect() // Disconnects Bluetooth
                
                // After OTA, the Arduino might restart and broadcast itself again.
                // We could initiate a scan or attempt to reconnect to `desiredPeripheralId`
                // after a short delay to allow the Arduino to boot up.
                // For now, let's just complete the OTA status.
                
                DispatchQueue.main.async {
                    if let targetVersion {
                        self.firmwareVersion = targetVersion
                    }
                    self.otaStatus = .complete
                }
                print("Firmware update completed successfully!")
                
            } catch {
                DispatchQueue.main.async {
                    self.otaError = error.localizedDescription
                    self.otaStatus = .failed
                    print("Firmware update failed: \(error.localizedDescription)")
                }
                // Attempt to reconnect Bluetooth even on failure for better UX
                self.disconnect()
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
        if let desired = desiredPeripheralId, peripheral.identifier != desired {
            return
        }
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
            self.batteryPercentage = 0
            self.servoCharacteristic = nil
            self.currentServoDegree = 0
            self.firmwareVersion = nil // Reset firmware version on disconnect
            
            // If OTA was in progress and Bluetooth disconnected, it might be expected
            // or an error if it happened unexpectedly mid-process.
            if self.otaStatus == .reconnectingBluetooth {
                self.otaStatus = .complete // Assume this was the final step of a successful OTA
            } else if self.otaStatus != .idle && self.otaStatus != .complete && self.otaStatus != .failed {
                // Unexpected disconnect during an active OTA phase
                self.otaError = "Bluetooth disconnected unexpectedly during OTA."
                self.otaStatus = .failed
            }
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
            print("Discovered characteristic: \(characteristic.uuid.uuidString) with properties: \(characteristic.properties)") // Log discovered characteristics
            
            // Set notify value if the characteristic supports it
            if characteristic.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: characteristic)
                print("  -> Set to notify for \(characteristic.uuid.uuidString)")
            }
            
            // Read initial value only if the characteristic supports reading
            if characteristic.properties.contains(.read) {
                peripheral.readValue(for: characteristic)
                print("  -> Read initial value for \(characteristic.uuid.uuidString)")
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
        if let error = error {
            print("[\(characteristic.uuid.uuidString)] Error updating value: \(error.localizedDescription)")
            return
        }
        
        guard let data = characteristic.value else {
            print("[\(characteristic.uuid.uuidString)] Received no data for characteristic.")
            return
        }
        
        if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
            print("[\(characteristic.uuid.uuidString)] Received data string: \"\(str)\"") // Log all received data strings
            // Handling battery data
            if str.hasPrefix("B:") {
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
            // Handling firmware version data
            else if str.hasPrefix("FW:") {
                let version = String(str.dropFirst(3))
                DispatchQueue.main.async {
                    self.firmwareVersion = version
                    self.syncToCloud() // <-- Trigger cloud sync when firmware version is updated
                }
                print("[\(characteristic.uuid.uuidString)] Parsed Firmware Version: \(version)") // Log parsed firmware
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
            // Fallback for raw byte data that might represent battery percentage or other unparseable data
            if data.count == 1 {
                let batteryValue = Int(data.first ?? 0)
                DispatchQueue.main.async {
                    self.batteryPercentage = batteryValue
                    self.syncToCloud()
                }
                print("[\(characteristic.uuid.uuidString)] Received single byte data (likely battery): \(batteryValue)")
            } else {
                print("[\(characteristic.uuid.uuidString)] Received unparseable data (non-UTF8 string, not single byte): \(data.hexEncodedString())")
            }
        }
    }
}

// Helper extension for Data to print raw bytes
extension Data {
    func hexEncodedString() -> String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
}

// MARK: - OTA Status Enum
enum OTAStatus: String {
    case idle = "Idle"
    case downloadingFirmware = "Downloading Firmware..."
    case sendingOtaCommand = "Sending OTA command..."
    case connectingToWifi = "Connecting to Arduino WiFi..."
    case uploadingFirmware = "Uploading Firmware..."
    case reconnectingBluetooth = "Reconnecting Bluetooth..."
    case complete = "OTA Complete!"
    case failed = "OTA Failed"
}

struct BTContentView: View {
    @EnvironmentObject var bt: BluetoothManager
    //@EnvironmentObject var appSettings: AppSettings

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

            if bt.isScanning {
                ProgressView("Searching for Arduino...")
                    .padding()
            }
            
            Spacer()
        }
        .padding()
        .animation(.spring(), value: bt.connectedPeripheral)

        .animation(.interactiveSpring(), value: bt.firmwareVersion) // Animate changes to firmware version
        .animation(.interactiveSpring(), value: bt.otaStatus) // Animate OTA status changes
        .animation(.interactiveSpring(), value: bt.otaProgress) // Animate OTA progress changes
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
