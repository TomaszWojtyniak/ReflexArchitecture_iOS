import Foundation

/// DummyJSON's two inventory endpoints. Writes are simulated there, so the
/// status alone confirms a save and the response body is ignored.
struct InventoryAPI {
    let http: any HTTPClient

    func products() async throws -> [Product] {
        let url = URL(string: "https://dummyjson.com/products?limit=20&select=title,stock")!
        return try JSONDecoder().decode(Page.self, from: try await send(URLRequest(url: url))).products
    }

    func save(id: Int, stock: Int) async throws {
        var request = URLRequest(url: URL(string: "https://dummyjson.com/products/\(id)")!)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["stock": stock])
        _ = try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await http.send(request)
        guard (200..<300).contains(response.statusCode) else { throw HTTPStatusError(status: response.statusCode) }
        return data
    }

    private struct Page: Decodable {
        let products: [Product]
    }
}

struct HTTPStatusError: Error {
    let status: Int
}
