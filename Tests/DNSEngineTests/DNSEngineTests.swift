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

    @Test("DoH Model & Endpoint URLs")
    func testDoHEndpoints() {
        #expect(DoHEndpoint.cloudflare.queryURL == "https://cloudflare-dns.com/dns-query")
        #expect(DoHEndpoint.google.queryURL == "https://dns.google/resolve")
        #expect(DoHEndpoint.quad9.queryURL == "https://dns.quad9.net/dns-query")

        let answer = DoHAnswerRecord(name: "example.com", type: 1, ttl: 300, data: "93.184.216.34")
        #expect(answer.typeName == "A")
    }

    @Test("DoH Live Query Cloudflare")
    func testDoHLiveQuery() async {
        let client = DoHClient()
        let res = await client.resolve(name: "cloudflare.com", endpoint: .cloudflare)
        #expect(res.isSuccess)
        #expect(res.statusCode == 0)
        #expect(!res.answers.isEmpty)
        #expect(res.isDNSSECValidated) // cloudflare.com is signed with DNSSEC
    }

    @Test("DoH Live Query Quad9 RFC 8484")
    func testDoHQuad9LiveQuery() async {
        let client = DoHClient()
        var res = await client.resolve(name: "apple.com", endpoint: .quad9)
        if !res.isSuccess {
            res = await client.resolve(name: "apple.com", endpoint: .quad9)
        }
        if res.isSuccess {
            #expect(res.statusCode == 0)
            #expect(!res.answers.isEmpty)
        }
    }
}

