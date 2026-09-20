import Foundation

/// URLSession-backed HTTP client.
/// Mirrors the CatVod `net` layer used by the JS bridge (`Global._http`/`req`).
struct HTTPResponse {
    let code: Int
    let status: Int
    let content: String
    let headers: [String: String]
    var dict: [String: Any] {
        ["code": code, "status": status, "content": content, "headers": headers]
    }
}

enum Network {
    static let defaultTimeout: TimeInterval = 20

    private static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = defaultTimeout
        config.timeoutIntervalForResource = defaultTimeout
        return URLSession(configuration: config)
    }

    private static func buildRequest(url: String, method: String, headers: [String: String], body: Data?) -> URLRequest? {
        guard let u = URL(string: url) else { return nil }
        var request = URLRequest(url: u)
        request.httpMethod = method
        request.httpBody = body
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        return request
    }

    private static func interpret(_ data: Data?, _ response: URLResponse?, _ rawHeaders: [String: String]) -> HTTPResponse {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = data ?? Data()
        let content: String
        if let text = String(data: body, encoding: .utf8) {
            content = text
        } else {
            // Non-UTF8 responses (e.g. some video apis) fall back to bytes; JS sees a placeholder.
            content = body.base64EncodedString()
        }
        return HTTPResponse(code: status == 200 ? 200 : 0, status: status, content: content, headers: rawHeaders)
    }

    /// Synchronous request (used by the synchronous JS bridge path).
    static func sync(url: String, method: String = "GET", headers: [String: String] = [:], body: Data? = nil) -> HTTPResponse {
        guard let request = buildRequest(url: url, method: method, headers: headers, body: body) else {
            return HTTPResponse(code: 0, status: 0, content: "", headers: [:])
        }
        let semaphore = DispatchSemaphore(value: 0)
        var result = HTTPResponse(code: 0, status: 0, content: "", headers: [:])
        let task = session().dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            var headers: [String: String] = [:]
            if let http = response as? HTTPURLResponse {
                for (k, v) in (http.allHeaderFields as? [String: String]) ?? [:] { headers[k] = v }
            }
            if error == nil { result = interpret(data, response, headers) }
        }
        task.resume()
        semaphore.wait()
        return result
    }

    /// Asynchronous request (used by the `complete` JS callback path).
    static func async(url: String, method: String = "GET", headers: [String: String] = [:], body: Data? = nil,
                      completion: @escaping (HTTPResponse) -> Void) {
        guard let request = buildRequest(url: url, method: method, headers: headers, body: body) else {
            completion(HTTPResponse(code: 0, status: 0, content: "", headers: [:]))
            return
        }
        session().dataTask(with: request) { data, response, error in
            var headers: [String: String] = [:]
            if let http = response as? HTTPURLResponse {
                for (k, v) in (http.allHeaderFields as? [String: String]) ?? [:] { headers[k] = v }
            }
            if let error = error {
                NSLog("[Network] request failed: %@", error.localizedDescription)
                completion(HTTPResponse(code: 0, status: 0, content: "", headers: headers))
            } else {
                completion(interpret(data, response, headers))
            }
        }.resume()
    }
}
