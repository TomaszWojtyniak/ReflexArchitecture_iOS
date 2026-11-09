#if DEBUG
import Foundation
import Network

/// The live counterpart of the headless CLI: the same protocol over TCP, answered by the
/// running app's own ViewModels, so the UI follows the terminal (`nc localhost 7777`).
/// Debug builds only, local connections only.
public final class IntrospectionServer {
    private let listener: NWListener
    private let session: IntrospectionSession
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    public init(port: UInt16, session: IntrospectionSession) throws {
        // Loopback only: reachable from this Mac (a simulator shares its network), never from the LAN.
        // acceptLocalOnly would be the obvious knob, but the iOS simulator silently drops those
        // connections (its NECP setup fails: "SO_NECP_LISTENUUID failed").
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port)!)
        listener = try NWListener(using: parameters)
        self.session = session
    }

    /// Listener and connections run on the main queue, so callbacks may enter the main actor directly.
    // ponytail: the handlers hold the server strongly on purpose; it never stops, so it lives as long as the app.
    public func start() {
        listener.newConnectionHandler = { connection in
            MainActor.assumeIsolated { self.accept(connection) }
        }
        listener.start(queue: .main)
    }

    private func accept(_ connection: NWConnection) {
        connections[ObjectIdentifier(connection)] = connection
        connection.start(queue: .main)
        receive(on: connection, buffer: LineBuffer())
    }

    private func receive(on connection: NWConnection, buffer: LineBuffer) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
            MainActor.assumeIsolated {
                var buffer = buffer
                for line in buffer.append(data ?? Data()) {
                    connection.send(content: Data((self.session.handle(line) + "\n").utf8), completion: .idempotent)
                }
                if isComplete || error != nil {
                    // Close only after the answers above have gone out.
                    connection.send(
                        content: nil, contentContext: .finalMessage, isComplete: true,
                        completion: .contentProcessed { _ in
                            connection.cancel()
                            MainActor.assumeIsolated { self.connections[ObjectIdentifier(connection)] = nil }
                        })
                } else {
                    self.receive(on: connection, buffer: buffer)
                }
            }
        }
    }
}
#endif
