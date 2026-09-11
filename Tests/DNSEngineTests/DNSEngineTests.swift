import Testing
@testable import DNSEngine
@testable import NetworkCore

@Suite("DNSEngine Resolution & Records")
struct DNSEngineTests {
    @Test("DNSRecord Creation and Identity")
    func testDNSRecord() {
        let record = DNSRecord(name: "example.com", type: .a, value: "93.184.216.34", ttl: 3600)
        #expect(record.type == .a)
        #expect(record.value == "93.184.216.34")
        #expect(record.ttl == 3600)
    }

    @Test("Localhost Resolution")
    func testLocalhostResolution() async {
        let resolver = DNSResolver()
        let result = await resolver.resolve(hostname: "localhost")
        #expect(result.isHealthy == true)
        #expect(!result.records.isEmpty)
        #expect(result.queryTimeMs >= 0.0)
    }
}
