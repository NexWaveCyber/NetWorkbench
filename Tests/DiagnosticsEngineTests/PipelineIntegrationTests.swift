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
        #expect(!result.findings.isEmpty)

        // Verify findings contain analytical classifications
        let classifications = Set(result.findings.map(\.classification))
        #expect(classifications.contains(.observed) || classifications.contains(.derived) || classifications.contains(.inferred))
    }
}
