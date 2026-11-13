import XCTest
@testable import Maso

@MainActor
final class WeightUnitDefaultTests: XCTestCase {
    func testChinaUsesKilogramsAndUnitedStatesUsesPounds() {
        XCTAssertEqual(GymWeightConvention.unitIfRecognized("CN"), .kg)
        XCTAssertEqual(GymWeightConvention.unitIfRecognized("cn"), .kg)
        XCTAssertEqual(GymWeightConvention.unitIfRecognized("US"), .lb)
        XCTAssertEqual(GymWeightConvention.unitIfRecognized("us"), .lb)
    }

    func testNonEnglishMetricCountriesAndEnglishMetricGymsStayKilograms() {
        for code in ["DE", "FR", "JP", "KR", "BR", "RU", "GB", "CA", "AU", "IE", "NZ"] {
            XCTAssertEqual(GymWeightConvention.unitIfRecognized(code), .kg, code)
        }
    }

    func testUnknownAlpha3AndTorCodesAreNotACountry() {
        XCTAssertNil(GymWeightConvention.unitIfRecognized("USA"))
        XCTAssertNil(GymWeightConvention.unitIfRecognized("XX"))
        XCTAssertNil(GymWeightConvention.unitIfRecognized("T1"))
        XCTAssertNil(GymWeightConvention.unitIfRecognized(nil))
        XCTAssertNil(GymWeightConvention.unitIfRecognized(" "))
    }

    func testNewUserKeepsDeviceUnitUntilIPAndDoesNotRewriteStoredKilograms() {
        let provisional = WeightUnitDefaulting.provisional(deviceCountry: "DE")
        XCTAssertEqual(provisional.unit, .kg)
        XCTAssertEqual(provisional.origin, .pending)
        let storedKilograms = 100.0
        let resolved = WeightUnitDefaulting.applyIP(country: "US", to: provisional)
        XCTAssertEqual(resolved.unit, .lb)
        XCTAssertEqual(resolved.origin, .ip)
        XCTAssertEqual(storedKilograms, 100)
        XCTAssertEqual(resolved.unit.toKg(resolved.unit.fromKg(storedKilograms)), storedKilograms, accuracy: 0.001)
    }

    func testUnitedKingdomDeviceFallbackStaysKilogramsWhenIPFails() {
        let provisional = WeightUnitDefaulting.provisional(deviceCountry: "GB")
        let failed = WeightUnitDefaulting.applyFailure(to: provisional)
        XCTAssertEqual(failed.unit, .kg)
        XCTAssertEqual(failed.origin, .device)
        XCTAssertFalse(WeightUnitDefaulting.shouldRequestIP(failed))
    }

    func testUnknownIPCountryLocksTheDeviceProvisional() {
        let provisional = WeightUnitDefaulting.provisional(deviceCountry: "US")
        let resolved = WeightUnitDefaulting.applyIP(country: "USA", to: provisional)
        XCTAssertEqual(resolved.unit, .lb)
        XCTAssertEqual(resolved.origin, .device)
    }

