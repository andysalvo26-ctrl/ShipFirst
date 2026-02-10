import XCTest
@testable import ShipFirstIntake

final class RunValidationTests: XCTestCase {
    func testValidationPassesForCompleteTenRoles() {
        let projectID = UUID()
        let cycleNo = 1
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
                        trustLabel: .userSaid,
                        provenanceRefs: ["turn:1"],
                        claimIndex: 0
                    )
                ]
            )
        }

        let result = RunValidator.validate(documents: docs)
        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.issues.isEmpty)
    }

    func testValidationFailsWhenRoleMissing() {
        let projectID = UUID()
        let cycleNo = 1
        let versionID = UUID()
        var docs = RoleCatalog.orderedRoles.map { role in
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
                        trustLabel: .userSaid,
                        provenanceRefs: ["turn:1"],
                        claimIndex: 0
                    )
                ]
            )
        }
        docs.removeLast()

        let result = RunValidator.validate(documents: docs)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.issues.joined(separator: " ").contains("Missing required roles"))
    }

    func testValidationFailsWhenContractVersionsAreMixed() {
        let projectID = UUID()
        let cycleNo = 1
        let versionA = UUID()
        let versionB = UUID()
        let docs = RoleCatalog.orderedRoles.enumerated().map { index, role in
            BrainDocument(
                id: UUID(),
                projectID: projectID,
                cycleNo: cycleNo,
                contractVersionID: index == 0 ? versionA : versionB,
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
                        contractVersionID: index == 0 ? versionA : versionB,
                        contractDocID: UUID(),
                        roleID: role.id,
                        claimText: "Claim",
                        trustLabel: .userSaid,
                        provenanceRefs: ["turn:1"],
                        claimIndex: 0
                    )
                ]
            )
        }

        let result = RunValidator.validate(documents: docs)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.issues.contains(where: { $0.contains("one contract version") }))
    }

    func testValidationFailsWhenProvenanceMissing() {
        let projectID = UUID()
        let cycleNo = 1
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
                        trustLabel: .assumed,
                        provenanceRefs: [],
                        claimIndex: 0
                    )
                ]
            )
        }

        let result = RunValidator.validate(documents: docs)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.issues.contains(where: { $0.contains("missing provenance") }))
    }
}
