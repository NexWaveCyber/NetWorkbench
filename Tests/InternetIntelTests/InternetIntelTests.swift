import Testing
@testable import InternetIntel
@testable import NetworkCore

@Suite("Internet Intelligence Engine Tests")
struct InternetIntelTests {
    @Test("BGP Announcement Model Initialization")
    func testBGPAnnouncementModel() {
        let bgp = BGPAnnouncement(
            prefix: "1.1.1.0/24",
            originASN: 13335,
            registry: "apnic",
            countryCode: "au",
            allocationDate: "2011-08-11"
        )
        #expect(bgp.prefix == "1.1.1.0/24")
        #expect(bgp.originASN == 13335)
        #expect(bgp.registry == "APNIC")
        #expect(bgp.countryCode == "AU")
    }

    @Test("ASRecord Formatted ASN")
    func testASRecord() {
        let record = ASRecord(
            asn: 15169,
            asName: "GOOGLE",
            countryCode: "US",
            registry: "ARIN",
            allocatedDate: "2000-03-30"
        )
        #expect(record.formattedASN == "AS15169")
        #expect(record.asName == "GOOGLE")
    }

    @Test("RPKI Status Verification Model")
    func testRPKIStatus() {
        let valid = RPKIValidationResult(
            status: .valid,
            originASN: 13335,
            prefix: "1.1.1.0/24",
            explanation: "ROA signed"
        )
        #expect(valid.status == .valid)
        #expect(valid.status.displayLabel.contains("Valid"))

        let invalid = RPKIValidationResult(
            status: .invalid,
            originASN: 13335,
            prefix: "1.1.1.0/24",
            explanation: "Conflict"
        )
        #expect(invalid.status == .invalid)
    }
}
