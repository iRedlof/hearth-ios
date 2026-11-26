import Foundation
import HearthKit

enum CpLiveSnapshot {
    static func fetch(now nowParam: Date? = nil, advanceAuto: Bool = false) async -> CpSnapshot {
        do {
            // A dashboard display date must never freeze admission/lease time across network awaits.
            let now = nowParam ?? Date()
            let runtime = try CpSessionStore.runtime()
            let snapshot = try await runtime.refresh(runAuto: advanceAuto)

            // Morning-commute auto-join hook
            if CommuteStore.enabled {
                await checkCommute(runtime: runtime, now: now)
            }

            return snapshot
        } catch {
            return CpSessionStore.unavailableSnapshot
        }
    }

    private static func checkCommute(runtime: CpOwnedRuntime, now: Date) async {
        // Fetch HA commute sensors
        let config = HaConfigStore.load()
        guard let result = await fetchCommuteSensors(config, now: now) else { return }

        // Update lastHeard for the detection status row
        CommuteStore.lastHeard = result.lastHeard

        // Get current CP snapshot to extract state
        guard let current = try? runtime.store.snapshot(now: now),
              let origin = current.renderedOrigin else { return }

        // Extract CP state for commuteDecide
        // Canonical charging definition (matches CpSnapshotMapping.swift:19)
        let status: String = {
            guard case let .inLine(_, value, _, _, _) = current.reading?.provider.waitlist else { return "" }
            return value
        }()
        let charging = current.reading?.provider.charging != nil || status == "CHARGING"
        let alreadyArmed = current.run.armed
        let signedOutOrExpired = !current.session.isSignedIn || current.session.expired || current.session.joinExpired

        // Build today in local timezone
        let today = commuteDay(from: now, in: .current)

        // Decide action
        let action = commuteDecide(
            enabled: true,
            chargeNow: result.chargeNow,
            signinNeeded: result.signinNeeded,
            alreadyArmed: alreadyArmed,
            charging: charging,
            signedOutOrExpired: signedOutOrExpired,
            lastArmDay: CommuteStore.lastArmDay,
            lastNotifyDay: CommuteStore.lastNotifyDay,
            today: today
        )

        // Act on the result
        switch action {
        case .armAuto:
            // Trigger auto-join/arm via setAuto (reuses existing Join with Auto path)
            do {
                _ = try await runtime.setAuto(origin: origin, desired: .join)
                CommuteStore.lastArmDay = today  // only stamp when arm actually succeeded
            } catch {
                // leave lastArmDay unset so the next refresh in the window retries
            }
        case .notifySignIn:
            // Nudge user to sign in to ChargePoint
            CpNotify.post(title: "ChargePoint Sign-In", body: "Sign in to ChargePoint to enable auto-join for your commute.", id: "commute-signin")
            CommuteStore.lastNotifyDay = today
        case .none:
            break
        }
    }
}
