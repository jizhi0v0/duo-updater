import Foundation
import Testing
@testable import DuoKit

@Suite struct DocumentSchemaTests {

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func reportJSON(schemaVersion: String? = nil) -> Data {
        let version = schemaVersion.map { "\"schemaVersion\":\($0)," } ?? ""
        return Data("""
            {\(version)"generatedAt":"2026-01-01T00:00:00Z","findings":[]}
            """.utf8)
    }

    private func triageJSON(schemaVersion: String? = nil) -> Data {
        let version = schemaVersion.map { "\"schemaVersion\":\($0)," } ?? ""
        return Data("""
            {\(version)"generatedAt":"2026-01-01T00:00:00Z","suggestions":[]}
            """.utf8)
    }

    private func reportJSON(
        status: FindingStatus, schemaVersion: Int, warnings: [String] = []
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let finding = Finding(
            recipeID: "changelog:com.example.autofix:-", registry: .changelog,
            bundleID: "com.example.autofix", channel: "-", status: status,
            version: "3.0", warnings: warnings, endpointHost: "notes.example.com")
        let encoded = try encoder.encode(Report.Document(generatedAt: Date(), findings: [finding]))
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["schemaVersion"] = schemaVersion
        return try JSONSerialization.data(withJSONObject: object)
    }

    @Test func reportAcceptsLegacyDocumentsAndTheCurrentVersion() throws {
        for version in [nil, "1", "1.0"] {
            let document = try decoder().decode(
                Report.Document.self, from: reportJSON(schemaVersion: version))
            #expect(document.schemaVersion == 1)
        }
    }

    @Test func reportRejectsUnsupportedAndMalformedVersions() {
        for version in ["2", "999", "0", "-1", "1.5", "true", "\"wrong-type\"", "null"] {
            #expect(throws: (any Error).self) {
                try decoder().decode(Report.Document.self, from: reportJSON(schemaVersion: version))
            }
        }
    }

    @Test func triageAcceptsLegacyDocumentsAndTheCurrentVersion() throws {
        for version in [nil, "1", "1.0"] {
            let document = try decoder().decode(
                TriageDocument.self, from: triageJSON(schemaVersion: version))
            #expect(document.schemaVersion == 1)
        }
    }

    @Test func triageRejectsUnsupportedAndMalformedVersions() {
        for version in ["2", "999", "0", "-1", "1.5", "true", "\"wrong-type\"", "null"] {
            #expect(throws: (any Error).self) {
                try decoder().decode(TriageDocument.self, from: triageJSON(schemaVersion: version))
            }
        }
    }

    @Test func newlyWrittenDocumentsKeepVersionOne() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let date = Date(timeIntervalSince1970: 0)
        let report = try JSONSerialization.jsonObject(with: encoder.encode(
            Report.Document(generatedAt: date, findings: []))) as? [String: Any]
        let triage = try JSONSerialization.jsonObject(with: encoder.encode(
            TriageDocument(generatedAt: date, suggestions: []))) as? [String: Any]
        #expect(report?["schemaVersion"] as? Int == 1)
        #expect(triage?["schemaVersion"] as? Int == 1)
    }

    @Test func reportConsumersRejectFutureVersionsOfOtherwiseValidReports() throws {
        let currentOK = try reportJSON(status: .ok, schemaVersion: 1)
        let futureOK = try reportJSON(status: .ok, schemaVersion: 2)
        let currentWarning = try reportJSON(
            status: .warn, schemaVersion: 1, warnings: ["something degraded"])
        let futureWarning = try reportJSON(
            status: .warn, schemaVersion: 2, warnings: ["something degraded"])

        #expect(ChangelogAutofix.verifyRefusal(
            report: currentOK, recipeID: "changelog:com.example.autofix:-") == nil)
        #expect(ChangelogAutofix.verifyRefusal(
            report: futureOK, recipeID: "changelog:com.example.autofix:-")
                == "G7: could not read duo verify's report")
        #expect(ChangelogAutofix.verifyWarnings(
            report: currentWarning, recipeID: "changelog:com.example.autofix:-")
                == ["something degraded"])
        #expect(ChangelogAutofix.verifyWarnings(
            report: futureWarning, recipeID: "changelog:com.example.autofix:-")
                == ["the report could not be read again"])
    }

    @Test func anInvalidOptionalTriageDocumentDoesNotStopDryRunReconcile() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-document-schema-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let reportURL = root.appendingPathComponent("report.json")
        let triageURL = root.appendingPathComponent("triage.json")
        try reportJSON().write(to: reportURL)
        try triageJSON(schemaVersion: "2").write(to: triageURL)

        let result = await Reconcile.run(.init(
            reportPath: reportURL,
            baselinePath: root.appendingPathComponent("baseline.json"),
            triagePath: triageURL,
            dryRun: true))
        #expect(result == 0)
    }
}
