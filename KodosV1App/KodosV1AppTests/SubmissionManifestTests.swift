import XCTest
@testable import KodosV1

final class SubmissionManifestTests: XCTestCase {
    func testManifestContainsRunAndTenDocuments() {
        let runID = UUID()
        let projectID = UUID()
        let cycleNo = 1
        let userID = UUID()
        let versionID = UUID()
        let docs = RoleCatalog.orderedRoles.map { role in
            BrainDocument(
                id: UUID(),
                projectID: projectID,
                cycleNo: cycleNo,
                contractVersionID: versionID,
                roleID: role.id,
                title: role.displayName,
                body: "Body",
                isComplete: true,
                createdAt: "2026-01-01T00:00:00Z",
                claims: [
                    DocumentClaim(
                        id: UUID(),
                        projectID: projectID,
                        cycleNo: cycleNo,
                        contractVersionID: versionID,
                        contractDocID: UUID(),
                        roleID: role.id,
                        claimText: "Claim",
                        trustLabel: .unknown,
                        provenanceRefs: ["turn:2"],
                        claimIndex: 0
                    )
                ]
            )
        }

        let manifest = SubmissionManifestBuilder.build(
            runID: runID,
            userID: userID,
            submittedAt: "2026-01-01T00:00:00Z",
            documents: docs
        )

        XCTAssertEqual(manifest.documentCount, 10)
        XCTAssertEqual(manifest.documents.first?.roleID, 1)
        XCTAssertEqual(manifest.documents.last?.roleID, 10)
        XCTAssertEqual(manifest.runID, runID)
        XCTAssertEqual(manifest.userID, userID)
    }
}
