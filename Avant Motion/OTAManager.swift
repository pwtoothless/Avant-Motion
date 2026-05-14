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

extension NEHotspotConfigurationManager {
    /// Asynchronously applies a new Wi-Fi hotspot configuration.
    func apply(_ configuration: NEHotspotConfiguration) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            // Explicitly use 'completionHandler' label to avoid "Extra trailing closure" error
            // FIX: Call the original method on NEHotspotConfigurationManager.shared
            NEHotspotConfigurationManager.shared.apply(configuration, completionHandler: { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            })
        }
    }
    
}


final class OTAManager: NSObject, ObservableObject, URLSessionDelegate, URLSessionTaskDelegate, URLSessionDownloadDelegate {
    @Published var otaStatus: OTAStatus = .idle
    @Published var otaProgress: Double = 0.0 // 0.0 to 1.0
    @Published var otaError: String? = nil

    private let firmwareUpdateURL = URL(string: "http://192.168.4.1/update")!
    private let firmwareProbeURL = URL(string: "http://192.168.4.1/")!
    private let otaHotspotSSID = "Avant-Update"
    private let otaHotspotPassword = "" // Often no password for OTA hotspots, or a default one
    
    private var downloadTask: URLSessionDownloadTask?
    private var uploadTask: URLSessionUploadTask?
    private var temporaryFirmwareFileURL: URL?
    private var temporaryUploadFileURL: URL?
    
    // Continuations for async operations
    private var downloadContinuation: CheckedContinuation<URL, Error>? // Changed this line
    private var uploadContinuation: CheckedContinuation<Void, Error>?

    // MARK: - Firmware Download
    func downloadFirmware(githubOwner: String, repoName: String, firmwareFileName: String) async throws -> URL {
        let rawGitHubURLString = "https://raw.githubusercontent.com/\(githubOwner)/\(repoName)/main/\(firmwareFileName)"
        guard let githubURL = URL(string: rawGitHubURLString) else {
            throw OTAError.invalidFirmwareURL(rawGitHubURLString)
        }

        return try await downloadFirmware(from: githubURL, suggestedFileName: firmwareFileName)
    }

