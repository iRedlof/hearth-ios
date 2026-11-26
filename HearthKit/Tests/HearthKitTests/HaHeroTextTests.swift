import Testing
@testable import HearthKit

@Suite("HaHeroText Tests")
struct HaHeroTextTests {

    @Test("Empty host returns 'Not connected'")
    func emptyHost() {
        #expect(haHeroDetail(host: "", deviceCount: nil, widgetCount: nil) == "Not connected")
        #expect(haHeroDetail(host: "  ", deviceCount: nil, widgetCount: nil) == "Not connected")
    }

    @Test("Host only returns trimmed host")
    func hostOnly() {
        #expect(haHeroDetail(host: "home.example.net", deviceCount: nil, widgetCount: nil) == "home.example.net")
        #expect(haHeroDetail(host: "  192.168.1.100  ", deviceCount: nil, widgetCount: nil) == "192.168.1.100")
    }

    @Test("Device and widget counts singular")
    func countsSingular() {
        let result = haHeroDetail(host: "home.example.net", deviceCount: 1, widgetCount: 1)
        #expect(result == "1 device · 1 widget")
    }

    @Test("Device and widget counts plural")
    func countsPlural() {
        let result = haHeroDetail(host: "home.example.net", deviceCount: 42, widgetCount: 4)
        #expect(result == "42 devices · 4 widgets")
    }

    @Test("Zero counts")
    func zeroCounts() {
        let result = haHeroDetail(host: "home.example.net", deviceCount: 0, widgetCount: 0)
        #expect(result == "0 devices · 0 widgets")
    }

    @Test("Host ignored when counts present")
    func hostIgnoredWithCounts() {
        let result = haHeroDetail(host: "ignored.example.net", deviceCount: 5, widgetCount: 3)
        #expect(result == "5 devices · 3 widgets")
    }
}
