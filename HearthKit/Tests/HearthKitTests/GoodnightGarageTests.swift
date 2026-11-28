import Testing
import Foundation
@testable import HearthKit

/// Goodnight closes the garage chosen in the Garage setting as well as the covers in Doors.
@Suite("Goodnight closes the selected garage")
struct GoodnightGarageTests {
    private func haConfig(doors: String = "[]", garage: String? = nil) -> HaConfig {
        HaConfig(baseUrl: "https://ha.local", token: "token", entityId: "alarm_control_panel.home",
                 doorIdsJson: doors, garageId: garage)
    }

    private func covers(doors: String = "[]", garage: String? = nil) -> [String] {
        planGoodnight(config: GoodnightConfig(), haConfig: haConfig(doors: doors, garage: garage),
                      allLights: [], panelSupportsNight: false).covers
    }

    @Test("A garage chosen in the Garage setting is closed with no Doors selection")
    func selectedGarageAlone() {
        #expect(covers(garage: "cover.garage") == ["cover.garage"])
    }

    @Test("The selected garage is closed after the covers in Doors")
    func selectedGarageJoinsDoors() {
        #expect(covers(doors: #"["cover.side_gate","lock.front"]"#, garage: "cover.garage")
            == ["cover.side_gate", "cover.garage"])
    }

    @Test("A garage that is also in Doors is closed once")
    func selectedGarageAlreadyInDoors() {
        #expect(covers(doors: #"["cover.garage","cover.side_gate"]"#, garage: "cover.garage")
            == ["cover.garage", "cover.side_gate"])
    }

    @Test("A cover listed twice in Doors is closed once")
    func repeatedDoorClosedOnce() {
        #expect(covers(doors: #"["cover.garage","cover.garage"]"#) == ["cover.garage"])
    }

    @Test("Garage set to None adds nothing; the covers in Doors still close")
    func garageNone() {
        #expect(covers(doors: #"["cover.side_gate"]"#, garage: "") == ["cover.side_gate"])
        #expect(covers(garage: "") == [])
    }

    @Test("A saved garage that is not a cover is never sent a close")
    func savedGarageNotACover() {
        #expect(covers(garage: "lock.front") == [])
        #expect(covers(garage: "cover.Bad Id") == [])
    }

    @Test("The runtime closes the selected garage and each cover once")
    func runtimeClosesSelectedGarage() async {
        let closed = ClosedCovers()
        let result = await GoodnightRuntime.run(
            config: GoodnightConfig.default,
            haConfig: haConfig(doors: #"["cover.side_gate","cover.garage"]"#, garage: "cover.garage"),
            now: Date(),
            injectedFetchState: { _ in ([], true) },
            injectedCloseCover: { await closed.record($0) },
            injectedTurnOffLights: { _ in },
            injectedLock: { true },
            injectedArm: { _ in true },
            injectedRecord: { _ in }
        )
        #expect(await closed.ids == ["cover.side_gate", "cover.garage"])
        #expect(result.garagesClosed)
    }

    @Test("The runtime closes a garage chosen only in the Garage setting")
    func runtimeClosesGarageOutsideDoors() async {
        let closed = ClosedCovers()
        _ = await GoodnightRuntime.run(
            config: GoodnightConfig.default,
            haConfig: haConfig(garage: "cover.garage"),
            now: Date(),
            injectedFetchState: { _ in ([], true) },
            injectedCloseCover: { await closed.record($0) },
            injectedTurnOffLights: { _ in },
            injectedLock: { true },
            injectedArm: { _ in true },
            injectedRecord: { _ in }
        )
        #expect(await closed.ids == ["cover.garage"])
    }
}

private actor ClosedCovers {
    private(set) var ids: [String] = []
    func record(_ id: String) { ids.append(id) }
}
