import Foundation
import IntrospectionKit
import InventoryCore

/// The headless host: Core built on fixtures, one command per stdin line, one answer per stdout line.
@main
enum CLI {
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.first == "--fixtures", arguments.count > 1 else {
            fail("usage: inventory-cli --fixtures <file.json>...", code: 64)
        }
        let fixtures: [String: Fixture]
        do {
            fixtures = try FixtureHTTPClient.load(Array(arguments.dropFirst()))
        } catch {
            fail("cannot load fixtures: \(error)", code: 66)
        }

        NetworkGuard.install()
        let session = IntrospectionSession(root: InventoryApp(http: FixtureHTTPClient(fixtures: fixtures)))
        // Async reading lets effects (service Tasks) run between commands.
        for try await line in FileHandle.standardInput.bytes.lines
        where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            let answer = session.handle(line)
            let violations = NetworkGuard.violations
            if !violations.isEmpty {
                fail(violations.map { "network violation: \($0)" }.joined(separator: "\n"), code: 3)
            }
            // Unbuffered on purpose: a piped stdout would otherwise hold answers back.
            FileHandle.standardOutput.write(Data((answer + "\n").utf8))
        }
    }

    static func fail(_ message: String, code: Int32) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(code)
    }
}
