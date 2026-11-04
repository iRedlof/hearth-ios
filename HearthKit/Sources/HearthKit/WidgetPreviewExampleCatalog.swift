import Foundation

/// Stable descriptions of admitted illustrative inputs. No store or provider authority.
public struct WidgetPreviewExample: Identifiable, Hashable, Sendable {
    public let kind: WidgetPreviewKind
    public let id: String
    public let title: String
    public let group: String
    public init(kind: WidgetPreviewKind, id: String, title: String, group: String) {
        self.kind = kind; self.id = id; self.title = title; self.group = group
    }
}

public func widgetPreviewExamples(for kind: WidgetPreviewKind) -> [WidgetPreviewExample] {
    let rows: [(String, String, String)]
    switch kind {
    case .alarm:
        rows = [
            ("disarmed", "Disarmed", "Alarm status"),
            ("armed_home", "Armed home", "Alarm status"),
            ("armed_away", "Armed away", "Alarm status"),
            ("armed_night", "Armed night", "Alarm status"),
            ("armed_vacation", "Armed vacation", "Alarm status"),
            ("armed_custom_bypass", "Armed bypass", "Alarm status"),
            ("arming", "Arming", "Alarm status"),
            ("disarming", "Disarming", "Alarm status"),
            ("pending", "Entry delay", "Alarm status"),
            ("triggered", "Alarm triggered", "Alarm status"),
            ("panel_unavailable", "Alarm unavailable", "Alarm status"),
            ("panel_unknown", "Alarm state unknown", "Alarm status"),
            ("door_unlocked", "Door unlocked", "Door status"),
            ("door_open", "Door open", "Door status"),
            ("door_jammed", "Door jammed", "Door status"),
            ("door_locking", "Door locking", "Door status"),
            ("door_unlocking", "Door unlocking", "Door status"),
            ("door_opening", "Door opening", "Door status"),
            ("door_unknown", "Door state unknown", "Door status"),
            ("door_unavailable", "Door unavailable", "Door status"),
            ("no_door", "No companion door", "Door status"),
            ("setup", "Connect your alarm", "Connection and readings"),
            ("first_failure", "First check failed", "Connection and readings"),
            ("offline", "Checks failed · last readings", "Connection and readings"),
            ("panel_failed", "Alarm check failed · last reading", "Connection and readings"),
            ("historical_triggered", "Last alarm reading · triggered", "Connection and readings"),
            ("door_failed", "Door check failed · last reading", "Connection and readings"),
            ("door_first_failure", "Door check failed · no reading", "Connection and readings"),
            ("auth_failed", "Sign in required", "Connection and readings"),
            ("door_bad_entity", "Door not found", "Connection and readings"),
            ("old_cache", "Older saved readings", "Connection and readings"),
            ("home_only", "Home arming only", "Available actions"),
            ("away_only", "Away arming only", "Available actions"),
            ("no_arm_modes", "Arm modes unavailable", "Available actions"),
            ("code_required", "Arming requires a code", "Available actions"),
            ("pending_arm", "Arm request pending", "Updates"),
            ("failed_arm", "Arm request failed", "Updates"),
            ("pending_door", "Door request pending", "Updates"),
            ("failed_door", "Door request failed", "Updates"),
            ("triggered_pending_door", "Alarm triggered · door request pending", "Updates"),
            ("interrupted", "Update interrupted", "Updates"),
            ("long_names", "Long alarm and door names", "Long names")
        ]
    case .thermostat:
        rows = [
            ("auto", "Auto · holding", "Mode and activity"),
            ("heating", "Heat · heating", "Mode and activity"),
            ("cooling", "Cool · cooling", "Mode and activity"),
            ("heat_idle", "Heat · holding", "Mode and activity"),
            ("cool_idle", "Cool · holding", "Mode and activity"),
            ("auto_heating", "Auto · heating", "Mode and activity"),
            ("auto_cooling", "Auto · cooling", "Mode and activity"),
            ("fan", "Auto · fan setting", "Mode and activity"),
            ("off", "Off", "Mode and activity"),
            ("fan_only", "Fan only", "Mode and activity"),
            ("dry", "Dry", "Mode and activity"),
            ("unavailable", "Thermostat unavailable", "Mode and activity"),
            ("unknown_room", "Room temperature unknown", "Temperatures and sensors"),
            ("unknown_targets", "Targets unknown", "Temperatures and sensors"),
            ("one_target", "One target available", "Temperatures and sensors"),
            ("unknown_unit", "Temperature unit unknown", "Temperatures and sensors"),
            ("celsius", "Celsius", "Temperatures and sensors"),
            ("heat_min", "Heat target at minimum", "Temperatures and sensors"),
            ("heat_max", "Heat target at maximum", "Temperatures and sensors"),
            ("cool_min", "Cool target at minimum", "Temperatures and sensors"),
            ("cool_max", "Cool target at maximum", "Temperatures and sensors"),
            ("range_min", "Auto range at minimum", "Temperatures and sensors"),
            ("range_max", "Auto range at maximum", "Temperatures and sensors"),
            ("no_context", "No extra sensors", "Temperatures and sensors"),
            ("context_failed", "Outside sensor check failed", "Temperatures and sensors"),
            ("sensor_failed", "Bedroom sensor check failed", "Temperatures and sensors"),
            ("no_controls", "Controls unavailable", "Available actions"),
            ("no_fan_mode", "Fan mode unavailable", "Available actions"),
            ("unavailable_no_fan_mode", "Thermostat and fan mode unavailable", "Available actions"),
            ("pending_target", "Target request pending", "Updates"),
            ("failed_target", "Target request failed", "Updates"),
            ("pending_mode", "Mode request pending", "Updates"),
            ("pending_fan", "Fan request pending", "Updates"),
            ("pending_resume", "Resume request pending", "Updates"),
            ("pending_no_fan_mode", "Target request pending · fan mode unavailable", "Updates"),
            ("setup", "Connect your thermostat", "Connection and readings"),
            ("first_failure", "First check failed", "Connection and readings"),
            ("no_saved_reading", "No saved reading", "Connection and readings"),
            ("offline", "Check failed · last reading", "Connection and readings"),
            ("auth_failed", "Sign in required", "Connection and readings"),
            ("bad_entity", "Thermostat not found", "Connection and readings"),
            ("shared_store_failed", "Shared readings unavailable", "Connection and readings"),
            ("save_failed", "Reading could not be saved", "Connection and readings"),
            ("selection_changed", "Thermostat selection changed", "Connection and readings"),
            ("auth_retained", "Sign in required · saved reading", "Connection and readings"),
            ("long_names", "Long thermostat name", "Long names")
        ]
    case .car:
        rows = [
            ("parked", "Parked at home", "Vehicle and charging"),
            ("charging", "Charging", "Vehicle and charging"),
            ("complete", "Charging complete", "Vehicle and charging"),
            ("low_battery", "Low battery", "Vehicle and charging"),
            ("battery_100", "Full battery", "Vehicle and charging"),
            ("limit_90", "Charge limit 90%", "Vehicle and charging"),
            ("no_limit", "Charge limit unknown", "Vehicle and charging"),
            ("sentry", "Sentry on", "Security and openings"),
            ("unlocked_away", "Unlocked away", "Security and openings"),
            ("open", "Trunk open", "Security and openings"),
            ("windows_open", "Windows open", "Security and openings"),
            ("port_open", "Charge port open", "Security and openings"),
            ("mixed_open", "Multiple openings", "Security and openings"),
            ("partial_open", "Opening partly unknown", "Security and openings"),
            ("unknown_security", "Security readings unknown", "Security and openings"),
            ("tires", "Check tyre pressure", "Security and openings"),
            ("setup", "Connect your car", "Connection and readings"),
            ("no_car", "Car not found", "Connection and readings"),
            ("no_reading", "No car reading", "Connection and readings"),
            ("first_failure", "First check failed", "Connection and readings"),
            ("offline", "Check failed · last reading", "Connection and readings"),
            ("stale_sentry", "Check failed · last Sentry reading", "Connection and readings"),
            ("old_reading", "Last known reading", "Connection and readings"),
            ("historical_open", "Last known openings", "Connection and readings"),
            ("auth_failed", "Sign in required", "Connection and readings"),
            ("auth_history", "Sign in required · saved reading", "Connection and readings"),
            ("save_failed", "Reading could not be saved", "Connection and readings"),
            ("save_failed_open", "Openings reading could not be saved", "Connection and readings"),
            ("long_names", "Long car name", "Long names")
        ]
    case .lights:
        rows = [
            ("sample", "Mixed lights · pinned Porch", "Examples"),
            ("ready", "All sample lights on", "Readings"),
            ("all_off", "All lights off · pinned Porch", "Readings"),
            ("setup", "Connect your lights", "Connection"),
            ("loading", "Checking lights", "Connection"),
            ("empty", "No lights found", "Readings"),
            ("unavailable", "Lights unavailable", "Connection"),
            ("failed", "Could not load lights", "Connection"),
            ("overflow", "Many lights", "More items"),
            ("long_names", "Long light names", "Long names"),
            ("pinned_overflow", "Many lights · pinned lights", "Pinned lights"),
            ("pins_only", "Only pinned lights", "Pinned lights"),
            ("one_pin", "One pinned light", "Pinned lights")
        ]
    case .favourites:
        rows = [
            ("sample", "Mixed favourites · script", "Examples"),
            ("ready", "Mixed switch favourites", "Readings"),
            ("setup", "Connect your favourites", "Connection"),
            ("loading", "Checking favourites", "Connection"),
            ("empty", "Choose favourites", "Readings"),
            ("unavailable", "One favourite unavailable", "Connection"),
            ("failed", "Could not load favourites", "Connection"),
            ("overflow", "Many favourites", "More items"),
            ("long_names", "Long favourite names", "Long names"),
            ("overflow_error", "Many favourites · one unavailable", "More items")
        ]
    case .quick:
        rows = [
            ("sample", "Actions ready", "Examples"),
            ("ready", "Four sample actions", "Readings"),
            ("setup", "Connect your actions", "Connection"),
            ("loading", "Checking actions", "Connection"),
            ("empty", "Choose actions", "Readings"),
            ("unavailable", "Some actions unavailable", "Connection"),
            ("failed", "Could not load actions", "Connection"),
            ("overflow", "Many actions", "More items"),
            ("long_names", "Long action names", "Long names"),
            ("overflow_error", "Many actions · one unavailable", "More items")
        ]
    case .activity:
        rows = [
            ("sample", "Recent activity", "Examples"),
            ("ready", "Five settled events", "Readings"),
            ("setup", "Connect your activity", "Connection"),
            ("loading", "Checking activity", "Connection"),
            ("empty", "No settled events", "Readings"),
            ("failed", "Check failed · last events", "Connection"),
            ("partial_failure", "Some events unreadable · last events", "Connection"),
            ("overflow", "Many events", "More items"),
            ("long_names", "Long event names", "Long names"),
            ("history", "Older events", "Readings"),
            ("boundary", "Events at the time-window boundary", "Readings"),
            ("legacy_bypass", "Armed bypass event", "Readings")
        ]
    case .doors:
        rows = [
            ("sample", "Garage open", "Examples"),
            ("ready", "Doors shut", "Readings"),
            ("setup", "Connect your doors", "Connection"),
            ("loading", "Checking doors", "Connection"),
            ("empty", "No doors selected", "Readings"),
            ("unavailable", "Door readings unavailable", "Connection"),
            ("failed", "Checks failed · last door readings", "Connection"),
            ("partial_failure", "One door check failed", "Connection"),
            ("overflow", "Many doors", "More items"),
            ("long_names", "Long door names", "Long names"),
            ("history", "Older door readings", "Readings"),
            ("moving", "Garage and gate moving", "Readings"),
            ("failed_history", "Checks failed · last movement", "Readings"),
            ("opening_pending", "Open request pending", "Updates"),
            ("opening_pending_unavailable", "Open request pending · reading unavailable", "Updates"),
            ("stop_pending", "Stop request pending", "Updates"),
            ("lock_pending", "Lock request pending", "Updates"),
            ("command_failed", "Door request failed", "Updates")
        ]
    case .battery:
        rows = [
            ("sample", "Battery levels", "Examples"),
            ("ready", "Four battery levels", "Readings"),
            ("setup", "Connect your batteries", "Connection"),
            ("loading", "Checking batteries", "Connection"),
            ("empty", "No batteries found", "Readings"),
            ("unavailable", "Battery readings unavailable", "Connection"),
            ("failed", "Check failed · last levels", "Connection"),
            ("partial_failure", "Some levels unreadable · last levels", "Connection"),
            ("overflow", "Many batteries", "More items"),
            ("long_names", "Long battery names", "Long names"),
            ("history", "Older battery readings", "Readings"),
            ("binary_low", "Binary Low and OK", "Readings"),
            ("invalid_numeric", "Battery values unknown", "Readings")
        ]
    case .chargepoint:
        rows = [
            ("heldSnoozeAvailable", "Spot held · snooze available", "Examples"),
            ("heldNoSnoozes", "Spot held · no snoozes left", "Examples"),
            ("sessionExpiredSignInRequired", "Session expired · sign in required", "Examples"),
            ("available", "Plugs available", "Availability and setup"),
            ("signed_out", "Signed out", "Availability and setup"),
            ("no_location", "Choose a location", "Availability and setup"),
            ("waiting", "In line · Auto off", "Queue"),
            ("auto_waiting", "In line · Auto on", "Queue"),
            ("pending", "Waitlist opens later", "Queue"),
            ("offer", "Offer ready · snooze available", "Offers and holds"),
            ("offer_last", "Offer ready · no snoozes left", "Offers and holds"),
            ("held", "Spot held · Auto off", "Offers and holds"),
            ("held_unknown", "Spot held · allowance unknown", "Offers and holds"),
            ("dib_held", "Spot held again", "Offers and holds"),
            ("offer_no_floor", "Offer ready · charger name", "Offers and holds"),
            ("unknown_deadline", "Offer deadline unknown", "Offers and holds"),
            ("snoozed", "Snoozed · Auto off", "Snoozed"),
            ("auto_snoozed", "Snoozed · Auto on", "Snoozed"),
            ("charging", "Charging · Stop available", "Charging"),
            ("charging_no_stop", "Charging · open app", "Charging"),
            ("done", "Charging complete", "Charging"),
            ("fault", "Charging stopped", "Charging"),
            ("unplugged", "Unplugged", "Charging"),
            ("overstayed", "Move your car", "Charging"),
            ("blocked", "Charger blocked", "Charging")
        ]
    }
    return rows.map { WidgetPreviewExample(kind: kind, id: $0.0, title: $0.1, group: $0.2) }
}

