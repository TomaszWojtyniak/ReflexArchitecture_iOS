#if DEBUG
import Foundation
import Testing
@testable import IntrospectionKit

/// Talks to the server the way a person does: `printf 'ls\nls\n' | nc -w 1 127.0.0.1 <port>`.
@Test func serverAnswersEachLineOverTCP() async throws {
    let server = try IntrospectionServer(port: 7798, session: IntrospectionSession(root: Container()))
    server.start()
    try await Task.sleep(for: .milliseconds(100))

    let nc = Process()
    nc.executableURL = URL(filePath: "/usr/bin/nc")
    nc.arguments = ["-w", "1", "127.0.0.1", "7798"]
    let input = Pipe()
    let output = Pipe()
    nc.standardInput = input
    nc.standardOutput = output
    try nc.run()
    input.fileHandleForWriting.write(Data("ls\ndo Bump\n".utf8))
    try input.fileHandleForWriting.close()
    while nc.isRunning { try await Task.sleep(for: .milliseconds(20)) }

    let answer = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    #expect(answer == """
        Leaf
          state   {"count":0}
          actions Bump, Set {value}, goBack, close
        ok

        """)
}
#endif
