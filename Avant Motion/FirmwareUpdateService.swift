import Foundation

struct GitHubRelease: Decodable {
    let tag_name: String
    let name: String?
    let body: String?
}

enum FirmwareUpdateError: Error {
    case invalidURL
    case network(Error)
    case decoding(Error)
    case notFound
}

final class FirmwareUpdateService {
    func fetchLatestRelease(owner: String, repo: String) async throws -> GitHubRelease {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest") else {
            throw FirmwareUpdateError.invalidURL
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw FirmwareUpdateError.network(error)
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw FirmwareUpdateError.notFound
        }
        do {
            return try JSONDecoder().decode(GitHubRelease.self, from: data)
        } catch {
            throw FirmwareUpdateError.decoding(error)
        }
    }
}