    func downloadFirmware(from remoteURL: URL, suggestedFileName: String? = nil) async throws -> URL {
        otaStatus = .downloadingFirmware
        otaProgress = 0.0
        otaError = nil

        print("[OTA Manager] Starting firmware download from: \(remoteURL)")

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) -> Void in
            self.downloadContinuation = continuation // Store continuation
            
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
            var request = URLRequest(url: remoteURL)
            if let suggestedFileName, !suggestedFileName.isEmpty {
                request.setValue("attachment; filename=\"\(suggestedFileName)\"", forHTTPHeaderField: "Content-Disposition")
            }
            self.downloadTask = session.downloadTask(with: request)
            self.downloadTask?.resume()
        }
    }

    // MARK: - Wi-Fi Connection
    func connectToOTAHotspot() async throws {
        otaStatus = .connectingToWifi
        otaProgress = 0.0
        otaError = nil

        let firmwareHostReachable = await isFirmwareHostReachable()
        if firmwareHostReachable {
            print("[OTA Manager] OTA host is already reachable at \(firmwareProbeURL.absoluteString).")
            return
        }
        
        let config = otaHotspotPassword.isEmpty
            ? NEHotspotConfiguration(ssid: otaHotspotSSID)
            : NEHotspotConfiguration(ssid: otaHotspotSSID, passphrase: otaHotspotPassword, isWEP: false)
        config.joinOnce = true

        let manager = NEHotspotConfigurationManager.shared
        
        let maxJoinAttempts = 5
        var lastApplyErrorDescription: String?
        for attempt in 1...maxJoinAttempts {
            do {
                try await manager.apply(config)
                print("[OTA Manager] Successfully applied Wi-Fi configuration for \(self.otaHotspotSSID) on attempt \(attempt).")
                break
            } catch {
                let nsError = error as NSError
                lastApplyErrorDescription = error.localizedDescription
                print("[OTA Manager] Wi-Fi connection error during apply on attempt \(attempt): \(error.localizedDescription)")

                if nsError.domain == NEHotspotConfigurationErrorDomain,
                   let neError = NEHotspotConfigurationError(rawValue: nsError.code) {
                    if neError == .systemDenied {
                        print("[OTA Manager] Hotspot configuration was denied by the system. Falling back to manual Wi-Fi connection.")
                        break
                    }

                    if neError == .alreadyAssociated {
                        print("[OTA Manager] Already associated with \(otaHotspotSSID). Proceeding to verification.")
                        break
                    }
                }

                if attempt == maxJoinAttempts {
                    print("[OTA Manager] Auto-join failed after \(maxJoinAttempts) attempts. Waiting for the OTA host to become reachable instead.")
                    break
                }

                try await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
        
        // Wait for the phone to finish switching routes and for the OTA server to respond.
        let maxAttempts = 30
        let delaySeconds: UInt64 = 2

        for attempt in 1...maxAttempts {
            try await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)

            if await isFirmwareHostReachable() {
                print("[OTA Manager] OTA host became reachable after \(attempt) attempts.")
                return
            }

            print("[OTA Manager] Attempt \(attempt)/\(maxAttempts): OTA host is not reachable yet at \(firmwareProbeURL.absoluteString).")
        }

        let reason = lastApplyErrorDescription.map { " Last Wi-Fi join error: \($0)." } ?? ""
        throw OTAError.wifiConnectionFailed("Could not reach the OTA device at \(firmwareProbeURL.host ?? "192.168.4.1") after \(maxAttempts * Int(delaySeconds)) seconds.\(reason)")
    }
    
    // The previous getCurrentWiFiSSID helper is removed as it's now handled by the NEHotspotConfigurationManager extension.

    // MARK: - Firmware Upload
    func uploadFirmware(fileURL: URL) async throws {
        otaStatus = .uploadingFirmware
        otaProgress = 0.0
        otaError = nil

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw OTAError.fileNotFound(fileURL)
        }

        guard await isFirmwareHostReachable() else {
            throw OTAError.wifiConnectionFailed("Connected to Wi-Fi, but the OTA server at \(firmwareProbeURL.host ?? "192.168.4.1") is not responding yet.")
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
        
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 180
        configuration.waitsForConnectivity = true
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
        
        // Use a temporary file for the upload task to allow progress tracking.
        // URLSession.uploadTask(with:from:) automatically handles the stream.
        let tempUploadFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("upload")
        try body.write(to: tempUploadFile)
        temporaryUploadFileURL = tempUploadFile

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.uploadContinuation = continuation // Store continuation
            self.uploadTask = session.uploadTask(with: request, fromFile: tempUploadFile)
            self.uploadTask?.resume()
        }
        
        // Clean up the original downloaded firmware file after successful upload
        try? FileManager.default.removeItem(at: fileURL)
        temporaryFirmwareFileURL = nil
    }

    private func isFirmwareHostReachable() async -> Bool {
        var request = URLRequest(url: firmwareProbeURL)
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5

        do {
            let (_, response) = try await URLSession(configuration: configuration).data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                print("[OTA Manager] Reachability probe received status \(httpResponse.statusCode).")
                return true
            }
        } catch {
            print("[OTA Manager] Reachability probe failed: \(error.localizedDescription)")
        }

        return false
    }
    
    // MARK: - URLSessionDelegate Methods
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            DispatchQueue.main.async { self.otaProgress = progress }
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard downloadTask === self.downloadTask else { return }

        // Move the downloaded file to a persistent temporary location
        let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("bin")
        do {
            try FileManager.default.moveItem(at: location, to: destinationURL)
            temporaryFirmwareFileURL = destinationURL
            print("[OTA Manager] Firmware downloaded to: \(destinationURL.lastPathComponent)")
            downloadContinuation?.resume(returning: destinationURL)
        } catch {
            downloadContinuation?.resume(throwing: OTAError.downloadFailed(error))
        }
        downloadContinuation = nil // Clear continuation
        self.downloadTask = nil
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        if totalBytesExpectedToSend > 0 {
            let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
            DispatchQueue.main.async { self.otaProgress = progress }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if task === downloadTask {
            if let error = error {
                downloadContinuation?.resume(throwing: OTAError.downloadFailed(error))
            } else {
                // If it's a download task and completed without error, but didFinishDownloadingTo wasn't called (unlikely for successful completion)
                // or if it's a download task that completed with an HTTP error that wasn't caught earlier.
                // This specific scenario is generally handled by didFinishDownloadingTo for success.
                // If there's an HTTP error, the URLSession task error usually includes enough info.
                downloadContinuation?.resume(throwing: OTAError.downloadFailed(error ?? OTAError.unknown("Download completed with unexpected error state.")))
            }
            downloadContinuation = nil
            self.downloadTask = nil
        } else if task === uploadTask {
            if let temporaryUploadFileURL {
                try? FileManager.default.removeItem(at: temporaryUploadFileURL)
                self.temporaryUploadFileURL = nil
            }

            if let error = error {
                uploadContinuation?.resume(throwing: OTAError.uploadFailed(error))
            } else {
                guard let httpResponse = task.response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    // Try to read response body for more details if available
                    // Note: 'data' is not directly available here as we are using fromFile for upload
                    // The server response details will be less granular here.
                    uploadContinuation?.resume(throwing: OTAError.invalidServerResponse((task.response as? HTTPURLResponse)?.statusCode ?? -1, "Server responded with error."))
                    return
                }
                print("[OTA Manager] Firmware upload successful!")
                uploadContinuation?.resume(returning: ())
            }
            uploadContinuation = nil
            self.uploadTask = nil
        }
    }
    
    // MARK: - Cleanup
    deinit {
        downloadTask?.cancel()
        uploadTask?.cancel()
        downloadContinuation?.resume(throwing: OTAError.operationCancelled)
        uploadContinuation?.resume(throwing: OTAError.operationCancelled)
        if let fileURL = temporaryFirmwareFileURL {
            try? FileManager.default.removeItem(at: fileURL)
            print("[OTA Manager] Cleaned up temporary firmware file: \(fileURL.lastPathComponent)")
        }
        if let temporaryUploadFileURL {
            try? FileManager.default.removeItem(at: temporaryUploadFileURL)
            print("[OTA Manager] Cleaned up temporary upload file: \(temporaryUploadFileURL.lastPathComponent)")
        }
    }
}
