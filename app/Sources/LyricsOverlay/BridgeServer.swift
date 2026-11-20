import Foundation
import Network

/// What the browser extension reports about the playing video.
struct PlayerState: Decodable {
    var videoId: String?
    var title: String
    var artist: String?      // only set on YouTube Music, where it's reliable
    var channel: String?
    var duration: Double?
    var position: Double?
    var playing: Bool?
    var ad: Bool?
    var rate: Double?
}

/// Local WebSocket server (bound to 127.0.0.1) that the extension connects to.
/// Rejects handshakes from web pages (http/https origins); only extensions may connect.
final class BridgeServer {
    /// The extension always uses 8765; LYRICS_PORT exists only so tests can run beside a live copy.
    static let port: UInt16 = UInt16(ProcessInfo.processInfo.environment["LYRICS_PORT"] ?? "") ?? 8765

    var onState: ((PlayerState) -> Void)?
    var onConnectionCount: ((Int) -> Void)?

    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    func start() throws {
        let ws = NWProtocolWebSocket.Options()
        ws.autoReplyPing = true
        ws.setClientRequestHandler(.main) { _, headers in
            let origin = headers.first { $0.name.lowercased() == "origin" }?.value ?? ""
            let allowed = origin.isEmpty
                || origin.hasPrefix("moz-extension://")
                || origin.hasPrefix("chrome-extension://")
            return NWProtocolWebSocket.Response(status: allowed ? .accept : .reject, subprotocol: nil)
        }

        let params = NWParameters.tcp
        params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        // Bind to 127.0.0.1 only. (requiredInterfaceType alone still listened on all interfaces.)
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: Self.port)!)

        let l = try NWListener(using: params)
        l.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        l.stateUpdateHandler = { state in
            if case .failed(let err) = state { print("Bridge server failed: \(err)") }
        }
        l.start(queue: .main)
        listener = l
    }

    private func accept(_ conn: NWConnection) {
        let id = ObjectIdentifier(conn)
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.connections[id] = conn
                self?.reportCount()
            case .failed, .cancelled:
                self?.connections[id] = nil
                self?.reportCount()
            default: break
            }
        }
        conn.start(queue: .main)
        receive(conn)
    }

    private func reportCount() { onConnectionCount?(connections.count) }

    private func receive(_ conn: NWConnection) {
        conn.receiveMessage { [weak self] data, context, _, error in
            if let data, !data.isEmpty,
               let meta = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata,
               meta.opcode == .text,
               let state = try? JSONDecoder().decode(PlayerState.self, from: data) {
                self?.onState?(state)
            }
            if error == nil { self?.receive(conn) } else { conn.cancel() }
        }
    }
}
