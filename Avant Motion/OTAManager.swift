//
//  OTAManager.swift
//  Avant Motion
//
//  Created by Peyton Ward on 4/3/26.
//

import Foundation
import NetworkExtension // For programmatic Wi-Fi configuration
import Combine

// Define custom errors for OTA process
enum OTAError: LocalizedError {
    case invalidFirmwareURL(String)
    case downloadFailed(Error)
    case fileNotFound(URL)
    case wifiConnectionFailed(String)
    case uploadFailed(Error)
    case invalidServerResponse(Int, String?)
    case missingHotspotConfigurationEntitlement
    case operationCancelled
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidFirmwareURL(let url): return "Invalid firmware URL: \(url)"
        case .downloadFailed(let error): return "Firmware download failed: \(error.localizedDescription)"
        case .fileNotFound(let url): return "Firmware file not found at \(url.lastPathComponent)"
        case .wifiConnectionFailed(let reason): return "Wi-Fi connection failed: \(reason)"
        case .uploadFailed(let error): return "Firmware upload failed: \(error.localizedDescription)"
        case .invalidServerResponse(let statusCode, let message): return "Server responded with status \(statusCode): \(message ?? "No message")"
        case .missingHotspotConfigurationEntitlement: return "Missing 'Hotspot Configuration' entitlement. Cannot programmatically connect to Wi-Fi."
        case .operationCancelled: return "OTA operation cancelled."
        case .unknown(let message): return "An unknown error occurred: \(message)"
        }
    }
}

final class OTAManager: NSObject, ObservableObject, URLSessionDelegate, URLSessionTaskDelegate {
    @Published var otaStatus: OTAStatus = .idle
    @Published var otaProgress: Double = 0.0 // 0.0 to 1.0
    @Published var otaError: String? = nil

    private let firmwareUpdateURL = URL(string: "http://192.168.4.1/update")!
    private let otaHotspotSSID = "Avant-Update"
    private let otaHotspotPassword = "" // Often no password for OTA hotspots, or a default one
    
    private var downloadTask: URLSessionDownloadTask?
    private var uploadTask: URLSessionUploadTask?
    private var temporaryFirmwareFileURL: URL?
    
    private var currentDownloadProgressHandler: ((Double) -> Void)?
    private var currentUploadProgressHandler: ((Double) -> Void)?

    // MARK: - Firmware Download
    func downloadFirmware(githubOwner: String, repoName: String, firmwareFileName: String) async throws -> URL {
        otaStatus = .downloadingFirmware
        otaProgress = 0.0
        otaError = nil

        let rawGitHubURLString = "https://raw.githubusercontent.com/\(githubOwner)/\(repoName)/main/\(firmwareFileName)"
        guard let githubURL = URL(string: rawGitHubURLString) else {
            throw OTAError.invalidFirmwareURL(rawGitHubURLString)
        }

        print("[OTA Manager] Starting firmware download from: \(githubURL)")

        let (tempLocalURL, response) = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(URL, URLResponse), Error>) in
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
            
            self.currentDownloadProgressHandler = { progress in
                DispatchQueue.main.async { self.otaProgress = progress }
            }

