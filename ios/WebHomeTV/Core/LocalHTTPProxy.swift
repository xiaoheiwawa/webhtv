import Foundation
import Network

/// Minimal blocking HTTP client for forwarding (used by the local proxy).
private enum HTTPForward {
    static func getData(url: String, headers: [String: String], range: String?) -> (status: Int, headers: [String: String], data: Data?) {
        guard let u = URL(string: url) else { return (400, [:], nil) }
        var request = URLRequest(url: u)
        request.httpMethod = "GET"
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        if let range, !range.isEmpty { request.setValue(range, forHTTPHeaderField: "Range") }
        let sem = DispatchSemaphore(value: 0)
        var status = 0
        var respHeaders: [String: String] = [:]
        var data: Data?
        URLSession.shared.dataTask(with: request) { d, resp, _ in
            defer { sem.signal() }
            if let h = resp as? HTTPURLResponse {
                status = h.statusCode
                for (k, v) in (h.allHeaderFields as? [String: String]) ?? [:] {
                    respHeaders[k.lowercased()] = v
                }
            }
            data = d
        }.resume()
        sem.wait()
        return (status, respHeaders, data)
    }
}

/// Local HTTP server backing `net.resourceUrl` and offering a `/proxy` hook route.
///
/// Serves plaintext TCP via `NWListener`. Reads the request line (GET/HEAD) and query, forwards
/// `/webResource?url=...` through URLSession, and streams back the response with CORS headers.
final class LocalHTTPProxy {

    static let shared = LocalHTTPProxy()
    private static let defaultPort: UInt16 = 8080

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "webhometv.httpproxy")
    private var port: UInt16 = 0

    private init() {}

    var address: String { "http://127.0.0.1:\(port)" }

    func start(port: UInt16 = defaultPort) throws {
        guard listener == nil else { return }
        self.port = port
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.stateUpdateHandler = { state in
            print("[LocalHTTPProxy] state=\(state)")
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection handling

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            var buf = buffer
            if let data { buf.append(data) }
            if !isComplete && error == nil {
                self.receive(connection, buffer: buf)
                return
            }
            self.process(connection, request: buf)
        }
    }

    private func process(_ connection: NWConnection, request: Data) {
        guard let text = String(data: request, encoding: .utf8), !text.isEmpty else {
            respond(connection, status: 400, contentType: "text/plain", body: Data("Bad Request".utf8), headOnly: false)
            return
        }
        let lines = text.components(separatedBy: "\r\n")
        let requestLine = lines.first ?? ""
        let parts = requestLine.split(separator: " ").map(String.init)
        guard parts.count >= 2, parts[0] == "GET" || parts[0] == "HEAD" else {
            respond(connection, status: 405, contentType: "text/plain", body: Data("Method Not Allowed".utf8), headOnly: false)
            return
        }
        let method = parts[0]
        let pathAndQuery = parts[1]
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let hp = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if hp.count == 2 { headers[hp[0].lowercased()] = hp[1] }
        }
        handleRequest(connection, method: method, pathAndQuery: pathAndQuery, headers: headers)
    }

    private func handleRequest(_ connection: NWConnection, method: String, pathAndQuery: String, headers: [String: String]) {
        if pathAndQuery.hasPrefix("/webResource") {
            let urlString = "http://localhost\(pathAndQuery)"
            guard let comps = URLComponents(string: urlString) else {
                respond(connection, status: 400, contentType: "text/plain", body: Data("bad request".utf8), headOnly: false)
                return
            }
            let params = (comps.queryItems ?? []).reduce(into: [String: String]()) { $0[$1.name] = ($1.value ?? "") }
            guard let target = params["url"], !target.isEmpty else {
                respond(connection, status: 400, contentType: "text/plain", body: Data("missing url".utf8), headOnly: false)
                return
            }
            let range = headers["range"]
            let result = HTTPForward.getData(url: target, headers: Self.parseHeaders(params["headers"]), range: range)
            if let data = result.data {
                var respHeaders = result.headers
                if respHeaders["content-type"] == nil { respHeaders["content-type"] = "application/octet-stream" }
                respHeaders["access-control-allow-origin"] = "*"
                var head = "HTTP/1.1 \(result.status) \(statusText(result.status))\r\n"
                for (k, v) in respHeaders { head += "\(k): \(v)\r\n" }
                head += "Content-Length: \(data.count)\r\n\r\n"
                var out = head.data(using: .utf8) ?? Data()
                if method != "HEAD" { out.append(data) }
                send(connection, out, thenClose: true)
            } else {
                respond(connection, status: 502, contentType: "text/plain", body: Data("Bad gateway".utf8), headOnly: method == "HEAD")
            }
            return
        }
        if pathAndQuery.hasPrefix("/proxy") {
            respond(connection, status: 404, contentType: "text/plain", body: Data("proxy not wired".utf8), headOnly: method == "HEAD")
            return
        }
        respond(connection, status: 404, contentType: "text/plain", body: Data("not found".utf8), headOnly: method == "HEAD")
    }

    /// `headers` is the JSON object a page passes to `net.resourceUrl(url, { headers })`.
    /// `credentials=include` (cookie forwarding) is not implemented yet.
    private static func parseHeaders(_ raw: String?) -> [String: String] {
        guard let raw, !raw.isEmpty, let data = raw.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [:] }
        var out: [String: String] = [:]
        for (key, value) in object { out[key] = "\(value)" }
        return out
    }

    // MARK: - Reply helpers

    private func respond(_ connection: NWConnection, status: Int, contentType: String, body: Data, headOnly: Bool) {
        let head = statusLine(status) + "Content-Type: \(contentType)\r\nContent-Length: \(body.count)\r\n\r\n"
        var out = head.data(using: .utf8) ?? Data()
        if !headOnly { out.append(body) }
        send(connection, out, thenClose: true)
    }

    private func send(_ connection: NWConnection, _ data: Data, thenClose: Bool) {
        connection.send(content: data, completion: .contentProcessed { [weak connection] _ in
            if thenClose { connection?.cancel() }
        })
    }

    private func statusLine(_ code: Int) -> String { "HTTP/1.1 \(code) \(statusText(code))\r\n" }
    private func statusText(_ code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 206: return "Partial Content"
        case 304: return "Not Modified"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 502: return "Bad Gateway"
        default: return "Status"
        }
    }
}
