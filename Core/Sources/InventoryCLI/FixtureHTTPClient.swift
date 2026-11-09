import Foundation
import InventoryCore

struct Fixture {
    let status: Int
    let body: Data
    var delayMs = 0  // lets a test act while a request is in flight
}

/// Answers requests from fixture files instead of the network.
final class FixtureHTTPClient: HTTPClient {
    private let fixtures: [String: Fixture]

    init(fixtures: [String: Fixture]) {
        self.fixtures = fixtures
    }

    /// Reads fixture files; a key in a later file replaces the same key from an earlier one.
    static func load(_ paths: [String]) throws -> [String: Fixture] {
        var fixtures: [String: Fixture] = [:]
        for path in paths {
            let file = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(filePath: path)))
            guard let entries = file as? [String: [String: Any]] else {
                throw FixtureError(description: "\(path): expected {\"<METHOD> <path>\": {\"status\": …}}")
            }
            for (key, entry) in entries {
                guard let status = entry["status"] as? Int else {
                    throw FixtureError(description: "\(path): \(key) has no status")
                }
                let body = try entry["body"].map {
                    try JSONSerialization.data(withJSONObject: $0, options: .fragmentsAllowed)
                }
                fixtures[key] = Fixture(status: status, body: body ?? Data(), delayMs: entry["delayMs"] as? Int ?? 0)
            }
        }
        return fixtures
    }

    /// "GET /products?limit=20&select=title,stock" — the host is ignored.
    static func key(for request: URLRequest) -> String {
        let url = request.url!
        let query = url.query(percentEncoded: true).map { "?\($0)" } ?? ""
        return "\(request.httpMethod ?? "GET") \(url.path(percentEncoded: true))\(query)"
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let key = Self.key(for: request)
        guard let fixture = fixtures[key] else {
            NetworkGuard.record("missing fixture: \(key)")
            throw URLError(.resourceUnavailable)
        }
        if fixture.delayMs > 0 { try await Task.sleep(for: .milliseconds(fixture.delayMs)) }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: fixture.status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"])!
        return (fixture.body, response)
    }
}

struct FixtureError: Error, CustomStringConvertible {
    let description: String
}
