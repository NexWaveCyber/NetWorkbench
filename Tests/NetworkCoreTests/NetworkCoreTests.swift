import Testing
@testable import NetworkCore

@Suite("NetworkCore Subnet and IP Primitives")
struct NetworkCoreTests {
    @Test("IPv4 Parsing and Classification")
    func testIPv4Classification() {
        let privateIP = IPAddress.IPv4("192.168.1.1")!
        #expect(privateIP.isPrivate == true)
        #expect(privateIP.isLoopback == false)

        let loopback = IPAddress.IPv4("127.0.0.1")!
        #expect(loopback.isLoopback == true)
        #expect(loopback.isPrivate == false)

        let cgnat = IPAddress.IPv4("100.64.1.5")!
        #expect(cgnat.isCarrierGradeNAT == true)

        let publicIP = IPAddress.IPv4("8.8.8.8")!
        #expect(publicIP.isPrivate == false)
        #expect(publicIP.isLoopback == false)
    }

    @Test("IPv4 Subnet Calculations")
    func testSubnetMath() {
        let net = IPNetwork("192.168.10.0/24")!
        #expect(net.networkAddress.description == "192.168.10.0")
        #expect(net.broadcastAddress?.description == "192.168.10.255")
        #expect(net.firstUsableAddress?.description == "192.168.10.1")
        #expect(net.lastUsableAddress?.description == "192.168.10.254")
        #expect(net.usableHostCount == 254)
        #expect(net.ipv4Netmask?.description == "255.255.255.0")
        #expect(net.ipv4WildcardMask?.description == "0.0.0.255")

        let inside = IPAddress("192.168.10.45")!
        let outside = IPAddress("192.168.20.45")!
        #expect(net.contains(inside) == true)
        #expect(net.contains(outside) == false)
    }

    @Test("RFC 3021 Point-to-Point /31 and RFC 1122 /32 Subnets")
    func testSpecialSubnets() {
        let p2p = IPNetwork("10.0.0.0/31")!
        #expect(p2p.usableHostCount == 2)
        #expect(p2p.firstUsableAddress?.description == "10.0.0.0")
        #expect(p2p.lastUsableAddress?.description == "10.0.0.1")

        let host = IPNetwork("10.0.0.5/32")!
        #expect(host.usableHostCount == 1)
        #expect(host.firstUsableAddress?.description == "10.0.0.5")
        #expect(host.lastUsableAddress?.description == "10.0.0.5")
    }

    @Test("Target Auto-Classification")
    func testTargetClassifier() {
        let t1 = TargetClassifier.classify("10.20.30.1")
        #expect(t1?.targetType == .ipv4)

        let t2 = TargetClassifier.classify("2001:db8::1")
        #expect(t2?.targetType == .ipv6)

        let t3 = TargetClassifier.classify("api.example.com")
        #expect(t3?.targetType == .hostname)

        let t4 = TargetClassifier.classify("https://service.internal:8443/status")
        #expect(t4?.targetType == .url)

        let t5 = TargetClassifier.classify("172.16.0.0/16")
        #expect(t5?.targetType == .subnet)

        let t6 = TargetClassifier.classify("core-sw01")
        #expect(t6?.targetType == .device)
    }
}
