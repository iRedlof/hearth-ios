import Testing
@testable import HearthKit

@Suite("hearthVersionString formatting")
struct VersionStringTests {

    @Test("normal case: short + build")
    func normalCaseShortAndBuild() {
        let result = hearthVersionString(short: "0.1.0", build: "9")
        #expect(result == "0.1.0 (9)")
    }

    @Test("empty short: returns just build")
    func emptyShortReturnsJustBuild() {
        let result = hearthVersionString(short: "", build: "42")
        #expect(result == "42")
    }
}
