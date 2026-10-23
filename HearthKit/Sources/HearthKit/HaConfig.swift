import Foundation

public let CONFIRM_BIOMETRIC = "biometric"
public let CONFIRM_DIALOG = "dialog"

/// Persisted Home Assistant settings. Ported from Android `HaConfig.kt`. On iOS this is stored in the
/// Keychain / an App-Group-shared store so the widget extension can read it.
public struct HaConfig: Sendable, Equatable {
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

    public init(baseUrl: String, token: String, entityId: String, refreshToken: String = "",
                lockId: String = "", lockName: String = "", confirmWith: String = CONFIRM_BIOMETRIC,
                climateId: String = "", comfortId: String = "", resumeId: String = "",
                sensorsJson: String = "[]", doorIdsJson: String = "[]", scriptIdsJson: String = "[]",
                lightPinsJson: String = "[]", favouriteIdsJson: String = "[]") {
        self.baseUrl = baseUrl; self.token = token; self.entityId = entityId; self.refreshToken = refreshToken
        self.lockId = lockId; self.lockName = lockName; self.confirmWith = confirmWith
        self.climateId = climateId; self.comfortId = comfortId; self.resumeId = resumeId
        self.sensorsJson = sensorsJson; self.doorIdsJson = doorIdsJson; self.scriptIdsJson = scriptIdsJson
        self.lightPinsJson = lightPinsJson; self.favouriteIdsJson = favouriteIdsJson
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
    public var lightPins: Set<String> { Set(Self.parseArray(lightPinsJson)) }

    private static func parseArray(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [String] else { return [] }
        return arr
    }
}
