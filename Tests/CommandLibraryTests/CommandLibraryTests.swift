import Testing
import Foundation
import NetworkCore
@testable import CommandLibrary

@Suite("CommandLibrary Enterprise Multi-Vendor Tests")
struct CommandLibraryTests {
    @Test("Command Database Scale, Vendors, and Categories")
    func testDatabaseScale() {
        let db = CommandDatabase.shared
        #expect(db.commands.count >= 160)

        // Verify all 8 vendors are present
        let vendors = Set(db.commands.map { $0.vendor })
        #expect(vendors.count == 8)
        for v in VendorOS.allCases {
            #expect(vendors.contains(v), "Vendor \(v.rawValue) missing from database")
        }

        // Verify all 12 categories are present
        let categories = Set(db.commands.map { $0.category })
        #expect(categories.count == 12)
        for c in CommandCategory.allCases {
            #expect(categories.contains(c), "Category \(c.rawValue) missing from database")
        }
    }

    @Test("Multi-Vendor Rosetta Stone Matrix")
    func testRosettaStone() {
        let db = CommandDatabase.shared

        // 1. Transceiver Diagnostics
        let transceiverMatrix = db.rosettaStone(forIntent: "Show Transceiver Diagnostics")
        #expect(transceiverMatrix.count == 8)
        #expect(transceiverMatrix[.ciscoIOSXE]?.syntax.contains("transceiver") == true)
        #expect(transceiverMatrix[.juniperJunos]?.syntax.contains("optics") == true)
        #expect(transceiverMatrix[.linuxNet]?.syntax.contains("ethtool") == true)

        // 2. BGP Summary
        let bgpMatrix = db.rosettaStone(forIntent: "Show BGP Summary")
        #expect(bgpMatrix.count == 8)
        #expect(bgpMatrix[.aristaEOS]?.syntax == "show ip bgp summary")
        #expect(bgpMatrix[.fortinetFortiOS]?.syntax.contains("bgp summary") == true)
        #expect(bgpMatrix[.mikrotikRouterOS]?.syntax.contains("/routing bgp session print") == true)
    }

    @Test("Parameter Interpolation Engine")
    func testParameterInterpolation() {
        let param = CommandParameter(key: "interface", label: "Interface", defaultValue: "GigabitEthernet1/0/1")
        let cmd = VendorCommand(
            intent: "Show Interface Details",
            category: .interfaces,
            vendor: .ciscoIOSXE,
            syntax: "show interfaces {{interface}} status",
            description: "Status check",
            parameters: [param]
        )

        // With custom value
        let custom = cmd.interpolate(with: ["interface": "TenGigabitEthernet1/1/1"])
        #expect(custom == "show interfaces TenGigabitEthernet1/1/1 status")

        // With default value fallback
        let defaulted = cmd.interpolate(with: [:])
        #expect(defaulted == "show interfaces GigabitEthernet1/0/1 status")
    }

    @Test("Search and Query Index")
    func testSearchEngine() {
        let db = CommandDatabase.shared

        let bgpResults = db.search(query: "BGP")
        #expect(!bgpResults.isEmpty)
        #expect(bgpResults.allSatisfy {
            $0.intent.localizedCaseInsensitiveContains("BGP") ||
            $0.syntax.localizedCaseInsensitiveContains("BGP") ||
            $0.category == .bgp ||
            $0.description.localizedCaseInsensitiveContains("BGP")
        })

        let lldpResults = db.search(query: "lldp")
        #expect(!lldpResults.isEmpty)
        #expect(lldpResults.contains(where: { $0.vendor == .ciscoIOSXE }))
        #expect(lldpResults.contains(where: { $0.vendor == .juniperJunos }))
    }

    @Test("Markdown and CSV Cheatsheet Export")
    func testCheatsheetExport() {
        let db = CommandDatabase.shared

        let md = db.exportMarkdown()
        #expect(md.contains("# NexWave Network Operations Command Library Cheatsheet"))
        #expect(md.contains("## Optics & Transceivers"))
        #expect(md.contains("Show Transceiver Diagnostics"))

        let csv = db.exportCSV()
        #expect(csv.hasPrefix("Intent,Category,Vendor,Syntax,Description"))
        #expect(csv.contains("Show BGP Summary"))
    }
}