    func testLegacyProfileKeepsItsUnitAndDoesNotRequestAgain() throws {
        var settings = UserSettings()
        settings.weightUnit = .lb
        settings.weightUnitOrigin = nil
        let encoded = try JSONEncoder().encode(settings)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "weightUnitOrigin")
        let decoded = try JSONDecoder().decode(UserSettings.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.weightUnit, .lb)
        XCTAssertNil(decoded.weightUnitOrigin)
        let legacy = WeightUnitDefaulting.state(unit: decoded.weightUnit, storedOrigin: decoded.weightUnitOrigin)
        XCTAssertFalse(WeightUnitDefaulting.shouldRequestIP(legacy))
        let ignored = WeightUnitDefaulting.applyIP(country: "CN", to: legacy)
        XCTAssertEqual(ignored.unit, .lb)
        XCTAssertEqual(ignored.origin, .manual)
    }

    func testManualChoiceWinsOverALateIPResultAndASecondLaunchDoesNotAskAgain() async {
        let data = DataStore(exercises: [], plans: [], sets: [], settings: pending("CN"))
        let gate = CountryGate()
        let task = Task { await data.resolveWeightUnitFromIPIfNeeded { await gate.wait() } }
        await gate.untilWaiting()
        data.selectWeightUnit(.lb)
        await gate.finish("CN")
        await task.value
        XCTAssertEqual(data.settings.weightUnit, .lb)
        XCTAssertEqual(data.settings.weightUnitOrigin, "manual")

        let counter = CallCounter()
        await data.resolveWeightUnitFromIPIfNeeded {
            counter.increment()
            return "US"
        }
        XCTAssertEqual(counter.value, 0)
        XCTAssertEqual(data.settings.weightUnit, .lb)
    }

    func testIPSuccessThenAnotherCountryDoesNotSwitch() async {
        let data = DataStore(exercises: [], plans: [], sets: [], settings: pending("DE"))
        await data.resolveWeightUnitFromIPIfNeeded { "US" }
        XCTAssertEqual(data.settings.weightUnit, .lb)
        XCTAssertEqual(data.settings.weightUnitOrigin, "ip")
        await data.resolveWeightUnitFromIPIfNeeded { "CN" }
        XCTAssertEqual(data.settings.weightUnit, .lb)
        XCTAssertEqual(data.settings.weightUnitOrigin, "ip")
    }

    func testNetworkFailureLocksDeviceUnitWithoutAnotherLaunch() async {
        let data = DataStore(exercises: [], plans: [], sets: [], settings: pending("JP"))
        await data.resolveWeightUnitFromIPIfNeeded { throw URLError(.timedOut) }
        XCTAssertEqual(data.settings.weightUnit, .kg)
        XCTAssertEqual(data.settings.weightUnitOrigin, "device")
        let counter = CallCounter()
        await data.resolveWeightUnitFromIPIfNeeded { counter.increment(); return "US" }
        XCTAssertEqual(counter.value, 0)
        XCTAssertEqual(data.settings.weightUnit, .kg)
    }

    func testFreshInstallUsesDeviceCountryWithoutWaitingAndWithoutUsingLanguage() {
        let china = DataStore.freshInstall(deviceCountry: "CN")
        XCTAssertEqual(china.settings.weightUnit, .kg)
        XCTAssertEqual(china.settings.weightUnitOrigin, "pending")
        XCTAssertFalse(china.settings.onboardingCompleted)
        let unitedStates = DataStore.freshInstall(deviceCountry: "US")
        XCTAssertEqual(unitedStates.settings.weightUnit, .lb)
        XCTAssertEqual(unitedStates.settings.weightUnitOrigin, "pending")
        let britain = DataStore.freshInstall(deviceCountry: "GB")
        XCTAssertEqual(britain.settings.weightUnit, .kg)
    }

    func testProxyReadsOnlyCountryFromTheExistingRegionRoute() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RegionHTTPStub.self]
        RegionHTTPStub.handler = { request in
            XCTAssertEqual(request.url?.path, "/region")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Maso-Client-Token"), "token")
            XCTAssertNil(request.httpBody)
            let body = Data(#"{"country":"CN"}"#.utf8)
            return (200, body)
        }
        let client = ProxyIPCountryClient(bases: ["https://proxy.test"], token: "token",
                                           session: URLSession(configuration: configuration))
        let country = try await client.countryCode()
        XCTAssertEqual(country, "CN")
    }

    func testProxyFailureAndMissingConfigurationDoNotInventACountry() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RegionHTTPStub.self]
        RegionHTTPStub.handler = { _ in (404, Data("nope".utf8)) }
        let client = ProxyIPCountryClient(bases: ["https://proxy.test"], token: "token",
                                           session: URLSession(configuration: configuration))
        do {
            _ = try await client.countryCode()
            XCTFail("A missing route must fail")
        } catch is WeightUnitLookupError {}
        catch { XCTFail("Unexpected \(error)") }
        let unconfigured = ProxyIPCountryClient(bases: [""], token: "", session: URLSession(configuration: configuration))
        do { _ = try await unconfigured.countryCode(); XCTFail("Empty proxy must not be called") }
        catch is WeightUnitLookupError {}
        catch { XCTFail("Unexpected \(error)") }
    }

    private func pending(_ device: String) -> UserSettings {
        var settings = UserSettings()
        let provisional = WeightUnitDefaulting.provisional(deviceCountry: device)
        settings.weightUnit = provisional.unit
        settings.weightUnitOrigin = provisional.origin.rawValue
        return settings
    }
}

private final class CountryGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String?, Never>?
    private var entered: CheckedContinuation<Void, Never>?
    private var value: String?
    private var ready = false
    private var started = false

    func wait() async -> String? {
        lock.lock()
        started = true
        let entered = self.entered
        self.entered = nil
        if ready {
            let value = self.value
            lock.unlock()
            entered?.resume()
            return value
        }
        lock.unlock()
        entered?.resume()
        return await withCheckedContinuation { continuation in
            lock.lock()
            if ready {
                let value = self.value
                lock.unlock()
                continuation.resume(returning: value)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }

    func untilWaiting() async {
        lock.lock()
        if started {
            lock.unlock()
            return
        }
        lock.unlock()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if started {
                lock.unlock()
                continuation.resume()
            } else {
                entered = continuation
                lock.unlock()
            }
        }
    }

    func finish(_ value: String?) {
        lock.lock()
        ready = true
        self.value = value
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: value)
    }
}

private final class CallCounter: @unchecked Sendable {
    private(set) var value = 0
    func increment() { value += 1 }
}

private final class RegionHTTPStub: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, body) = Self.handler?(request) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
