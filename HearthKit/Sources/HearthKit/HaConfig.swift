import Foundation

public let CONFIRM_BIOMETRIC = "biometric"
public let CONFIRM_DIALOG = "dialog"

/// Persisted Home Assistant settings. Ported from Android `HaConfig.kt`. On iOS this is stored in the
/// Keychain / an App-Group-shared store so the widget extension can read it.
public struct HaConfig: Sendable, Equatable, Codable {
    public var baseUrl: String
    public var token: String
    public var entityId: String
    public var refreshToken: String
    public var lockId: String
    public var lockName: String
    public var confirmWith: String
    public var climateId: String
    public var comfortId: String
    public var resumeId: String
    public var sensorsJson: String
    public var doorIdsJson: String
    public var scriptIdsJson: String
    public var lightPinsJson: String
    public var favouriteIdsJson: String
    public var doorsChosen: Bool

    public init(baseUrl: String, token: String, entityId: String, refreshToken: String = "",
                lockId: String = "", lockName: String = "", confirmWith: String = CONFIRM_BIOMETRIC,
                climateId: String = "", comfortId: String = "", resumeId: String = "",
                sensorsJson: String = "[]", doorIdsJson: String = "[]", scriptIdsJson: String = "[]",
                lightPinsJson: String = "[]", favouriteIdsJson: String = "[]", doorsChosen: Bool = false) {
        self.baseUrl = baseUrl; self.token = token; self.entityId = entityId; self.refreshToken = refreshToken
        self.lockId = lockId; self.lockName = lockName; self.confirmWith = confirmWith
        self.climateId = climateId; self.comfortId = comfortId; self.resumeId = resumeId
        self.sensorsJson = sensorsJson; self.doorIdsJson = doorIdsJson; self.scriptIdsJson = scriptIdsJson
        self.lightPinsJson = lightPinsJson; self.favouriteIdsJson = favouriteIdsJson
        self.doorsChosen = doorsChosen
    }

    private enum CodingKeys: String, CodingKey {
        case baseUrl, token, entityId, refreshToken, lockId, lockName, confirmWith, climateId, comfortId, resumeId
        case sensorsJson, doorIdsJson, scriptIdsJson, lightPinsJson, favouriteIdsJson, doorsChosen
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(baseUrl: try values.decode(String.self, forKey: .baseUrl),
            token: try values.decode(String.self, forKey: .token),
            entityId: try values.decode(String.self, forKey: .entityId),
            refreshToken: try values.decodeIfPresent(String.self, forKey: .refreshToken) ?? "",
            lockId: try values.decodeIfPresent(String.self, forKey: .lockId) ?? "",
            lockName: try values.decodeIfPresent(String.self, forKey: .lockName) ?? "",
            confirmWith: try values.decodeIfPresent(String.self, forKey: .confirmWith) ?? CONFIRM_BIOMETRIC,
            climateId: try values.decodeIfPresent(String.self, forKey: .climateId) ?? "",
            comfortId: try values.decodeIfPresent(String.self, forKey: .comfortId) ?? "",
            resumeId: try values.decodeIfPresent(String.self, forKey: .resumeId) ?? "",
            sensorsJson: try values.decodeIfPresent(String.self, forKey: .sensorsJson) ?? "[]",
            doorIdsJson: try values.decodeIfPresent(String.self, forKey: .doorIdsJson) ?? "[]",
            scriptIdsJson: try values.decodeIfPresent(String.self, forKey: .scriptIdsJson) ?? "[]",
            lightPinsJson: try values.decodeIfPresent(String.self, forKey: .lightPinsJson) ?? "[]",
            favouriteIdsJson: try values.decodeIfPresent(String.self, forKey: .favouriteIdsJson) ?? "[]",
            doorsChosen: try values.decodeIfPresent(Bool.self, forKey: .doorsChosen) ?? false)
    }

    public var isSignedIn: Bool { !refreshToken.isEmpty }
    public var hasAuth: Bool { !token.isEmpty || isSignedIn }
    public var hasLock: Bool { lockId.hasPrefix("lock.") }
    public var hasClimate: Bool { climateId.hasPrefix("climate.") && baseUrl.hasPrefix("https://") && hasAuth }
    public var confirmWithBiometric: Bool { confirmWith != CONFIRM_DIALOG }
    public var isComplete: Bool { baseUrl.hasPrefix("https://") && hasAuth && entityId.hasPrefix("alarm_control_panel.") }

    /// The car refresh only needs a valid https base URL and some auth (the car is auto-discovered).
    public var carReady: Bool { baseUrl.hasPrefix("https://") && hasAuth }

    public var doorIds: [String] { Self.parseArray(doorIdsJson) }
    public var scriptIds: [String] { Self.parseArray(scriptIdsJson) }
    public var favouriteIds: [String] { Self.parseArray(favouriteIdsJson) }
    public var sensorIds: [String] { Self.parseArray(sensorsJson) }
    public var lightPins: Set<String> { Set(Self.parseArray(lightPinsJson)) }

    private static func parseArray(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [String] else { return [] }
        return arr
    }
}

/// Collection generations include their relevant selection, separate from account scope.
public func haCollectionSelectionChanged(_ before: HaConfig?, _ after: HaConfig?) -> Bool {
    !haSameConnection(before, after) || before?.entityId != after?.entityId ||
        before?.lockId != after?.lockId || before?.doorIds != after?.doorIds ||
        before?.doorsChosen != after?.doorsChosen
}

public func preserveSelectionOrder(_ before: [String], selected: Set<String>, available: [String]) -> [String] {
    var seen = Set<String>()
    return (before + available + selected.sorted()).filter { selected.contains($0) && seen.insert($0).inserted }
}

/// The same HA account/server, independent of which widget entities are selected.
/// A long-lived token takes precedence over OAuth, matching HaClient's bearer choice.
public func haSameConnection(_ a: HaConfig?, _ b: HaConfig?) -> Bool {
    guard let a, let b else { return a == nil && b == nil }
    let aCredential = a.token.isEmpty ? "oauth:" + a.refreshToken : "token:" + a.token
    let bCredential = b.token.isEmpty ? "oauth:" + b.refreshToken : "token:" + b.token
    return a.baseUrl.trimmedTrailingSlash == b.baseUrl.trimmedTrailingSlash && aCredential == bCredential
}

/// Readiness for HA entity rows; Settings and ChargePoint remain available independently.
public func haSettingsReady(_ config: HaConfig?) -> Bool {
    config?.carReady == true
}
