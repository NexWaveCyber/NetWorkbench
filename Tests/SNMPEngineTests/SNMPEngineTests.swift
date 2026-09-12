import Testing
import Foundation
@testable import SNMPEngine

@Suite("SNMPEngine Tests")
struct SNMPEngineTests {

    @Test("ASN.1 BER Integer & Length Encoding/Decoding")
    func testASN1Integer() throws {
        let values: [Int64] = [0, 1, 127, 128, 255, 256, 65535, 65536, -1, -128, 100000]

        for v in values {
            let encoded = ASN1Encoder.encodeInteger(v)
            var decoder = ASN1Decoder(data: encoded)
            let decoded = try decoder.readInteger()
            #expect(decoded == v)
        }
    }

    @Test("ASN.1 BER OctetString & Null Encoding/Decoding")
    func testASN1StringAndNull() throws {
        let str = "NexWave-Telemetry"
        let encodedStr = ASN1Encoder.encodeOctetString(str)
        var strDecoder = ASN1Decoder(data: encodedStr)
        let decodedStr = try strDecoder.readOctetString()
        #expect(decodedStr == str)

        let encodedNull = ASN1Encoder.encodeNull()
        var nullDecoder = ASN1Decoder(data: encodedNull)
        let tag = try nullDecoder.readTag()
        let len = try nullDecoder.readLength()
        #expect(tag == ASN1Tag.null)
        #expect(len == 0)
    }

    @Test("ASN.1 BER OID Encoding and Decoding")
    func testASN1OID() throws {
        let testOIDs = [
            "1.3.6.1.2.1.1.1.0",       // sysDescr.0
            "1.3.6.1.2.1.2.2.1.10.1",   // ifInOctets.1
            "1.3.6.1.4.1.9.9.48.1.1.1", // ciscoMemoryPool
            "2.5.4.3"                   // commonName
        ]

        for oid in testOIDs {
            let encoded = try ASN1Encoder.encodeOID(oid)
            var decoder = ASN1Decoder(data: encoded)
            let decoded = try decoder.readOID()
            #expect(decoded == oid)
        }
    }

    @Test("SNMP Message Serialization & Deserialization Roundtrip")
    func testSNMPMessageRoundtrip() throws {
        let varBinds = [
            SNMPVarBind(oid: "1.3.6.1.2.1.1.1.0", value: .null),
            SNMPVarBind(oid: "1.3.6.1.2.1.1.3.0", value: .null),
            SNMPVarBind(oid: "1.3.6.1.2.1.1.5.0", value: .octetString("core-sw01"))
        ]

        let pdu = SNMPPDU(
            tag: ASN1Tag.getRequest,
            requestId: 12345,
            errorStatus: .noError,
            errorIndex: 0,
            varBinds: varBinds
        )

        let msg = SNMPMessage(version: .v2c, community: "public", pdu: pdu)
        let serialized = try msg.serialize()

        let deserialized = try SNMPMessage.deserialize(data: serialized)
        #expect(deserialized.version == .v2c)
        #expect(deserialized.community == "public")
        #expect(deserialized.pdu.requestId == 12345)
        #expect(deserialized.pdu.tag == ASN1Tag.getRequest)
        #expect(deserialized.pdu.varBinds.count == 3)
        #expect(deserialized.pdu.varBinds[0].oid == "1.3.6.1.2.1.1.1.0")
        #expect(deserialized.pdu.varBinds[0].value == .null)
        #expect(deserialized.pdu.varBinds[2].value == .octetString("core-sw01"))
    }

    @Test("OIDTrie Hierarchy and Symbolic Resolution")
    func testOIDTrie() {
        let trie = OIDTrie()
        trie.insert(oid: "1.3.6.1.2.1.1.1", name: "sysDescr")
        trie.insert(oid: "1.3.6.1.2.1.1.3", name: "sysUpTime")
        trie.insert(oid: "1.3.6.1.2.1.1.5", name: "sysName")

        #expect(trie.resolveName(oid: "1.3.6.1.2.1.1.1.0") == "sysDescr.0")
        #expect(trie.resolveName(oid: "1.3.6.1.2.1.1.3.0") == "sysUpTime.0")
        #expect(trie.resolveName(oid: "1.3.6.1.2.1.1.5.0") == "sysName.0")
        #expect(trie.resolveName(oid: "1.3.6.1.2.1.99.1.0") == "1.3.6.1.2.1.99.1.0") // Unmapped

        let children = trie.allChildren(prefix: "1.3.6.1.2.1.1")
        #expect(children.count == 3)
    }

    @Test("MIBDictionary Standard Lookups")
    func testMIBDictionaryStandardLookups() {
        let mib = MIBDictionary.shared
        #expect(mib.resolve(oid: "1.3.6.1.2.1.1.1.0") == "sysDescr.0")
        #expect(mib.resolve(oid: "1.3.6.1.2.1.2.1.0") == "ifNumber.0")
        #expect(mib.resolve(oid: "1.3.6.1.2.1.2.2.1.10.1") == "ifInOctets.1")
        #expect(mib.resolve(oid: "1.3.6.1.2.1.2.2.1.14.2") == "ifInErrors.2")
        #expect(mib.resolve(oid: "1.3.6.1.2.1.31.1.1.1.1.3") == "ifName.3")
    }

    @Test("Interface Throughput and Error Delta Calculations")
    func testInterfaceDeltaCalculations() {
        let t0 = Date()
        let t1 = t0.addingTimeInterval(5.0) // 5.0 seconds later

        let prev = SNMPInterfaceMetric(
            index: 1,
            name: "GigabitEthernet0/1",
            speedMbps: 1000.0,
            inOctets: 100_000_000,
            outOctets: 50_000_000,
            inErrors: 10,
            outErrors: 5,
            timestamp: t0
        )

        // 5 seconds later: 10MB in (80 Mbits -> 16 Mbps), 5MB out (40 Mbits -> 8 Mbps), 20 inErrors (4 err/s)
        let curr = SNMPInterfaceMetric(
            index: 1,
            name: "GigabitEthernet0/1",
            speedMbps: 1000.0,
            inOctets: 110_000_000,
            outOctets: 55_000_000,
            inErrors: 30,
            outErrors: 5,
            timestamp: t1
        )

        let delta = SNMPClient.calculateDeltas(previous: prev, current: curr)

        #expect(abs(delta.inMbps - 16.0) < 0.1)
        #expect(abs(delta.outMbps - 8.0) < 0.1)
        #expect(abs(delta.inErrorsPerSec - 4.0) < 0.01)
        #expect(delta.outErrorsPerSec == 0.0)
        #expect(delta.inUtilizationPct > 1.5 && delta.inUtilizationPct < 1.7)
    }
}
