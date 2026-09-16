import Testing
import Foundation
@testable import NetworkCore
@testable import DiagnosticsEngine

@Suite("DiagnosticPipeline End-to-End Integration")
struct PipelineIntegrationTests {
    @Test("End-to-End Diagnosis of Localhost")
    func testLocalhostDiagnosis() async {
        let target = TargetClassifier.classify("localhost")!
        let pipeline = DiagnosticPipeline()

        let result = await pipeline.execute(target: target)

        #expect(result.target.displayString == "localhost")
        #expect(result.dns != nil)
        #expect(result.dns?.isHealthy == true)
        #expect(result.executionDurationMs > 0.0)

        // Verify findings contain analytical classifications and remediation
        let classifications = Set(result.findings.map(\.classification))
        #expect(classifications.contains(.observed) || classifications.contains(.derived) || classifications.contains(.inferred))
    }

    @Test("Diagnosis with Custom Port and Execution Timing")
    func testCustomPortDiagnosis() async {
        let target = TargetClassifier.classify("127.0.0.1")!
        let pipeline = DiagnosticPipeline()

        let result = await pipeline.execute(target: target, customPort: NetworkPort(8080))

        #expect(result.executionDurationMs > 0.0)
        #expect(result.target.displayString == "127.0.0.1")
        #expect(result.tcp != nil)
    }

    @Test("Live TLS Certificate Inspection on apple.com")
    func testLiveTLSCertificateInspection() async {
        let pipeline = DiagnosticPipeline()
        let target = TargetClassifier.classify("apple.com")!
        let result = await pipeline.execute(target: target)

        #expect(result.http != nil)
        if let cert = result.http?.certificateInfo {
            #expect(cert.expirationDate != nil)
            #expect(cert.daysUntilExpiry != nil)
            #expect((cert.daysUntilExpiry ?? 0) > 0)
            #expect(cert.isExpired == false)
            #expect(cert.cipherSuite != nil)
            #expect(cert.protocolVersion != nil)
            print("Verified apple.com certificate:", cert.subjectSummary, "Expires:", cert.expirationDate as Any, "Days remaining:", cert.daysUntilExpiry as Any, "Cipher:", cert.cipherSuite as Any, "Protocol:", cert.protocolVersion as Any)
        }
    }
}

