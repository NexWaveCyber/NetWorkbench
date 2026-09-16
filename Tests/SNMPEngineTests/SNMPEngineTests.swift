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

    @Test("SNMPv3 Password-to-Key Localization (RFC 3414)")
    func testSNMPv3KeyLocalization() {
        let password = "map-password-123"
        let engineID = Data([0x80, 0x00, 0x00, 0x09, 0x03, 0x00, 0x00, 0x11, 0x22, 0x33, 0x44])

        let md5Key = SNMPv3Crypto.passwordToKey(password: password, engineID: engineID, protocol: .md5)
        #expect(md5Key.count == 16)

        let sha1Key = SNMPv3Crypto.passwordToKey(password: password, engineID: engineID, protocol: .sha1)
        #expect(sha1Key.count == 20)

        let sha256Key = SNMPv3Crypto.passwordToKey(password: password, engineID: engineID, protocol: .sha256)
        #expect(sha256Key.count == 32)
    }

    @Test("SNMPv3 HMAC Authentication Signatures")
    func testSNMPv3HMAC() {
        let sampleData = "Sample SNMPv3 Message Data Payload".data(using: .utf8)!
        let sampleKey = Data(repeating: 0x42, count: 32)

        let md5HMAC = SNMPv3Crypto.computeAuthHMAC(data: sampleData, authKey: sampleKey, protocol: .md5)
        #expect(md5HMAC.count == 12)

        let sha1HMAC = SNMPv3Crypto.computeAuthHMAC(data: sampleData, authKey: sampleKey, protocol: .sha1)
        #expect(sha1HMAC.count == 12)

        let sha256HMAC = SNMPv3Crypto.computeAuthHMAC(data: sampleData, authKey: sampleKey, protocol: .sha256)
        #expect(sha256HMAC.count == 16)
    }

    @Test("SNMPv3 AES-128 CFB Encryption and Decryption Roundtrip")
    func testSNMPv3AES128Roundtrip() throws {
        let plaintext = "TopSecretNetworkScopedPDUConfigurationPayload".data(using: .utf8)!
        let privKey = Data(repeating: 0x5A, count: 16) // 16 bytes for AES-128
        let boots: Int32 = 12
        let time: Int32 = 4500

        let encrypted = try SNMPv3Crypto.encryptAES128(
            payload: plaintext,
            privKey: privKey,
            engineBoots: boots,
            engineTime: time,
            salt: 0x0102030405060708
        )

        #expect(encrypted.privParams.count == 8)
        #expect(encrypted.ciphertext != plaintext)

        let decrypted = try SNMPv3Crypto.decryptAES128(
            ciphertext: encrypted.ciphertext,
            privKey: privKey,
            engineBoots: boots,
            engineTime: time,
            privParams: encrypted.privParams
        )

        #expect(decrypted == plaintext)
    }

    @Test("SNMPv3 ScopedPDU & Message Serialization Roundtrip")
    func testSNMPv3MessageRoundtrip() throws {
        let varBinds = [
            SNMPVarBind(oid: "1.3.6.1.2.1.1.1.0", value: .null),
            SNMPVarBind(oid: "1.3.6.1.2.1.1.5.0", value: .octetString("core-router"))
        ]
        let pdu = SNMPPDU(tag: ASN1Tag.getRequest, requestId: 9988, varBinds: varBinds)
        let scoped = ScopedPDU(
            contextEngineID: Data([0x80, 0x00, 0x00, 0x01]),
            contextName: "vrf-mgmt",
            pdu: pdu
        )
        let rawScoped = try scoped.serialize()

        let deserializedScoped = try ScopedPDU.deserialize(data: rawScoped)
        #expect(deserializedScoped.contextName == "vrf-mgmt")
        #expect(deserializedScoped.pdu.requestId == 9988)
        #expect(deserializedScoped.pdu.varBinds.count == 2)
        #expect(deserializedScoped.pdu.varBinds[1].value == .octetString("core-router"))

        let secParams = UsmSecurityParameters(
            engineID: Data([0x80, 0x00, 0x00, 0x01]),
            engineBoots: 3,
            engineTime: 1200,
            userName: "netadmin",
            authParameters: Data(),
            privParameters: Data()
        )

        let v3Msg = SNMPv3Message(
            msgID: 554433,
            msgFlags: 0x05, // reportable + auth
            securityParameters: secParams,
            scopedPDUData: rawScoped,
            isEncrypted: false
        )

        let authKey = Data(repeating: 0x99, count: 32)
        let wireData = try v3Msg.serialize(authKey: authKey, authProtocol: .sha256)

        let decodedMsg = try SNMPv3Message.deserialize(data: wireData)
        #expect(decodedMsg.msgID == 554433)
        #expect(decodedMsg.securityParameters.userName == "netadmin")
        #expect(decodedMsg.securityParameters.engineBoots == 3)
        #expect(decodedMsg.securityParameters.authParameters.count == 16) // SHA256 truncated HMAC
    }

    @Test("Malformed ASN.1 BER buffer safety and truncation defense")
    func testMalformedBERBufferSafety() {
        // Truncated length claim (header says length 64, data only has 2 bytes)
        let corruptData = Data([0x02, 0x40, 0x01, 0x02])
        var decoder = ASN1Decoder(data: corruptData)
        #expect(throws: Error.self) {
            _ = try decoder.readInteger()
        }

        // Truncated OID payload (length claims 5 bytes, but buffer only has 1 byte)
        let corruptOIDData = Data([0x06, 0x05, 0x01])
        var oidDecoder = ASN1Decoder(data: corruptOIDData)
        #expect(throws: Error.self) {
            _ = try oidDecoder.readOID()
        }
    }

    @Test("SNMP Message deserialization rejects invalid version bytes and garbage")
    func testInvalidSNMPVersionSafety() {
        // Random garbage bytes
        let garbage = Data([0xFF, 0xFE, 0xFD, 0xFC, 0x00, 0x11, 0x22])
        #expect(throws: Error.self) {
            _ = try SNMPMessage.deserialize(data: garbage)
        }

        // Empty payload
        #expect(throws: Error.self) {
            _ = try SNMPMessage.deserialize(data: Data())
        }
    }

    @Test("OIDTrie deep subtree hierarchy and non-matching prefix queries")
    func testOIDTrieSubtreePruning() {
        let trie = OIDTrie()
        trie.insert(oid: "1.3.6.1.4.1.9.9.48.1.1.1.5", name: "ciscoMemoryPoolUsed")
        trie.insert(oid: "1.3.6.1.4.1.9.9.48.1.1.1.6", name: "ciscoMemoryPoolFree")

        // Exact match with instance .1
        let resolved = trie.resolveName(oid: "1.3.6.1.4.1.9.9.48.1.1.1.5.1")
        #expect(resolved == "ciscoMemoryPoolUsed.1")

        // Non-existent subtree query
        let nonExistentChildren = trie.allChildren(prefix: "1.3.6.1.4.1.311")
        #expect(nonExistentChildren.isEmpty)

        // Matching subtree query
        let matchingChildren = trie.allChildren(prefix: "1.3.6.1.4.1.9.9.48")
        #expect(matchingChildren.count == 2)
    }
}


