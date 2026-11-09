#if DEBUG
import Foundation
import Testing
@testable import IntrospectionKit

@Test func lineBufferSplitsAndJoinsPackets() {
    var buffer = LineBuffer()
    #expect(buffer.append(Data("ls\ndo In".utf8)) == ["ls"])
    #expect(buffer.append(Data("crement\n".utf8)) == ["do Increment"])
    #expect(buffer.append(Data("ls\r\nls\n\n".utf8)) == ["ls", "ls"])
}
#endif
