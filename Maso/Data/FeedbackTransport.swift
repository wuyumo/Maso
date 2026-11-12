import Foundation

/// Sends one report to the central intake API. The server batches and emails reports weekly.
enum FeedbackTransport {
    private static var clientToken: String {
        Bundle.main.object(forInfoDictionaryKey: "MasoClientToken") as? String ?? ""
    }

    private static var endpoints: [URL] {
        let info = Bundle.main.infoDictionary ?? [:]
        return ["MasoAIProxyURL", "MasoAIProxyFallbackURL"]
            .compactMap { info[$0] as? String }
            .filter { !$0.isEmpty }
            .compactMap { URL(string: "\($0)/feedback") }
    }

    static func send(_ item: FeedbackStore.Item) async -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["MASO_FEEDBACK_TEST_OFFLINE"] == "1" { return false }
        #endif
        guard !clientToken.isEmpty, !endpoints.isEmpty else { return false }
        let payload: [String: Any] = [
            "id": item.id.uuidString,
            "submittedAt": ISO8601DateFormatter().string(from: item.date),
            "body": item.body,
            "appVersion": item.appVersion,
            "osVersion": item.osVersion,
            "language": item.language,
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return false }

        for endpoint in endpoints {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 12
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(clientToken, forHTTPHeaderField: "X-Maso-Client-Token")
            request.httpBody = body
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 202 { return true }
            } catch {
                continue
            }
        }
        return false
    }
}
