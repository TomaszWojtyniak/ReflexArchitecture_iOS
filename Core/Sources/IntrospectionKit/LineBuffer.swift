#if DEBUG
import Foundation

/// Turns TCP chunks into whole command lines: a command split across packets is
/// joined, several commands in one packet are split. Blank lines and "\r" are dropped.
nonisolated struct LineBuffer {
    private var pending = Data()

    mutating func append(_ data: Data) -> [String] {
        pending.append(data)
        guard let end = pending.lastIndex(of: UInt8(ascii: "\n")) else { return [] }
        let lines = pending[..<end].split(separator: UInt8(ascii: "\n")).map {
            String(decoding: $0, as: UTF8.self).trimmingCharacters(in: .newlines)
        }
        pending = Data(pending[pending.index(after: end)...])
        return lines.filter { !$0.isEmpty }
    }
}
#endif
