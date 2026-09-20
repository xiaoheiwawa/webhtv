import Foundation

/// Minimal UTF-8 HTTP client backed by URLSession.
/// Stage one: blocking request; async/body/headers/redirect semantics added in the network milestone.
enum Network {
    static func request(url: String, options: [String: Any] = [:]) -> [String: Any] {
        guard let u = URL(string: url) else {
            return ["code": 0, "content": "", "status": 0]
        }
        let semaphore = DispatchSemaphore(value: 0)
        var responseDict: [String: Any] = ["code": 0, "content": "", "status": 0]
        var task: URLSessionDataTask?
        task = URLSession.shared.dataTask(with: u) { data, response, error in
            defer { semaphore.signal() }
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            responseDict = ["code": status == 200 ? 200 : 0, "content": body, "status": status]
        }
        task?.resume()
        semaphore.wait()
        return responseDict
    }
}
