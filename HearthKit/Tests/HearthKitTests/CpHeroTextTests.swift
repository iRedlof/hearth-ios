import Testing
@testable import HearthKit

@Suite("CpHeroText Tests")
struct CpHeroTextTests {

    @Test("No place returns 'Not set up'")
    func noPlace() {
        #expect(cpHeroDetail(place: nil, plugsFree: nil, plugsTotal: nil) == "Not set up")
        #expect(cpHeroDetail(place: nil, plugsFree: 2, plugsTotal: 4) == "Not set up")
    }

    @Test("Place only returns trimmed place")
    func placeOnly() {
        #expect(cpHeroDetail(place: "Office", plugsFree: nil, plugsTotal: nil) == "Office")
        #expect(cpHeroDetail(place: "  Garage  ", plugsFree: nil, plugsTotal: nil) == "Garage")
    }

    @Test("Place with plug counts")
    func placeWithPlugCounts() {
        let result = cpHeroDetail(place: "Office", plugsFree: 2, plugsTotal: 4)
        #expect(result == "Office · 2 of 4 plugs free")
    }

    @Test("Place with singular plug free")
    func placeWithSingularPlugFree() {
        let result = cpHeroDetail(place: "Office", plugsFree: 1, plugsTotal: 4)
        #expect(result == "Office · 1 of 4 plugs free")
    }

    @Test("Place with zero plugs free")
    func placeWithZeroPlugsFree() {
        let result = cpHeroDetail(place: "Office", plugsFree: 0, plugsTotal: 4)
        #expect(result == "Office · 0 of 4 plugs free")
    }

    @Test("Place with partial plug counts returns place only")
    func placeWithPartialCounts() {
        // If only one count is present, ignore both
        #expect(cpHeroDetail(place: "Office", plugsFree: 2, plugsTotal: nil) == "Office")
        #expect(cpHeroDetail(place: "Office", plugsFree: nil, plugsTotal: 4) == "Office")
    }
}