            self.downloadTask = session.downloadTask(with: githubURL) { localURL, response, error in
                self.currentDownloadProgressHandler = nil // Clear handler
                if let error = error {
                    continuation.resume(throwing: OTAError.downloadFailed(error))
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode),
                      let localURL = localURL else {
                    continuation.resume(throwing: OTAError.invalidServerResponse((response as? HTTPURLResponse)?.statusCode ?? -1, "Unexpected download response."))
                    return
                }
                continuation.resume(returning: (localURL, httpResponse))
            }
            self.downloadTask?.resume()
        }
        
        // Move the downloaded file to a persistent temporary location
        let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("bin")
        try FileManager.default.moveItem(at: tempLocalURL, to: destinationURL)
        temporaryFirmwareFileURL = destinationURL
        
        print("[OTA Manager] Firmware downloaded to: \(destinationURL.lastPathComponent)")
        return destinationURL
    }

    // MARK: - Wi-Fi Connection
    func connectToOTAHotspot() async throws {
        otaStatus = .connectingToWifi
        otaProgress = 0.0
        otaError = nil
        
        guard NEHotspotConfigurationManager.are   HotspotConfigurationEntitlementsAuthorized else {
            throw OTAError.missingHotspotConfigurationEntitlement
        }

        let config = NEHotspotConfiguration(ssid: otaHotspotSSID)
        config.joinOnce = true // Only connect to this network for this session
        config.passphrase = otaHotspotPassword // Set password if required

        let manager = NEHotspotConfigurationManager.shared
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Remove any existing configuration for this SSID first to ensure a fresh connection
            manager.removeConfiguration(forSSID: otaHotspotSSID) { error in
                if let error = error {
                    print("[OTA Manager] Warning: Failed to remove previous Wi-Fi config: \(error.localizedDescription). Proceeding anyway.")
                }
                
                // Add the new configuration and attempt to connect
                manager.apply(config) { error in
                    if let error = error {
                        print("[OTA Manager] Wi-Fi connection error: \(error.localizedDescription)")
                        continuation.resume(throwing: OTAError.wifiConnectionFailed(error.localizedDescription))
                    } else {
                        print("[OTA Manager] Successfully applied Wi-Fi configuration for \(self.otaHotspotSSID)")
                        // At this point, the configuration is applied, but the device might not have joined yet.
                        // We need to verify actual connection.
                        
                        // Add a small delay and then verify connection
                        // This is a simplified check. A more robust solution might poll current SSID.
                        Task { @MainActor in // Use MainActor for network status checks if they touch UI or system services
                            do {
                                // Wait for a moment for the connection to establish
                                try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                                
                                let currentSSID = await self.getCurrentWiFiSSID()
                                if currentSSID == self.otaHotspotSSID {
                                    print("[OTA Manager] Successfully connected to Wi-Fi hotspot: \(self.otaHotspotSSID)")
                                    continuation.resume(returning: ())
                                } else {
                                    print("[OTA Manager] Failed to verify connection to \(self.otaHotspotSSID). Current SSID: \(currentSSID ?? "None")")
                                    continuation.resume(throwing: OTAError.wifiConnectionFailed("Could not verify connection to \(self.otaHotspotSSID). Current SSID: \(currentSSID ?? "None"). Please check Wi-Fi settings manually."))
                                }
                            } catch {
                                continuation.resume(throwing: error)
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Helper to get current Wi-Fi SSID (requires Access Wi-Fi Information capability)
    @MainActor
    private func getCurrentWiFiSSID() async -> String? {
        // This function requires the "Access Wi-Fi Information" capability.
        // It's part of the `SystemConfiguration` framework, but getting SSID on iOS
        // is restricted to apps that are actively connected to the network
        // via `NEHotspotConfiguration` or have special entitlements.
        // For simplicity, we'll rely on the NEHotspotConfigurationManager callback
        // for connection success, but this could be a fallback.
        // For actual SSID check, you might use CNCopyCurrentNetworkInfo from SystemConfiguration
        // which returns nil if not connected or unauthorized.
        
        // This is a placeholder for a true SSID check. In a real app, you'd use
        // `CNCopyCurrentNetworkInfo` with the appropriate entitlements.
        // For NEHotspotConfiguration, if `apply` succeeds, the system attempts to connect.
        return nil // We'll assume success if apply returns no error for this example.
    }

    // MARK: - Firmware Upload
    func uploadFirmware(fileURL: URL) async throws {
        otaStatus = .uploadingFirmware
        otaProgress = 0.0
        otaError = nil

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw OTAError.fileNotFound(fileURL)
        }

        print("[OTA Manager] Starting firmware upload to: \(firmwareUpdateURL)")

        let boundary = UUID().uuidString
        let mimeType = "application/octet-stream"
        let filename = fileURL.lastPathComponent

        var request = URLRequest(url: firmwareUpdateURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Create the multipart/form-data body
        var body = Data()
        
        // Add the firmware file data
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"firmware\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(try Data(contentsOf: fileURL))
        body.append("\r\n".data(using: .utf8)!)
        
        // End the multipart/form-data
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        
        // Use a temporary file for the upload task to allow progress tracking.
        // URLSession.uploadTask(with:from:) automatically handles the stream.
        let tempUploadFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("upload")
        try body.write(to: tempUploadFile)

        self.currentUploadProgressHandler = { progress in
            DispatchQueue.main.async { self.otaProgress = progress }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.uploadTask = session.uploadTask(with: request, fromFile: tempUploadFile) { data, response, error in
                self.currentUploadProgressHandler = nil // Clear handler
                // Cleanup the temporary upload file
                try? FileManager.default.removeItem(at: tempUploadFile)
                
                if let error = error {
                    continuation.resume(throwing: OTAError.uploadFailed(error))
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    let responseBody = data.flatMap { String(data: $0, encoding: .utf8) }
                    continuation.resume(throwing: OTAError.invalidServerResponse((response as? HTTPURLResponse)?.statusCode ?? -1, responseBody))
                    return
                }
                print("[OTA Manager] Firmware upload successful! Server response: \(String(data: data ?? Data(), encoding: .utf8) ?? "N/A")")
                continuation.resume(returning: ())
            }
            self.uploadTask?.resume()
        }
        
        // Clean up the original downloaded firmware file after successful upload
        try? FileManager.default.removeItem(at: fileURL)
        temporaryFirmwareFileURL = nil
    }
    
    // MARK: - URLSessionTaskDelegate for Progress
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            currentDownloadProgressHandler?(progress)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        if totalBytesExpectedToSend > 0 {
            let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
            currentUploadProgressHandler?(progress)
        }
    }
    
    // MARK: - Cleanup
    deinit {
        downloadTask?.cancel()
        uploadTask?.cancel()
        if let fileURL = temporaryFirmwareFileURL {
            try? FileManager.default.removeItem(at: fileURL)
            print("[OTA Manager] Cleaned up temporary firmware file: \(fileURL.lastPathComponent)")
        }
    }
}
