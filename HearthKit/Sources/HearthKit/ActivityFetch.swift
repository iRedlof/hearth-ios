import Foundation

/// The Activity widget's payload: recent events + when it was read.
public struct ActivitySnapshot: Sendable, Equatable {
    public let items: [ActivityItem]; public let checkedAt: String
    public let state: TileSnapshotState; public let error: String?
    public let observedAt: Date?; public let windowEnd: Date?
    public init(items: [ActivityItem], checkedAt: String, state: TileSnapshotState = .ready,
                error: String? = nil, observedAt: Date? = nil, windowEnd: Date? = nil) {
        self.items = items; self.checkedAt = checkedAt; self.state = state; self.error = error
        self.observedAt = observedAt; self.windowEnd = windowEnd
    }
    public static let loading = ActivitySnapshot(items: [], checkedAt: "", state: .loading)

    public static let sample = ActivitySnapshot(items: [
        ActivityItem(at: Date().addingTimeInterval(-300), kind: .garage, text: "Garage closed", by: "Arriving home routine"),
        ActivityItem(at: Date().addingTimeInterval(-1800), kind: .alarm, text: "Home Alarm disarmed", by: nil),
        ActivityItem(at: Date().addingTimeInterval(-3600), kind: .lock, text: "Front Door unlocked", by: nil),
        ActivityItem(at: Date().addingTimeInterval(-6300), kind: .door, text: "Back Door opened", by: nil),
        ActivityItem(at: Date().addingTimeInterval(-9000), kind: .charge, text: "Tesla plugged in", by: nil),
    ], checkedAt: "9:41 AM")
}

/// Last 24 hours, with the same default door and car selection as Android. Injected reads use the
/// supplied selected names, without discovery or network calls.
public func fetchActivitySnapshot(_ config: HaConfig?, now: Date = Date(),
    read: (@Sendable () async throws -> String)? = nil, names: [String: String] = [:],
    carIds: Set<String> = [], previous: ActivitySnapshot? = nil) async -> ActivitySnapshot {
    guard let config, config.carReady else {
        return mapActivitySnapshot(config: config, reply: .success("[]"), names: names, previous: previous, now: now)
    }
    var selectedNames = activitySelectedNames(config, names: names)
    var selectedCarIds = carIds
    do {
        let log: String
        if let read {
            log = try await read()
        } else {
            let client = HaClient(config)
            var doors = config.doorIds
            if doors.isEmpty && !config.doorsChosen {
                let states = try await client.allStatesJson()
                doors = try defaultDoorIDs(states, lockID: config.lockId)
            }
            for id in doors where selectedNames[id] == nil || selectedNames[id] == activityFallbackName(id, config: config) {
                selectedNames[id] = activityFallbackName(id, config: config)
                if let json = try? await client.stateJson(id), let door = doorFromState(json), door.id == id {
                    selectedNames[id] = door.name
                }
            }
            if let json = try? await client.template(CAR_TEMPLATE),
               let data = json.data(using: .utf8),
               let car = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               car["found"] as? Bool == true, let prefix = car["prefix"] as? String, !prefix.isEmpty {
                let name = (car["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Car"
                for id in ["lock.\(prefix)_lock", "binary_sensor.\(prefix)_charge_cable"] {
                    selectedNames[id] = name; selectedCarIds.insert(id)
                }
            }
            if selectedNames.isEmpty {
                log = "[]"
            } else {
                log = try await client.logbookJson(since: now.addingTimeInterval(-24 * 3600), ids: selectedNames.keys.sorted())
            }
        }
        // HA names are useful only for the IDs explicitly included in the request.
        selectedNames = activityNamesFromLogbook(log, selected: selectedNames)
        return mapActivitySnapshot(config: config, reply: .success(log), names: selectedNames,
                                   carIds: selectedCarIds, previous: previous, now: now)
    } catch {
        return mapActivitySnapshot(config: config, reply: .failure(HaError(tileReadError(error))), names: selectedNames,
                                   carIds: selectedCarIds, previous: previous, now: now)
    }
}

/// `names` is the explicit request selection, including discovered doors/car IDs. Never derive
/// selection from the returned logbook: HA may include rows outside the requested entities.
public func mapActivitySnapshot(config: HaConfig?, reply: Result<String, HaError>, names: [String: String],
    carIds: Set<String> = [], previous: ActivitySnapshot? = nil, now: Date) -> ActivitySnapshot {
    guard let config, config.carReady else { return ActivitySnapshot(items: [], checkedAt: "", state: .setup) }
    let selected = activitySelectedNames(config, names: names)
    do {
        let json = try reply.get()
        guard let data = json.data(using: .utf8),
              (try JSONSerialization.jsonObject(with: data)) is [[String: Any]] else {
            throw HaError("Unexpected activity reading")
        }
        let items = activityFrom(json, names: selected, haStart: nil, carIds: carIds, windowEnd: now)
        return ActivitySnapshot(items: items, checkedAt: widgetClock(now), state: items.isEmpty ? .empty : .ready,
                                observedAt: now, windowEnd: now)
    } catch {
        return ActivitySnapshot(items: activityInWindow(previous?.items ?? [], now: now), checkedAt: previous?.checkedAt ?? "",
                                state: .failed, error: tileReadError(error), observedAt: previous?.observedAt,
                                windowEnd: previous?.windowEnd)
    }
}

private func activityFallbackName(_ id: String, config: HaConfig) -> String {
    if id == config.entityId { return "Alarm" }
    if id == config.lockId { return config.lockName.isEmpty ? "Front door" : config.lockName }
    return id.split(separator: ".").last.map { $0.replacingOccurrences(of: "_", with: " ").capitalized } ?? id
}

private func activitySelectedNames(_ config: HaConfig, names: [String: String]) -> [String: String] {
    var selected = names
    for (id, name) in names where name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        selected[id] = activityFallbackName(id, config: config)
    }
    for id in ([config.entityId, config.lockId] + config.doorIds) where !id.isEmpty {
        if selected[id]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            selected[id] = activityFallbackName(id, config: config)
        }
    }
    return selected.mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
}

private func activityNamesFromLogbook(_ json: String, selected: [String: String]) -> [String: String] {
    guard let data = json.data(using: .utf8),
          let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return selected }
    var names = selected
    for e in arr {
        if let id = e["entity_id"] as? String, selected[id] != nil,
           let name = e["name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            names[id] = name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    return names
}
