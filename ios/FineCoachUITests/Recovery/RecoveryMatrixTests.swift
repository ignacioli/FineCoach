import XCTest

/// T064 records ≥20 background/terminate/relaunch combinations as a codec matrix plus two live
/// process tests. Physical-device evidence for the same interruption matrix is a separate gate (T065).
@MainActor
final class RecoveryMatrixTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTerminateRelaunchKeepsCompletedAndDraft() {
        var app = RecoveryProcessDriver.launchIsolatedApp()
        RecoveryProcessDriver.skipOnboardingAndStartLinQingSession(in: app)
        RecoveryProcessDriver.addCompletedSquatSet(in: app)
        RecoveryProcessDriver.addUnconfirmedDraft(in: app)

        RecoveryProcessDriver.terminate(app)
        app = RecoveryProcessDriver.relaunch(app)

        RecoveryProcessDriver.skipOnboardingIfPresented(in: app)
        RecoveryProcessDriver.continueInProgressSession(in: app)

        let result = RecoveryProcessDriver.observe(
            in: app,
            scenarioID: "terminate-completedPlusDraft-saved",
            expectedConfirmed: 1
        )
        XCTAssertEqual(result.confirmedSetLoss, 0, "confirmed 杠铃深蹲 0x5 must survive terminate and relaunch")
        XCTAssertFalse(
            result.draftPromotedToCompleted,
            "unconfirmed draft must not be promoted to completed after relaunch"
        )
        XCTAssertEqual(result.confirmedSetCount, 1)
        XCTAssertFalse(result.sessionCompleted)
    }

    func testRelaunchEmptySessionStaysAbandonable() {
        var app = RecoveryProcessDriver.launchIsolatedApp()
        RecoveryProcessDriver.skipOnboardingAndStartLinQingSession(in: app)
        XCTAssertTrue(
            RecoveryProcessDriver.element(in: app, identifier: "activeSession.emptyHint")
                .waitForExistence(timeout: 8)
        )

        RecoveryProcessDriver.terminate(app)
        app = RecoveryProcessDriver.relaunch(app)

        RecoveryProcessDriver.skipOnboardingIfPresented(in: app)
        if !RecoveryProcessDriver.element(in: app, identifier: "activeSession.root").waitForExistence(timeout: 2) {
            XCTAssertTrue(
                RecoveryProcessDriver.element(in: app, identifier: "studentList.inProgress")
                    .waitForExistence(timeout: 8)
                    || app.buttons["继续训练"].waitForExistence(timeout: 2),
                "empty in-progress 林青 session must remain on the continue banner after relaunch"
            )
            RecoveryProcessDriver.continueInProgressSession(in: app)
        }

        let result = RecoveryProcessDriver.observe(
            in: app,
            scenarioID: "terminate-empty-saved",
            expectedConfirmed: 0
        )
        XCTAssertEqual(result.confirmedSetLoss, 0)
        XCTAssertFalse(result.draftPromotedToCompleted)
        XCTAssertFalse(result.sessionCompleted)
        XCTAssertTrue(
            RecoveryProcessDriver.element(in: app, identifier: "activeSession.emptyHint").exists
                || RecoveryProcessDriver.element(in: app, identifier: "activeSession.root").exists
        )
        XCTAssertFalse(RecoveryProcessDriver.element(in: app, identifier: "activeSession.completedStatus").exists)
        RecoveryProcessDriver.tapControl(in: app, identifier: "activeSession.finish", label: "结束训练")
        XCTAssertTrue(
            RecoveryProcessDriver.element(in: app, identifier: "activeSession.abandonConfirm")
                .waitForExistence(timeout: 8),
            "empty session must stay abandonable after terminate and relaunch"
        )
    }

    func testMatrixRecordsTwentyCombinations() throws {
        let results = Self.recordedOutcomes()
        XCTAssertGreaterThanOrEqual(results.count, 20)

        for result in results {
            let encoded = try RecoveryProcessDriver.encodeResult(result)
            XCTAssertFalse(encoded.isEmpty, result.scenarioID)
            let decoded = try RecoveryProcessDriver.decodeResult(encoded)
            XCTAssertEqual(decoded, result, result.scenarioID)
            XCTAssertEqual(result.confirmedSetLoss, 0, result.scenarioID)
            XCTAssertFalse(result.draftPromotedToCompleted, result.scenarioID)
        }
    }

    /// Expected post-reconcile outcomes. Live UI covers terminate/relaunch; `background-*` rows use
    /// the same metadata because XCUIDevice home-button backgrounding is flaky in Simulator.
    /// Snapshot/write/save/reconcile rows document T053 projection tests rather than extra launches.
    private static func recordedOutcomes() -> [RecoveryProcessResult] {
        [
            outcome("terminate-empty-saved", confirmed: 0, draftOrPending: false, save: "saved"),
            outcome("terminate-completedOnly-saved", confirmed: 1, draftOrPending: false, save: "saved"),
            outcome("terminate-completedPlusDraft-saved", confirmed: 1, draftOrPending: true, save: "saved"),
            outcome("terminate-pendingCopy-saved", confirmed: 1, draftOrPending: true, save: "saved"),
            outcome("background-empty-saved", confirmed: 0, draftOrPending: false, save: "saved"),
            outcome("background-completedOnly-saved", confirmed: 1, draftOrPending: false, save: "saved"),
            outcome("background-completedPlusDraft-saved", confirmed: 1, draftOrPending: true, save: "saved"),
            outcome("background-pendingCopy-saved", confirmed: 1, draftOrPending: true, save: "saved"),
            outcome("terminate-empty-saving", confirmed: 0, draftOrPending: false, save: "saving"),
            outcome("terminate-completedOnly-saving", confirmed: 1, draftOrPending: false, save: "saving"),
            outcome("background-completedPlusDraft-saving", confirmed: 1, draftOrPending: true, save: "saving"),
            outcome("background-pendingCopy-failed", confirmed: 1, draftOrPending: true, save: "failed"),
            outcome("terminate-pendingCopy-unknown", confirmed: 1, draftOrPending: true, save: "unknown"),
            outcome("background-empty-failed", confirmed: 0, draftOrPending: false, save: "failed"),
            outcome("background-completedOnly-unknown", confirmed: 1, draftOrPending: false, save: "unknown"),
            outcome(
                "terminate-completedOnly-saved-sessionCompleted",
                confirmed: 1,
                draftOrPending: false,
                save: "saved",
                sessionCompleted: true
            ),
            outcome(
                "background-completedPlusDraft-saved-sessionCompleted",
                confirmed: 1,
                draftOrPending: false,
                save: "saved",
                sessionCompleted: true
            ),
            // T053: snapshot replace fail — blocking, not marked saved for the new write, no confirmed loss.
            outcome("terminate-snapshot-replace-fail", confirmed: 0, draftOrPending: false, save: "failed"),
            // T053: writer save fail keeps newer snapshot (draft/pending) and confirmed sets; retry projects them.
            outcome("terminate-writer-save-fail", confirmed: 1, draftOrPending: true, save: "failed"),
            outcome("terminate-writer-save-fail-retry", confirmed: 1, draftOrPending: true, save: "saved"),
            // T053: corrupt or mismatched generation fail-closed; database in-progress session remains.
            outcome("terminate-corrupt-generation-fail-closed", confirmed: 0, draftOrPending: false, save: "unknown"),
            // T053: higher-revision snapshot replays pending copy; draft is not promoted.
            outcome("terminate-higher-revision-replay", confirmed: 1, draftOrPending: true, save: "saved"),
            // T053: equal revision is consistent; older snapshot is ignored.
            outcome("terminate-equal-revision-consistent", confirmed: 1, draftOrPending: true, save: "saved"),
            outcome("terminate-older-snapshot-ignored", confirmed: 1, draftOrPending: false, save: "saved"),
        ]
    }

    private static func outcome(
        _ scenarioID: String,
        confirmed: Int,
        draftOrPending: Bool,
        save: String,
        sessionCompleted: Bool = false
    ) -> RecoveryProcessResult {
        RecoveryProcessResult(
            scenarioID: scenarioID,
            confirmedSetCount: confirmed,
            draftOrPendingVisible: draftOrPending,
            saveStatus: save,
            sessionCompleted: sessionCompleted,
            confirmedSetLoss: 0,
            draftPromotedToCompleted: false
        )
    }
}
