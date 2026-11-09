import Foundation
import Testing
@testable import InventoryCLI

@Suite(.serialized) struct NetworkGuardTests {
    @Test func requestsThroughTheSharedSessionAreBlockedAndRecorded() async {
        NetworkGuard.reset()
        NetworkGuard.install()
        await #expect(throws: (any Error).self) {
            _ = try await URLSession.shared.data(from: URL(string: "https://example.com/ping")!)
        }
        #expect(NetworkGuard.violations == ["GET https://example.com/ping"])
    }

    @Test func requestsWithoutAFixtureAreRecorded() async throws {
        NetworkGuard.reset()
        let client = FixtureHTTPClient(fixtures: [
            "GET /products?limit=20&select=title,stock": Fixture(status: 200, body: Data("{}".utf8)),
        ])
        let (body, response) = try await client.send(
            URLRequest(url: URL(string: "https://dummyjson.com/products?limit=20&select=title,stock")!))
        #expect(response.statusCode == 200)
        #expect(body == Data("{}".utf8))

        var put = URLRequest(url: URL(string: "https://dummyjson.com/products/7")!)
        put.httpMethod = "PUT"
        await #expect(throws: (any Error).self) { _ = try await client.send(put) }
        #expect(NetworkGuard.violations == ["missing fixture: PUT /products/7"])
    }
}
