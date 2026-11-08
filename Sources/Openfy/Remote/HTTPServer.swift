import Foundation
import Network

/// A deliberately tiny HTTP/1.1 server for the phone remote: one request per connection,
/// GET/POST with query parameters only (no request bodies). Runs on the main queue.
final class HTTPServer {
    struct Request {
        let method: String
        let path: String
        let query: [String: String]
    }

    struct Response {
        var status = 200
        var contentType = "application/json; charset=utf-8"
        var body = Data()
        var cacheControl = "no-store"

        static func json(_ object: Any) -> Response {
            let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
            return Response(body: data)
        }

        static func text(_ text: String, status: Int, type: String = "text/plain; charset=utf-8") -> Response {
            Response(status: status, contentType: type, body: Data(text.utf8))
        }

        static let notFound = text("Not found", status: 404)
    }

    enum State {
        case ready(port: UInt16)
        case failed(String)
    }

    var handler: (Request) -> Response = { _ in .notFound }
    var onStateChange: ((State) -> Void)?

    private var listener: NWListener?

    /// Listens on `port`, or the next free one if it's taken (up to `fallbacks` more).
    func start(port: UInt16, fallbacks: Int = 10) {
        stop()
        attempt(port: port, remaining: fallbacks)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func attempt(port: UInt16, remaining: Int) {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let nwPort = NWEndpoint.Port(rawValue: port),
              let listener = try? NWListener(using: params, on: nwPort) else {
            onStateChange?(.failed("Couldn't open a network port."))
            return
        }
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self, let listener, listener === self.listener else { return }
            switch state {
            case .ready:
                onStateChange?(.ready(port: listener.port?.rawValue ?? port))
            case .failed(let error), .waiting(let error):
                listener.cancel()
                self.listener = nil
                if remaining > 0 {
                    attempt(port: port &+ 1, remaining: remaining - 1)
                } else {
                    onStateChange?(.failed(error.localizedDescription))
                }
            default:
                break
            }
        }
        listener.start(queue: .main)
    }

    // MARK: Connections

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(connection, buffer: Data())
        // Never keep a silent client around.
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak connection] in connection?.cancel() }
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buffer[..<end.lowerBound], as: UTF8.self)
                send(connection, response(to: head))
            } else if error != nil || isComplete || buffer.count > 32_768 {
                connection.cancel()
            } else {
                receive(connection, buffer: buffer)
            }
        }
    }

    private func response(to head: String) -> Response {
        let requestLine = head.prefix { $0 != "\r" && $0 != "\n" }.split(separator: " ")
        guard requestLine.count >= 2 else { return .text("Bad request", status: 400) }
        let target = requestLine[1]
        let path = target.prefix { $0 != "?" }
        let query = target.dropFirst(path.count + 1)
        return handler(Request(method: String(requestLine[0]),
                               path: Self.decode(path),
                               query: Self.parseQuery(query)))
    }

    private func send(_ connection: NWConnection, _ r: Response) {
        let head = "HTTP/1.1 \(r.status) \(Self.reason(r.status))\r\n"
            + "Content-Type: \(r.contentType)\r\n"
            + "Content-Length: \(r.body.count)\r\n"
            + "Cache-Control: \(r.cacheControl)\r\n"
            + "X-Content-Type-Options: nosniff\r\n"
            + "Connection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + r.body, contentContext: .finalMessage, isComplete: true,
                        completion: .contentProcessed { _ in connection.cancel() })
    }

    // MARK: Parsing

    static func parseQuery(_ s: Substring) -> [String: String] {
        var query: [String: String] = [:]
        for pair in s.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            query[decode(kv[0])] = kv.count > 1 ? decode(kv[1]) : ""
        }
        return query
    }

    static func decode(_ s: Substring) -> String {
        let spaced = s.replacingOccurrences(of: "+", with: " ")
        return spaced.removingPercentEncoding ?? spaced
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: "OK"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        default: "Error"
        }
    }
}
