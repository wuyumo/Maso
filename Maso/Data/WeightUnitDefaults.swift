import Foundation

/// Gym plate convention for a coarse ISO 3166-1 alpha-2 country. Language and
/// App Store storefront are not inputs. Pounds are the commercial gym standard
/// in the US and US territories; IWF/IPF and UK, Canadian, and Australian gyms
/// load kilograms (a 20 kg bar), including English-speaking GB.
enum GymWeightConvention {
    static let poundPlateCountries: Set<String> = ["US", "PR", "GU", "VI", "AS", "MP"]

    static func normalize(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              trimmed.count == 2, trimmed.allSatisfy(\.isLetter),
              trimmed != "XX", trimmed != "T1" else { return nil }
        return trimmed
    }

    /// Nil when the code is missing or not a real alpha-2 country.
    static func unitIfRecognized(_ raw: String?) -> WeightUnit? {
        guard let code = normalize(raw) else { return nil }
        return poundPlateCountries.contains(code) ? .lb : .kg
    }

    static func unit(countryCode raw: String?) -> WeightUnit {
        unitIfRecognized(raw) ?? .kg
    }
}

struct WeightUnitDefaultState: Equatable {
    var unit: WeightUnit
    var origin: WeightUnitDefaultOrigin
}

enum WeightUnitDefaulting {
    static func state(unit: WeightUnit, storedOrigin: String?) -> WeightUnitDefaultState {
        guard let storedOrigin, let origin = WeightUnitDefaultOrigin(rawValue: storedOrigin) else {
            return WeightUnitDefaultState(unit: unit, origin: .manual)
        }
        return WeightUnitDefaultState(unit: unit, origin: origin)
    }

    static func shouldRequestIP(_ state: WeightUnitDefaultState) -> Bool {
        state.origin == .pending
    }

    static func provisional(deviceCountry: String?) -> WeightUnitDefaultState {
        WeightUnitDefaultState(unit: GymWeightConvention.unit(countryCode: deviceCountry), origin: .pending)
    }

    static func applyIP(country: String?, to state: WeightUnitDefaultState) -> WeightUnitDefaultState {
        guard state.origin == .pending else { return state }
        guard let unit = GymWeightConvention.unitIfRecognized(country) else {
            return WeightUnitDefaultState(unit: state.unit, origin: .device)
        }
        return WeightUnitDefaultState(unit: unit, origin: .ip)
    }

    static func applyFailure(to state: WeightUnitDefaultState) -> WeightUnitDefaultState {
        guard state.origin == .pending else { return state }
        return WeightUnitDefaultState(unit: state.unit, origin: .device)
    }

    static func userSelected(_ unit: WeightUnit) -> WeightUnitDefaultState {
        WeightUnitDefaultState(unit: unit, origin: .manual)
    }
}

enum WeightUnitLookupError: Error { case notConfigured, unavailable }

/// Reads `{ "country": "CN" }` from the existing app proxy. The route is served
/// by backend/shared/handler.mjs; this client does not call a geo vendor.
struct ProxyIPCountryClient: Sendable {
    var bases: [String]
    var token: String
    var session: URLSession = .shared
    var timeout: TimeInterval = 2.5

    static func live() -> ProxyIPCountryClient {
        let bases = ["MasoAIProxyURL", "MasoAIProxyFallbackURL"].compactMap {
            Bundle.main.object(forInfoDictionaryKey: $0) as? String
        }
        let token = Bundle.main.object(forInfoDictionaryKey: "MasoClientToken") as? String ?? ""
        return ProxyIPCountryClient(bases: bases, token: token)
    }

    func countryCode() async throws -> String? {
        let usable = bases.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !usable.isEmpty, !token.isEmpty else { throw WeightUnitLookupError.notConfigured }
        var last = WeightUnitLookupError.unavailable
        for base in usable {
            do { return try await fetch(base) }
            catch let error as WeightUnitLookupError { last = error }
            catch { last = .unavailable }
        }
        throw last
    }

    private func fetch(_ base: String) async throws -> String? {
        let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
        guard let url = URL(string: trimmed + "/region") else {
            throw WeightUnitLookupError.notConfigured
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue(token, forHTTPHeaderField: "X-Maso-Client-Token")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WeightUnitLookupError.unavailable
        }
        struct Body: Decodable { let country: String? }
        return try JSONDecoder().decode(Body.self, from: data).country
    }
}

extension DataStore {
    func selectWeightUnit(_ unit: WeightUnit) {
        let chosen = WeightUnitDefaulting.userSelected(unit)
        settings.weightUnit = chosen.unit
        settings.weightUnitOrigin = chosen.origin.rawValue
        save()
    }

    /// Asks the existing proxy once while the first-run marker is still pending.
    /// A manual choice made while the request is in flight is left untouched.
    func resolveWeightUnitFromIPIfNeeded(lookup: @Sendable () async throws -> String? = {
        try await ProxyIPCountryClient.live().countryCode()
    }) async {
        let current = WeightUnitDefaulting.state(unit: settings.weightUnit, storedOrigin: settings.weightUnitOrigin)
        guard WeightUnitDefaulting.shouldRequestIP(current) else { return }
        let resolved: WeightUnitDefaultState
        do { resolved = WeightUnitDefaulting.applyIP(country: try await lookup(), to: current) }
        catch { resolved = WeightUnitDefaulting.applyFailure(to: current) }
        let latest = WeightUnitDefaulting.state(unit: settings.weightUnit, storedOrigin: settings.weightUnitOrigin)
        guard latest.origin == .pending else { return }
        settings.weightUnit = resolved.unit
        settings.weightUnitOrigin = resolved.origin.rawValue
        save()
    }
}
