import Foundation
import Observation
import Security
import CryptoKit
import AVFoundation
import UIKit
import Network
import ImageIO

struct ExerciseDemoWallet: Codable {
    let walletId: String
    let balance: Int
    let held: Int
    let available: Int
}
struct ExerciseDemoResult: Codable {
    var enabled: Bool?
    var cost: Int?
    var version: String?
    var status: String?
    var jobId: String?
    var exerciseId: String?
    var sha256: String?
    var bytes: Int?
    var videoPath: String?
    var mediaType: String?
    var verification: String?
    var wallet: ExerciseDemoWallet?
}

/// Small bundled catalog and posters; video bytes live in private R2 and a bounded local cache.
enum CoreExerciseDemos {
    static let revokedHashes: Set<String> = {
        guard let url = Bundle.main.url(forResource: "revoked", withExtension: "json", subdirectory: "CoreExerciseDemos"),
              let data = try? Data(contentsOf: url),
              let hashes = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(hashes)
    }()
    static let assets: [String: ExerciseDemoResult] = {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "CoreExerciseDemos"),
              let data = try? Data(contentsOf: url),
              let rows = try? JSONDecoder().decode([ExerciseDemoResult].self, from: data) else { return [:] }
        return Dictionary(rows.compactMap { row in row.exerciseId.map { ($0, row) } }, uniquingKeysWith: { first, _ in first })
    }()
    static func isUnverified(_ id: String?) -> Bool {
        guard let id else { return false }
        return assets[id]?.verification == "unverified"
    }
    private static let posterSourceHashes: [String: String] = {
        guard let url = Bundle.main.url(forResource: "poster-catalog", withExtension: "json", subdirectory: "CoreExerciseDemos"),
              let data = try? Data(contentsOf: url),
              let hashes = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return hashes
    }()
    static func thumbnail(_ id: String?) -> UIImage? {
        guard let id, let approvedSHA = assets[id]?.sha256, posterSourceHashes[id] == approvedSHA,
              let url = Bundle.main.url(forResource: id, withExtension: "jpg", subdirectory: "CoreExerciseDemos") else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

@MainActor @Observable
final class ExerciseDemoService {
    static let shared = ExerciseDemoService()
    private(set) var files: [String: URL] = [:]
    private(set) var remoteAssets: [String: ExerciseDemoResult] = [:]
    private(set) var hasRemoteCatalog = false
    var availableMediaIDs: Set<String> {
        if hasRemoteCatalog { return Set(remoteAssets.keys) }
        return Set(CoreExerciseDemos.assets.compactMap { id, asset in
            asset.status == "ready" && asset.sha256.map { !CoreExerciseDemos.revokedHashes.contains($0) } == true ? id : nil
        })
    }
    private var catalogRefreshInProgress = false
    private var lastCatalogRefresh: Date?
    private let catalogCacheKey = "exerciseDemo.remoteCatalog.v1"
    private let catalogDefaults: UserDefaults
    private struct RemoteCatalog: Codable { let version: Int; let assets: [ExerciseDemoResult] }

    private func validatedCatalog(_ catalog: RemoteCatalog) -> [String: ExerciseDemoResult]? {
        guard catalog.version == 1, catalog.assets.count <= 2000 else { return nil }
        var result: [String: ExerciseDemoResult] = [:]
        let knownIDs = Set(ExerciseLibrary.all.map(\.id))
        for item in catalog.assets {
            guard let id = item.exerciseId else { return nil }
            guard knownIDs.contains(id) else { continue }
            guard item.status == "ready", let sha = item.sha256, sha.count == 64,
                  sha.allSatisfy({ $0.isHexDigit }), !CoreExerciseDemos.revokedHashes.contains(sha),
                  let size = item.bytes, (1...25*1024*1024).contains(size),
                  item.videoPath == "/v1/exercise-demos/video/\(sha)",
                  item.mediaType == nil || item.mediaType == "video" || item.mediaType == "gif",
                  result[id] == nil else { return nil }
            result[id] = item
        }
        return result
    }

    func refreshAvailableCatalog(force: Bool = false) async {
        guard !catalogRefreshInProgress, force || (lastCatalogRefresh.map({ Date().timeIntervalSince($0) > 3600 }) ?? true) else { return }
        catalogRefreshInProgress = true
        defer { catalogRefreshInProgress = false }
        do {
            let catalog: RemoteCatalog = try await call("catalog", authenticated: false)
            guard let checked = validatedCatalog(catalog) else { return }
            // Invalidate an old displayed file if the approved version changes or is withdrawn.
            for (id, oldFile) in files {
                let newSHA = checked[id]?.sha256
                if newSHA == nil || oldFile.deletingPathExtension().lastPathComponent != newSHA {
                    files.removeValue(forKey: id)
                    self.checked.removeValue(forKey: id)
                }
            }
            remoteAssets = checked
            hasRemoteCatalog = true
            if let bytes = try? JSONEncoder().encode(catalog) { catalogDefaults.set(bytes, forKey: catalogCacheKey) }
            lastCatalogRefresh = Date()
            if !protectedPrefetchIDs.isEmpty { await prefetch(protectedPrefetchIDs, priority: true) }
        } catch { /* Keep the last validated offline snapshot. */ }
    }
    private var checked: [String: Date] = [:]
    private var loading = Set<String>()
    private let network = NWPathMonitor()
    private var permitsPrefetch = false
    private var permitsPriorityPrefetch = false
    private var prefetching = false
    private var pendingPrefetch: [String] = []
    private var priorityPrefetch: [String] = []
    private var protectedPrefetchIDs: [String] = []
    private let session: URLSession
    private let baseURLs: [URL]
    init(session: URLSession = .shared, baseURLs: [URL]? = nil, catalogDefaults: UserDefaults = .standard) {
        self.session = session; self.baseURLs = baseURLs ?? Self.bases; self.catalogDefaults = catalogDefaults
        if let bytes = catalogDefaults.data(forKey: catalogCacheKey),
           let catalog = try? JSONDecoder().decode(RemoteCatalog.self, from: bytes),
           let checked = validatedCatalog(catalog) { remoteAssets = checked; hasRemoteCatalog = true }
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ExerciseDemos")
        for sha in CoreExerciseDemos.revokedHashes {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(sha + ".mp4"))
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(sha + ".gif"))
        }
        network.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.permitsPriorityPrefetch = path.status == .satisfied && !path.isConstrained
                self?.permitsPrefetch = path.status == .satisfied && !path.isExpensive && !path.isConstrained
                await self?.drainPrefetch()
            }
        }
        network.start(queue: DispatchQueue(label: "com.yumowu.maso.demo-network"))
    }
    static var bases: [URL] {
        ["MasoAIProxyURL", "MasoAIProxyFallbackURL"].compactMap {
            guard let value = Bundle.main.object(forInfoDictionaryKey: $0) as? String,
                  let url = URL(string: value), url.scheme == "https", url.host != nil else { return nil }
            return url
        }
    }
    private var clientToken: String { Bundle.main.object(forInfoDictionaryKey: "MasoClientToken") as? String ?? "" }
    enum Failure: Error { case unavailable, insufficientCredits, changedQuote, unknownExercise, download, identity }
    static func message(for error: Error) -> String {
        let key: String
        switch error {
        case Failure.insufficientCredits: key = "demo.insufficient"
        case Failure.changedQuote: key = "demo.quoteChanged"
        case Failure.unknownExercise: key = "demo.unknown"
        default: key = "demo.unavailable"
        }
        return NSLocalizedString(key, comment: "Exercise demo generation")
    }
    private func identity() throws -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.yumowu.maso.demo-wallet", kSecAttrAccount as String: "installation"]
        var result: CFTypeRef?
        var lookup = query; lookup[kSecReturnData as String] = true
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, let token = String(data: data, encoding: .utf8) { return token }
        guard status == errSecItemNotFound else { throw Failure.identity }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw Failure.identity }
        let token = Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        var add = query; add[kSecValueData as String] = Data(token.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw Failure.identity }
        return token
    }
    private func request(_ path: String, base: URL, method: String = "GET", payload: [String: Any]? = nil, authenticated: Bool = true) throws -> URLRequest {
        var req = URLRequest(url: base.appendingPathComponent("v1/exercise-demos").appendingPathComponent(path))
        req.httpMethod = method; req.timeoutInterval = 25
        req.setValue(clientToken, forHTTPHeaderField: "X-Maso-Client-Token")
        if authenticated { req.setValue("Bearer \(try identity())", forHTTPHeaderField: "Authorization") }
        if let payload { req.httpBody = try JSONSerialization.data(withJSONObject: payload); req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return req
    }
    private func call<T: Decodable>(_ path: String, method: String = "GET", payload: [String: Any]? = nil, authenticated: Bool = true) async throws -> T {
        for base in baseURLs {
            do {
                let (data, response) = try await session.data(for: request(path, base: base, method: method, payload: payload, authenticated: authenticated))
                guard let http = response as? HTTPURLResponse else { continue }
                switch http.statusCode {
                case 200..<300: return try JSONDecoder().decode(T.self, from: data)
                case 402: throw Failure.insufficientCredits
                case 409: throw Failure.changedQuote
                case 404: throw Failure.unknownExercise
                default: continue
                }
            } catch let e as Failure { throw e }
            catch { if Task.isCancelled { throw CancellationError() } }
        }
        throw Failure.unavailable
    }
    func quote(_ exerciseID: String) async throws -> ExerciseDemoResult {
        let _: ExerciseDemoWallet = try await call("wallet", method: "POST")
        return try await call("quote", method: "POST", payload: ["exerciseId": exerciseID])
    }
    func generate(_ exerciseID: String, quote: ExerciseDemoResult) async throws -> ExerciseDemoResult {
        guard quote.enabled == true, let cost = quote.cost, let version = quote.version else { throw Failure.unavailable }
        return try await call("jobs", method: "POST", payload: ["exerciseId": exerciseID, "acceptedCost": cost, "version": version, "shareConsent": true])
    }
    func status(_ id: String) async throws -> ExerciseDemoResult { try await call("jobs/\(id)") }
    /// Keep the latest likely workout ahead of ordinary background warming.
    static func mergedPrefetchIDs(_ first: [String], _ second: [String]) -> [String] {
        var seen = Set<String>()
        return (first + second).filter { seen.insert($0).inserted }
    }
    func prefetch(_ exerciseIDs: [String], priority: Bool = false) async {
        let available = availableMediaIDs
        let needed = exerciseIDs.filter { id in
            available.contains(id) && !(files[id].map { FileManager.default.fileExists(atPath: $0.path) } ?? false)
        }
        if priority {
            protectedPrefetchIDs = Self.mergedPrefetchIDs(exerciseIDs, [])
            priorityPrefetch = Self.mergedPrefetchIDs(needed, priorityPrefetch)
            let priorityIDs = Set(priorityPrefetch)
            pendingPrefetch.removeAll { priorityIDs.contains($0) }
        } else {
            let priorityIDs = Set(priorityPrefetch)
            pendingPrefetch = Array(Self.mergedPrefetchIDs(pendingPrefetch, needed.filter { !priorityIDs.contains($0) }).prefix(300))
        }
        Task { await drainPrefetch() }
    }
    private func drainPrefetch() async {
        guard permitsPriorityPrefetch, !prefetching else { return }
        prefetching = true; defer { prefetching = false }
        while permitsPriorityPrefetch && !Task.isCancelled {
            var batch: [String] = []
            while batch.count < 2 && !priorityPrefetch.isEmpty { batch.append(priorityPrefetch.removeFirst()) }
            while batch.count < 2 && permitsPrefetch && !pendingPrefetch.isEmpty { batch.append(pendingPrefetch.removeFirst()) }
            guard !batch.isEmpty else { break }
            await withTaskGroup(of: Void.self) { group in
                for id in batch { group.addTask { await self.loadMedia(id) } }
            }
        }
    }
    func loadMedia(_ exerciseID: String, force: Bool = false) async {
        // A newer catalog may arrive while an older version is downloading.
        // Wait for that request, then resolve the current approved version again.
        while loading.contains(exerciseID) {
            do { try await Task.sleep(for: .milliseconds(100)) }
            catch { return }
        }
        // A cache eviction or a concurrent prefetch can remove the published file.
        // Never throttle a known catalog item that still needs to be displayed.
        if !force, files[exerciseID] != nil, let date = checked[exerciseID], Date().timeIntervalSince(date) < 600 { return }
        loading.insert(exerciseID); defer { loading.remove(exerciseID) }
        do {
            let asset: ExerciseDemoResult
            if let remote = remoteAssets[exerciseID] { asset = remote }
            else if let bundled = CoreExerciseDemos.assets[exerciseID] { asset = bundled }
            else { asset = try await call("assets/\(exerciseID)", authenticated: false) }
            if asset.status == "ready" { try await download(asset, exerciseID: exerciseID) }
            checked[exerciseID] = Date()
        } catch { /* Existing exercise images and instructions remain available. */ }
    }
    private func download(_ asset: ExerciseDemoResult, exerciseID: String) async throws {
        guard let sha = asset.sha256, !CoreExerciseDemos.revokedHashes.contains(sha), sha.count == 64, sha.allSatisfy({ $0.isHexDigit }),
              let size = asset.bytes, (1...25*1024*1024).contains(size),
              asset.videoPath == "/v1/exercise-demos/video/\(sha)" else { throw Failure.download }
        // Existing catalogs have no mediaType; they remain playable MP4s.
        guard asset.mediaType == nil || asset.mediaType == "video" || asset.mediaType == "gif" else { throw Failure.download }
        let isGIF = asset.mediaType == "gif"
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ExerciseDemos", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(sha + (isGIF ? ".gif" : ".mp4"))
        if let data = try? Data(contentsOf: file), SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == sha {
            guard await Self.isPlayable(file, isGIF: isGIF) else { throw Failure.download }
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
            guard !hasRemoteCatalog || remoteAssets[exerciseID]?.sha256 == sha else { return }
            files[exerciseID] = file; return
        }
        var output = Data(); output.reserveCapacity(size)
        while output.count < size {
            try Task.checkCancellation()
            var part: Data?
            for base in baseURLs {
                var req = try request("video/\(sha)", base: base, authenticated: false)
                let end = min(output.count+1024*1024-1, size-1)
                req.setValue("bytes=\(output.count)-\(end)", forHTTPHeaderField: "Range")
                guard let (data, response) = try? await session.data(for: req), let http = response as? HTTPURLResponse,
                      http.statusCode == 206, data.count == end-output.count+1,
                      http.value(forHTTPHeaderField: "Content-Range") == "bytes \(output.count)-\(end)/\(size)" else { continue }
                part = data; break
            }
            guard let part else { throw Failure.download }; output.append(part)
        }
        guard SHA256.hash(data: output).map({ String(format: "%02x", $0) }).joined() == sha else { throw Failure.download }
        // Keep a bounded cache, preserving the currently published file.
        let old = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? []
        var total = output.count
        let protectedHashes = Set(protectedPrefetchIDs.compactMap { id in
            (remoteAssets[id] ?? CoreExerciseDemos.assets[id])?.sha256
        })
        for item in old.sorted(by: { lhs, rhs in
            let leftProtected = protectedHashes.contains(lhs.deletingPathExtension().lastPathComponent)
            let rightProtected = protectedHashes.contains(rhs.deletingPathExtension().lastPathComponent)
            if leftProtected != rightProtected { return leftProtected }
            return ((try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) >
                ((try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }) {
            total += (try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if total > 200*1024*1024 { try? FileManager.default.removeItem(at: item); files = files.filter { $0.value != item } }
        }
        try output.write(to: file, options: .atomic)
        guard await Self.isPlayable(file, isGIF: isGIF) else { try? FileManager.default.removeItem(at: file); throw Failure.download }
        guard !hasRemoteCatalog || remoteAssets[exerciseID]?.sha256 == sha else { return }
        files[exerciseID] = file
    }

    private static func isPlayable(_ url: URL, isGIF: Bool) async -> Bool {
        if isGIF {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  CGImageSourceGetType(source) as String? == "com.compuserve.gif",
                  CGImageSourceGetCount(source) > 0 else { return false }
            return CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
        }
        return (try? await AVURLAsset(url: url).load(.isPlayable)) == true
    }
}
