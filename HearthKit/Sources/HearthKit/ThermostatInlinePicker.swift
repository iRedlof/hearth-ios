import Foundation

/// How long an opened Mode/Fan row stays on the widget before it collapses by itself.
public let thermostatInlinePickerLifetime: TimeInterval = 20

private let thermostatInlineKinds = ["mode", "fan"]

/// The Mode/Fan choices one widget tap opened, bound to the card, account and command revision that offered them.
public struct ThermostatInlinePicker: Codable, Equatable, Sendable {
    public let kind: String
    public let options: [String]
    public let current: String?
    public let entityID: String
    public let scope: String
    public let revision: String
    public let selectionRevision: String
    public let expectedMode: String
    public let openedAt: Date

    public init(kind: String, options: [String], current: String?, entityID: String, scope: String,
                revision: String, selectionRevision: String, expectedMode: String, openedAt: Date) {
        self.kind = kind; self.options = options; self.current = current
        self.entityID = entityID; self.scope = scope; self.revision = revision
        self.selectionRevision = selectionRevision; self.expectedMode = expectedMode; self.openedAt = openedAt
    }

    public var expiresAt: Date { openedAt.addingTimeInterval(thermostatInlinePickerLifetime) }
}

public struct ThermostatInlineOption: Equatable, Identifiable, Sendable {
    public let value: String
    public let label: String
    public let isCurrent: Bool
    public var id: String { value }
}

/// What the chip row draws while a record is open on this exact card.
public struct ThermostatInlineChoices: Equatable, Sendable {
    public let kind: String
    public let options: [ThermostatInlineOption]
    public let expiresAt: Date
}

public enum ThermostatInlineSelection: Equatable, Sendable {
    /// The option already in effect: the row closes and no command is formed.
    case close
    case apply(String)
}

/// A record exists only when the live thermostat offers something other than its current setting.
public func thermostatInlinePicker(state: ClimateState, kind: String, entityID: String, scope: String,
                                   revision: String, selectionRevision: String, expectedMode: String,
                                   now: Date) -> ThermostatInlinePicker? {
    guard thermostatInlineKinds.contains(kind),
          ![entityID, scope, revision, selectionRevision].contains(where: \.isEmpty) else { return nil }
    let options = climateOptions(state, kind: kind)
    let current = kind == "fan" ? state.fanMode : state.mode
    guard options.contains(where: { $0 != current }) else { return nil }
    return ThermostatInlinePicker(kind: kind, options: options, current: current, entityID: entityID,
        scope: scope, revision: revision, selectionRevision: selectionRevision, expectedMode: expectedMode,
        openedAt: now)
}

/// Nil unless the record belongs to the entry being drawn and is younger than its lifetime.
public func thermostatInlineChoices(record: ThermostatInlinePicker?, now: Date, entityID: String, scope: String,
                                    revision: String, selectionRevision: String) -> ThermostatInlineChoices? {
    guard let record, thermostatInlineKinds.contains(record.kind),
          ![entityID, scope, revision, selectionRevision].contains(where: \.isEmpty),
          record.entityID == entityID, record.scope == scope, record.revision == revision,
          record.selectionRevision == selectionRevision else { return nil }
    let age = now.timeIntervalSince(record.openedAt)
    guard age.isFinite, age >= 0, age < thermostatInlinePickerLifetime else { return nil }
    var seen = Set<String>()
    let values = record.options.filter { !$0.isEmpty && seen.insert($0).inserted }
    guard values.contains(where: { $0 != record.current }) else { return nil }
    return ThermostatInlineChoices(kind: record.kind, options: values.map {
        ThermostatInlineOption(value: $0, label: thermostatInlineOptionLabel(kind: record.kind, option: $0),
                               isCurrent: $0 == record.current)
    }, expiresAt: record.expiresAt)
}

/// The card decides: a stale, pending or uncontrollable thermostat never shows an opened row.
public func thermostatInlineChoices(record: ThermostatInlinePicker?, now: Date,
                                    snapshot: ThermostatSnapshot) -> ThermostatInlineChoices? {
    guard let record, record.kind == "fan" ? snapshot.canPickFan : snapshot.canPickMode else { return nil }
    return thermostatInlineChoices(record: record, now: now, entityID: snapshot.entityID,
        scope: snapshot.requestScope, revision: snapshot.climateRevision,
        selectionRevision: snapshot.evidence?.origin?.selectionRevision ?? "")
}

/// Nil when the tapped chip is not one this record is still offering to this card.
public func thermostatInlineSelection(record: ThermostatInlinePicker?, now: Date, kind: String, option: String,
                                      entityID: String, scope: String, revision: String,
                                      selectionRevision: String) -> ThermostatInlineSelection? {
    guard let choices = thermostatInlineChoices(record: record, now: now, entityID: entityID, scope: scope,
              revision: revision, selectionRevision: selectionRevision),
          choices.kind == kind, let chosen = choices.options.first(where: { $0.value == option }) else { return nil }
    return chosen.isCurrent ? .close : .apply(chosen.value)
}

/// The account, thermostat and reading selection that opened the row must still be the current ones.
public func thermostatInlinePickerOwned(_ record: ThermostatInlinePicker, by context: HaStoreSnapshot?) -> Bool {
    guard let context, let origin = ThermostatSelectionOrigin(context) else { return false }
    return origin.scope == record.scope && origin.entityID == record.entityID
        && origin.selectionRevision == record.selectionRevision
}

/// The same names the Mode and Fan chips already use.
public func thermostatInlineOptionLabel(kind: String, option: String) -> String {
    kind == "fan" ? option.capitalizedFirst : climateModeDisplay(option)
}

public func thermostatInlineAccessibilityLabel(kind: String, option: ThermostatInlineOption) -> String {
    let control = kind == "fan" ? "fan" : "mode"
    return option.isCurrent ? "\(control.capitalizedFirst) \(option.label), current. Close"
        : "Set \(control) to \(option.label)"
}