/// Value-owned choices survive kind/family/reference round trips for this visit only.
public struct WidgetPreviewExampleSelection: Sendable {
    private var ids: [WidgetPreviewKind: String] = [:]
    public init() {}
    public func selected(for kind: WidgetPreviewKind) -> WidgetPreviewExample {
        let examples = widgetPreviewExamples(for: kind)
        return examples.first { $0.id == ids[kind] } ?? examples[0]
    }
    @discardableResult public mutating func select(id: String, for kind: WidgetPreviewKind) -> Bool {
        guard widgetPreviewExamples(for: kind).contains(where: { $0.id == id }) else { return false }
        ids[kind] = id
        return true
    }
    @discardableResult public mutating func select(_ example: WidgetPreviewExample, for kind: WidgetPreviewKind) -> Bool {
        guard example.kind == kind else { return false }
        return select(id: example.id, for: kind)
    }
}

/// One successful fictional reading; normal gallery dispatch consumes the live parser and mapper.
public func lightsAllOffWidgetPreviewSnapshot(now: Date) -> LightsSnapshot {
    let rows: [[String: Any]] = ["Kitchen", "Living room", "Desk lamp", "Porch"].enumerated().map {
        ["entity_id": "light.fixture_\($0.offset + 1)", "name": $0.element, "state": "off", "group": false]
    }
    let reply = String(data: try! JSONSerialization.data(withJSONObject: rows), encoding: .utf8)!
    let config = HaConfig(baseUrl: "https://example.com", token: "inert", entityId: "",
                          lightPinsJson: "[\"light.fixture_4\"]")
    return mapLightsSnapshot(config, reply: .success(reply), now: now)
}
