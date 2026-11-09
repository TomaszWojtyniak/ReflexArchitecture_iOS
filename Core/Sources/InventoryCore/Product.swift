nonisolated public struct Product: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let title: String
    public var stock: Int
}
