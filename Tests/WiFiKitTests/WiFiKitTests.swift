import Testing
import Foundation
@testable import WiFiKit

@Suite("WiFiKit Telemetry & RF Metrics")
struct WiFiKitTests {

    @Test("Signal Quality Evaluation Matrix")
    func testSignalQualityMatrix() {
        // Pristine: SNR >= 40 or RSSI >= -50
        #expect(WiFiSignalQuality.evaluate(rssi: -30, noise: -80) == .pristine) // SNR = 50
        #expect(WiFiSignalQuality.evaluate(rssi: -45, noise: -75) == .pristine) // RSSI >= -50

        // Good: SNR 25-39 or RSSI >= -65
        #expect(WiFiSignalQuality.evaluate(rssi: -55, noise: -85) == .good) // SNR = 30
        #expect(WiFiSignalQuality.evaluate(rssi: -62, noise: -80) == .good) // RSSI >= -65

        // Fair: SNR 15-24 or RSSI >= -75
        #expect(WiFiSignalQuality.evaluate(rssi: -68, noise: -88) == .fair) // SNR = 20

        // Degraded: SNR 10-14 or RSSI >= -82
        #expect(WiFiSignalQuality.evaluate(rssi: -78, noise: -90) == .degraded) // SNR = 12

        // Critical: SNR < 10 or RSSI < -82
        #expect(WiFiSignalQuality.evaluate(rssi: -88, noise: -90) == .critical) // SNR = 2, RSSI = -88
    }

    @Test("Current Link SNR and Properties")
    func testCurrentLinkSNR() {
        let link = WiFiCurrentLink(
            interfaceName: "en0",
            macAddress: "de:06:f4:f1:6e:35",
            ssid: "Enterprise-5G",
            bssid: "00:1C:7F:6C:17:6E",
            rssi: -35,
            noise: -85,
            transmitRate: 1200.0,
            mcsIndex: 11,
            channel: 161,
            band: .ghz5,
            channelWidth: .mhz80,
            phyMode: .ax,
            security: "WPA3 Personal",
            countryCode: "US",
            dhcpServer: "10.0.0.1"
        )

        #expect(link.snr == 50)
        #expect(link.signalQuality == .pristine)
        #expect(link.band == .ghz5)
        #expect(link.channelWidth == .mhz80)
        #expect(link.mcsIndex == 11)
    }

    @Test("Roaming Event Delta Calculation")
    func testRoamingEventDelta() {
        let event = WiFiRoamingEvent(
            ssid: "Enterprise-5G",
            previousBSSID: "00:1C:7F:6C:17:6E",
            newBSSID: "00:1C:7F:6C:28:1A",
            previousRSSI: -68,
            newRSSI: -34,
            previousChannel: 36,
            newChannel: 161
        )

        #expect(event.rssiDelta == 34) // Improved by +34 dBm
        #expect(event.previousChannel == 36)
        #expect(event.newChannel == 161)
        #expect(event.newBSSID == "00:1C:7F:6C:28:1A")
    }

    @Test("Channel Congestion Aggregator")
    func testChannelCongestionAggregator() async {
        let engine = WiFiEngine()
        let networks: [NearbyAP] = [
            NearbyAP(ssid: "Net1", bssid: "00:01", channel: 36, band: .ghz5, channelWidth: .mhz80, rssi: -40, noise: -80, security: "WPA2", phyMode: "802.11ax", isCurrentAssociation: true),
            NearbyAP(ssid: "Net2", bssid: "00:02", channel: 36, band: .ghz5, channelWidth: .mhz80, rssi: -50, noise: -80, security: "WPA2", phyMode: "802.11ax", isCurrentAssociation: false),
            NearbyAP(ssid: "Net3", bssid: "00:03", channel: 36, band: .ghz5, channelWidth: .mhz80, rssi: -60, noise: -80, security: "WPA2", phyMode: "802.11ax", isCurrentAssociation: false),
            NearbyAP(ssid: "Net4", bssid: "00:04", channel: 1, band: .ghz2_4, channelWidth: .mhz20, rssi: -70, noise: -85, security: "WPA2", phyMode: "802.11n", isCurrentAssociation: false)
        ]

        let congestion = await engine.calculateChannelCongestion(from: networks, currentChannel: 36)
        #expect(congestion.count == 2)

        let ch36 = congestion.first { $0.channel == 36 }
        #expect(ch36 != nil)
        #expect(ch36?.apCount == 3)
        #expect(ch36?.isCurrentChannel == true)

        let ch1 = congestion.first { $0.channel == 1 }
        #expect(ch1 != nil)
        #expect(ch1?.apCount == 1)
        #expect(ch1?.isCurrentChannel == false)
    }

    @Test("System Profiler Output Parsing")
    func testSystemProfilerParsing() async {
        let engine = WiFiEngine()
        let sampleOutput = """
        Wi-Fi:
          Interfaces:
            en0:
              Status: Connected
              Current Network Information:
                CorpHQ:
                  PHY Mode: 802.11ax
                  Channel: 161 (5GHz, 80MHz)
                  Security: WPA2/WPA3 Personal
                  Signal / Noise: -32 dBm / -82 dBm
              Other Local Wi-Fi Networks:
                GuestNet:
                  PHY Mode: 802.11a/n/ac/ax
                  Channel: 44 (5GHz, 80MHz)
                  Security: WPA2 Personal
        """

        let nets = await engine.parseSystemProfiler(output: sampleOutput)
        #expect(nets.count >= 2)

        let corp = nets.first { $0.ssid == "CorpHQ" }
        #expect(corp != nil)
        #expect(corp?.channel == 161)
        #expect(corp?.rssi == -32)
        #expect(corp?.noise == -82)
        #expect(corp?.channelWidth == .mhz80)
        #expect(corp?.band == .ghz5)

        let guest = nets.first { $0.ssid == "GuestNet" }
        #expect(guest != nil)
        #expect(guest?.channel == 44)
    }
}
