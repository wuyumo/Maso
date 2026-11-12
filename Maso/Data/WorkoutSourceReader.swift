import Foundation

/// shortcut: direct public articles on this explicit allowlist only; no login, scraper API or universal video claim.
enum WorkoutSourceReader {
    #if DEBUG
    nonisolated(unsafe) static var fixtureProtocols: [AnyClass]?
    #endif
    static let hosts: Set<String> = ["strongerbyscience.com","www.strongerbyscience.com","muscleandstrength.com","www.muscleandstrength.com","strengthlog.com","www.strengthlog.com","hevyapp.com","www.hevyapp.com","exrx.net","www.exrx.net"]
    static func permits(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
            && hosts.contains(url.host?.lowercased() ?? "")
    }
    static func firstURL(_ text: String) -> URL? {
        guard let detector = try? NSDataDetector(types:NSTextCheckingResult.CheckingType.link.rawValue),
              let match = detector.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)) else { return nil }
        return match.url
    }
    static func visibleText(_ html: String) throws -> String {
        var value = html
        for tag in ["script","style","svg","nav","header","footer","noscript"] {
            value = value.replacingOccurrences(of:"(?is)<" + tag + #"\b[^>]*>.*?</"# + tag + ">",with:" ",options:.regularExpression)
        }
        value = value.replacingOccurrences(of:#"(?i)<(?:br\s*/?|/p|/li|/h[1-6]|/div|/tr)>"#,with:"\n",options:.regularExpression)
        value = value.replacingOccurrences(of:#"<[^>]*>"#,with:" ",options:.regularExpression)
        for (entity,replacement) in ["&nbsp;":" ","&amp;":"&","&quot;":"\"","&#39;":"'","&lt;":"<","&gt;":">"] { value = value.replacingOccurrences(of:entity,with:replacement) }
        value = value.replacingOccurrences(of:#"[ \t]+"#,with:" ",options:.regularExpression)
        value = value.replacingOccurrences(of:#"\n\s*\n+"#,with:"\n",options:.regularExpression).trimmingCharacters(in:.whitespacesAndNewlines)
        guard (120...60000).contains(value.count) else { throw WorkoutSourceError.unreadable }
        return value
    }
    static func read(_ url: URL) async throws -> String {
        guard permits(url) else { throw WorkoutSourceError.unreadable }
        let config = URLSessionConfiguration.ephemeral
        #if DEBUG
        config.protocolClasses = fixtureProtocols
        #endif
        config.httpShouldSetCookies = false; config.httpCookieStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 25
        let session = URLSession(configuration:config,delegate:PublicSourceRedirectGuard(),delegateQueue:nil)
        defer { session.invalidateAndCancel() }
        let (stream,response) = try await session.bytes(from:url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let finalURL = response.url, permits(finalURL), response.expectedContentLength <= 2_000_000 else { throw WorkoutSourceError.unreadable }
        let mime = response.mimeType?.lowercased() ?? ""
        guard ["text/html","text/plain","text/vtt","application/x-subrip"].contains(mime) else { throw WorkoutSourceError.unreadable }
        var data = Data()
        for try await byte in stream {
            if data.count & 8191 == 0 { try Task.checkCancellation() }
            guard data.count < 2_000_000 else { throw WorkoutSourceError.unreadable }
            data.append(byte)
        }
        guard let text = String(data:data,encoding:.utf8) else { throw WorkoutSourceError.unreadable }
        if mime == "text/html" { return try visibleText(text) }
        guard (120...60000).contains(text.count) else { throw WorkoutSourceError.unreadable }
        return text // Real body/subtitle text, never URL/title/thumbnail inference.
    }
}
private final class PublicSourceRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session:URLSession, task:URLSessionTask, willPerformHTTPRedirection response:HTTPURLResponse,
                    newRequest request:URLRequest, completionHandler:@escaping(URLRequest?)->Void) {
        completionHandler(request.url.map(WorkoutSourceReader.permits) == true ? request : nil)
    }
}
