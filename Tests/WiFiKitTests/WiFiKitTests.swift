import Testing
import Foundation
@testable import WiFiKit
import DeviceKit

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

    @Test("Algorithmic RF Channel Recommendation")
    func testChannelRecommendationEngine() async {
        let engine = WiFiEngine()
        // Simulate heavy congestion on 2.4 GHz Ch 1 & 11, clean Ch 6
        let networks: [NearbyAP] = [
            NearbyAP(ssid: "AP1", bssid: "00:00:00:00:00:01", channel: 1, band: .ghz2_4, channelWidth: .mhz20, rssi: -45, noise: -85, security: "WPA2", phyMode: "802.11n", isCurrentAssociation: false),
            NearbyAP(ssid: "AP2", bssid: "00:00:00:00:00:02", channel: 1, band: .ghz2_4, channelWidth: .mhz20, rssi: -55, noise: -85, security: "WPA2", phyMode: "802.11n", isCurrentAssociation: false),
            NearbyAP(ssid: "AP3", bssid: "00:00:00:00:00:03", channel: 11, band: .ghz2_4, channelWidth: .mhz20, rssi: -50, noise: -85, security: "WPA2", phyMode: "802.11n", isCurrentAssociation: false),
            // 5 GHz: heavy on UNII-1 (36, 40, 44, 48), clean UNII-3 (149)
            NearbyAP(ssid: "5G-1", bssid: "00:00:00:00:00:04", channel: 36, band: .ghz5, channelWidth: .mhz80, rssi: -50, noise: -85, security: "WPA2", phyMode: "802.11ax", isCurrentAssociation: false),
            NearbyAP(ssid: "5G-2", bssid: "00:00:00:00:00:05", channel: 40, band: .ghz5, channelWidth: .mhz80, rssi: -55, noise: -85, security: "WPA2", phyMode: "802.11ax", isCurrentAssociation: false),
            NearbyAP(ssid: "5G-3", bssid: "00:00:00:00:00:06", channel: 44, band: .ghz5, channelWidth: .mhz80, rssi: -60, noise: -85, security: "WPA2", phyMode: "802.11ax", isCurrentAssociation: false)
        ]

        let recs = await engine.recommendOptimalChannels(from: networks, currentChannel: 1)
        #expect(recs.count == 3)

        // 2.4 GHz recommendation should select Ch 6
        let rec24 = recs.first { $0.band == .ghz2_4 }
        #expect(rec24 != nil)
        #expect(rec24?.recommendedChannel == 6)
        #expect((rec24?.cleanlinessScore ?? 0) > 80)

        // 5 GHz recommendation should select UNII-3 (149) or DFS
        let rec5 = recs.first { $0.band == .ghz5 }
        #expect(rec5 != nil)
        #expect(rec5?.recommendedChannel != 36) // Ch 36 is congested
        #expect(rec5?.contendingAPCount == 0)

        // 6 GHz recommendation should exist
        let rec6 = recs.first { $0.band == .ghz6 }
        #expect(rec6 != nil)
        #expect(rec6?.cleanlinessScore == 100)
    }

    @Test("Co-Channel Contention Assessment")
    func testCoChannelContentionEvaluation() async {
        let engine = WiFiEngine()
        let currentLink = WiFiCurrentLink(
            interfaceName: "en0",
            macAddress: "de:06:f4:f1:6e:35",
            ssid: "HomeOffice",
            bssid: "00:1C:7F:6C:17:6E",
            rssi: -50,
            noise: -85,
            transmitRate: 866.0,
            channel: 36,
            band: .ghz5,
            channelWidth: .mhz80,
            phyMode: .ac,
            security: "WPA2",
            countryCode: "US"
        )

        // Case 1: Clean - 0 competing APs
        let cleanWarning = await engine.evaluateCoChannelContention(currentLink: currentLink, networks: [])
        #expect(cleanWarning.severity == .clean)
        #expect(cleanWarning.contendingAPCount == 0)

        // Case 2: Severe - 4 competing APs on Ch 36
        let busyNetworks = [
            NearbyAP(ssid: "Neighbor1", bssid: "00:11:22:33:44:01", channel: 36, band: .ghz5, channelWidth: .mhz80, rssi: -60, noise: -85, security: "WPA2", phyMode: "802.11ac", isCurrentAssociation: false),
            NearbyAP(ssid: "Neighbor2", bssid: "00:11:22:33:44:02", channel: 36, band: .ghz5, channelWidth: .mhz80, rssi: -65, noise: -85, security: "WPA2", phyMode: "802.11ac", isCurrentAssociation: false),
            NearbyAP(ssid: "Neighbor3", bssid: "00:11:22:33:44:03", channel: 36, band: .ghz5, channelWidth: .mhz80, rssi: -70, noise: -85, security: "WPA2", phyMode: "802.11ac", isCurrentAssociation: false),
            NearbyAP(ssid: "Neighbor4", bssid: "00:11:22:33:44:04", channel: 36, band: .ghz5, channelWidth: .mhz80, rssi: -72, noise: -85, security: "WPA2", phyMode: "802.11ac", isCurrentAssociation: false)
        ]
        let severeWarning = await engine.evaluateCoChannelContention(currentLink: currentLink, networks: busyNetworks)
        #expect(severeWarning.severity == .severe)
        #expect(severeWarning.contendingAPCount == 4)
    }

    @Test("OUI Hardware Vendor Resolution")
    func testOUIHardwareVendorResolution() {
        // Cisco Systems
        #expect(OUIResolver.resolve(mac: "00:00:0C:12:34:56") == "Cisco Systems, Inc")
        // Apple
        #expect(OUIResolver.resolve(mac: "3C:07:54:AA:BB:CC") == "Apple, Inc.")
        // Aruba / HPE
        #expect(OUIResolver.resolve(mac: "00:0B:86:11:22:33") == "Hewlett Packard Enterprise")
        // Ubiquiti Networks
        #expect(OUIResolver.resolve(mac: "24:A4:3C:99:88:77") == "Ubiquiti Inc")
        // eero / Amazon
        #expect(OUIResolver.resolve(mac: "50:F5:DA:44:55:66") == "Amazon Technologies Inc.")
    }

    @Test("RF Survey Report Markdown and JSON Export")
    func testRFSurveyReportGeneration() async {
        let engine = WiFiEngine()
        let link = WiFiCurrentLink(
            interfaceName: "en0",
            macAddress: "de:06:f4:f1:6e:35",
            ssid: "HQ-Production",
            bssid: "00:00:0C:12:34:56",
            vendorName: "Cisco Systems",
            rssi: -42,
            noise: -88,
            transmitRate: 1200.0,
            mcsIndex: 11,
            channel: 149,
            band: .ghz5,
            channelWidth: .mhz80,
            phyMode: .ax,
            security: "WPA3 Enterprise",
            countryCode: "US",
            dhcpServer: "192.168.1.1"
        )

        let networks = [
            NearbyAP(ssid: "HQ-Guest", bssid: "00:00:0C:99:88:77", vendorName: "Cisco Systems", channel: 149, band: .ghz5, channelWidth: .mhz80, rssi: -65, noise: -88, security: "WPA2", phyMode: "802.11ax", isCurrentAssociation: false)
        ]

        let report = await engine.generateSurveyReport(currentLink: link, networks: networks)
        let md = report.toMarkdown()
        let json = report.toJSON()

        #expect(md.contains("NexWave Wi-Fi Studio RF Survey Report"))
        #expect(md.contains("HQ-Production"))
        #expect(md.contains("Cisco Systems"))
        #expect(md.contains("Algorithmic Channel Recommendations"))

        #expect(json.contains("\"ssid\" : \"HQ-Production\""))
        #expect(json.contains("\"vendorName\" : \"Cisco Systems\""))
    }

    @Test("RF Spectrum Frequency Spans & Geometry Helper")
    func testRFFrequencyGeometry() {
        // 2.4 GHz
        let ch1Span = RFFrequencyHelper.frequencySpan(channel: 1, band: .ghz2_4, width: .mhz20)
        #expect(RFFrequencyHelper.centerFrequencyMHz(channel: 1, band: .ghz2_4) == 2412.0)
        #expect(ch1Span.lowerBound == 2401.0)
        #expect(ch1Span.upperBound == 2423.0)

        // 5 GHz UNII-1 80 MHz bonded block (Ch 36 - 48 bonded center 5210 MHz)
        let ch36Span = RFFrequencyHelper.frequencySpan(channel: 36, band: .ghz5, width: .mhz80)
        #expect(RFFrequencyHelper.centerFrequencyMHz(channel: 36, band: .ghz5) == 5180.0)
        #expect(ch36Span.lowerBound == 5170.0)
        #expect(ch36Span.upperBound == 5250.0)

        // DFS Radar Detection
        #expect(RFFrequencyHelper.isDFS(channel: 52, band: .ghz5) == true)
        #expect(RFFrequencyHelper.isDFS(channel: 100, band: .ghz5) == true)
        #expect(RFFrequencyHelper.isDFS(channel: 36, band: .ghz5) == false)
        #expect(RFFrequencyHelper.isDFS(channel: 149, band: .ghz5) == false)

        // 6 GHz Preferred Scanning Channel
        #expect(RFFrequencyHelper.centerFrequencyMHz(channel: 37, band: .ghz6) == 6135.0)
        #expect(RFFrequencyHelper.uniiSubBand(channel: 37, band: .ghz6) == "UNII-5")
    }

    @Test("OBSS Bonded Channel Overlap Detection")
    func testOBSSContentionDetection() async {
        let engine = WiFiEngine()
        let currentLink = WiFiCurrentLink(
            interfaceName: "en0",
            macAddress: "de:06:f4:f1:6e:35",
            ssid: "Corporate-5G",
            bssid: "00:11:22:33:44:00",
            rssi: -45,
            noise: -85,
            transmitRate: 1200.0,
            channel: 36,
            band: .ghz5,
            channelWidth: .mhz80,
            phyMode: .ax,
            security: "WPA3",
            countryCode: "US"
        )

        // AP on Channel 40 at 80 MHz: primary channel differs (36 vs 40), but both share 5170-5250 MHz!
        let networks = [
            NearbyAP(ssid: "Neighbor-80M", bssid: "AA:BB:CC:DD:EE:01", vendorName: "Netgear", channel: 40, band: .ghz5, channelWidth: .mhz80, rssi: -60, noise: -85, security: "WPA2", phyMode: "802.11ax", isCurrentAssociation: false),
            // Distant AP on UNII-3 (Ch 149, 80 MHz): completely separate spectrum (5735-5815 MHz)
            NearbyAP(ssid: "Distant-149", bssid: "AA:BB:CC:DD:EE:02", vendorName: "Aruba", channel: 149, band: .ghz5, channelWidth: .mhz80, rssi: -70, noise: -85, security: "WPA2", phyMode: "802.11ax", isCurrentAssociation: false)
        ]

        let warning = await engine.evaluateCoChannelContention(currentLink: currentLink, networks: networks)
        #expect(warning.contendingAPCount == 0) // Zero direct co-channel (channel 36)
        #expect(warning.obssOverlappingAPCount == 1) // 1 OBSS overlap on Ch 40!
        #expect(warning.obssOverlaps.first?.primaryChannel == 40)
        #expect(warning.obssOverlaps.first?.overlappingBandwidthMHz == 80.0)
    }

    @Test("Sticky Client Anomaly Detection")
    func testStickyClientAnomaly() async {
        let engine = WiFiEngine()
        let weakLink = WiFiCurrentLink(
            interfaceName: "en0",
            macAddress: "de:06:f4:f1:6e:35",
            ssid: "Campus-Secure",
            bssid: "11:22:33:44:55:01",
            vendorName: "Cisco Systems",
            rssi: -78, // Degraded signal
            noise: -85,
            transmitRate: 144.0,
            channel: 1,
            band: .ghz2_4,
            channelWidth: .mhz20,
            phyMode: .n,
            security: "WPA3",
            countryCode: "US"
        )

        let networks = [
            // Strong candidate on same SSID
            NearbyAP(ssid: "Campus-Secure", bssid: "11:22:33:44:55:02", vendorName: "Cisco Systems", channel: 149, band: .ghz5, channelWidth: .mhz80, rssi: -48, noise: -85, security: "WPA3", phyMode: "802.11ax", isCurrentAssociation: false),
            // Unrelated neighbor network
            NearbyAP(ssid: "Guest-Cafe", bssid: "99:88:77:66:55:44", vendorName: "Apple", channel: 6, band: .ghz2_4, channelWidth: .mhz20, rssi: -50, noise: -85, security: "WPA2", phyMode: "802.11ax", isCurrentAssociation: false)
        ]

        let anomaly = await engine.evaluateStickyClientAnomaly(currentLink: weakLink, networks: networks)
        #expect(anomaly != nil)
        #expect(anomaly?.candidateBSSID == "11:22:33:44:55:02")
        #expect(anomaly?.rssiDelta == 30) // -48 - (-78) = +30 dBm
        #expect(anomaly?.candidateChannel == 149)
    }

    @Test("Dynamic Modulation and Coding Scheme (MCS) Derivation")
    func testDynamicMCSExtraction() async {
        let engine = WiFiEngine()
        // 80 MHz 2x2
        #expect(await engine.extractMCSIndex(txRate: 1200.0, channelWidth: .mhz80, phyMode: .ax) == 11)
        #expect(await engine.extractMCSIndex(txRate: 864.0, channelWidth: .mhz80, phyMode: .ax) == 8)
        #expect(await engine.extractMCSIndex(txRate: 240.0, channelWidth: .mhz80, phyMode: .ax) == 2)

        // 40 MHz 2x2
        #expect(await engine.extractMCSIndex(txRate: 574.0, channelWidth: .mhz40, phyMode: .ax) == 11)
        #expect(await engine.extractMCSIndex(txRate: 280.0, channelWidth: .mhz40, phyMode: .ax) == 6)

        // 20 MHz 2x2
        #expect(await engine.extractMCSIndex(txRate: 287.0, channelWidth: .mhz20, phyMode: .ax) == 11)
    }

    @Test("RFC 4180 CSV Survey Report Export")
    func testCSVReportExport() async {
        let engine = WiFiEngine()
        let link = WiFiCurrentLink(
            interfaceName: "en0",
            macAddress: "de:06:f4:f1:6e:35",
            ssid: "Corporate-5G",
            bssid: "00:1C:7F:6C:17:6E",
            vendorName: "Aruba",
            rssi: -45,
            noise: -88,
            transmitRate: 1200.0,
            channel: 36,
            band: .ghz5,
            channelWidth: .mhz80,
            phyMode: .ax,
            security: "WPA3 Personal",
            countryCode: "US"
        )

        let networks = [
            NearbyAP(ssid: "Corporate-5G", bssid: "00:1C:7F:6C:17:6E", vendorName: "Aruba", channel: 36, band: .ghz5, channelWidth: .mhz80, rssi: -45, noise: -88, security: "WPA3 Personal", phyMode: "802.11ax", isCurrentAssociation: true),
            NearbyAP(ssid: "Guest-WiFi", bssid: "00:1C:7F:6C:17:6F", vendorName: "Aruba", channel: 149, band: .ghz5, channelWidth: .mhz80, rssi: -62, noise: -88, security: "WPA2", phyMode: "802.11ax", isCurrentAssociation: false)
        ]

        let report = await engine.generateSurveyReport(currentLink: link, networks: networks)
        let csv = report.toCSV()

        #expect(csv.contains("SSID,BSSID,Vendor,Channel,Band,Channel_Width,Center_Frequency_MHz,Signal_dBm,Noise_dBm,SNR_dB,Security,PHY_Mode,Is_Connected"))
        #expect(csv.contains("\"Corporate-5G\",\"00:1C:7F:6C:17:6E\",\"Aruba\",36,\"5 GHz\",\"80 MHz\",5180,-45,-88,43,\"WPA3 Personal\",\"802.11ax\",TRUE"))
        #expect(csv.contains("\"Guest-WiFi\",\"00:1C:7F:6C:17:6F\",\"Aruba\",149,\"5 GHz\",\"80 MHz\",5745,-62,-88,26,\"WPA2\",\"802.11ax\",FALSE"))
    }
}


