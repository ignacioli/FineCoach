// fictional-data: invented students, exercise snapshots and summary notes only.
package com.ignacioli.finecoach

import com.ignacioli.finecoach.core.application.*
import com.ignacioli.finecoach.core.domain.common.*
import com.ignacioli.finecoach.storage.FineCoachDatabaseFactory
import java.time.Instant
import java.util.UUID
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class HistoryRepositoryTests {
    private lateinit var f: T009Fixture
    @Before fun prepare() { f = T009Fixture() }
    @After fun close() { f.close() }

    @Test fun onlyNonemptyCompletedSessionsAppearAndMostRecentIsFirst() = f.test {
        val old = completeAt("2026-11-01T10:00:00Z")
        val recent = completeAt("2026-11-08T10:00:00Z")
        val active = f.content(completed = false)
        f.reopen()
        val rows = f.ok(f.history.list(HistoryQuery(f.studentID)))
        assertEquals(listOf(recent.sessionID, old.sessionID), rows.map { it.sessionID })
        assertNull(f.ok(f.history.detail(active.session.sessionID)))
        assertEquals(recent.sessionID, rows.first().sessionID)
    }

    @Test fun noHistoryAndNoFilterMatchesAreDistinctAndFiltersCanBeCleared() = f.test {
        assertEquals(HistoryEmptyState.noHistory, f.ok(f.historyCases.clearFilters(f.studentID)).emptyState)
        val completed = completeAt("2026-11-08T10:00:00Z")
        val absentFocus = setOf(BodyPart.entries.last())
        assertEquals(HistoryEmptyState.noMatches,
            f.ok(f.historyCases.list(HistoryQuery(f.studentID, trainingFocus = absentFocus))).emptyState)
        val cleared = f.ok(f.historyCases.clearFilters(f.studentID))
        assertNull(cleared.emptyState)
        assertEquals(listOf(completed.sessionID), cleared.records.map { it.sessionID })
    }

    @Test fun sevenThirtyNinetyDayWindowsIncludeLocalBoundaryAndExcludeAdjacentDays() = f.test {
        // DST ends on 2026-11-01; each preset is calendar days, not N * 24 hours.
        val today = java.time.LocalDate.parse("2026-11-08")
        for (window in HistoryWindowDays.entries) {
            val first = today.minusDays(window.days.toLong() - 1).atStartOfDay(f.zone).toInstant()
            val last = today.plusDays(1).atStartOfDay(f.zone).toInstant()
            val before = completeAt(first.minusNanos(1).toString())
            val includedStart = completeAt(first.toString())
            val includedEnd = completeAt(last.minusNanos(1).toString())
            val after = completeAt(last.toString())
            f.now = Instant.parse("2026-11-08T20:00:00Z")
            val rows = f.ok(f.history.list(HistoryQuery(f.studentID, window)))
            val ids = rows.map { it.sessionID }
            assertTrue(includedStart.sessionID in ids)
            assertTrue(includedEnd.sessionID in ids)
            assertFalse(before.sessionID in ids)
            assertFalse(after.sessionID in ids)
            assertEquals(rows.map { it.completedAtUTC }.sortedDescending(), rows.map { it.completedAtUTC })
        }
    }

    @Test fun orderingUsesInstantIncludingFractionalSecondRatherThanCanonicalText() = f.test {
        val fractional = completeAt("2026-11-08T10:00:00.100Z")
        val whole = completeAt("2026-11-08T10:00:00Z")
        f.reopen()
        assertEquals(listOf(fractional.sessionID, whole.sessionID),
            f.ok(f.history.list(HistoryQuery())).map { it.sessionID })
    }

    @Test fun focusUsesAnyOverlapAndCombinesWithExerciseAndStudentFilters() = f.test {
        val source = StableExerciseID.parse("fictional-history-source")
        val other = StableExerciseID.parse("fictional-other-source")
        val matching = completeAt("2026-11-08T10:00:00Z", source)
        val nonmatching = completeAt("2026-11-07T10:00:00Z", other)
        val focus = setOf(BodyPart.entries.first())
        f.ok(f.historyCases.saveFocusEdit(UpdateHistoryTrainingFocusCommand(matching.sessionID, matching.revision, focus)))
        f.ok(f.historyCases.saveFocusEdit(UpdateHistoryTrainingFocusCommand(nonmatching.sessionID, nonmatching.revision, focus)))
        val filter = HistoryQuery(f.studentID, HistoryWindowDays.days7,
            focus + BodyPart.entries.last(), setOf(source))
        f.now = Instant.parse("2026-11-08T20:00:00Z")
        assertEquals(listOf(matching.sessionID), f.ok(f.history.list(filter)).map { it.sessionID })
        assertTrue(f.ok(f.history.list(filter.copy(studentID = f.ids.newStudentID()))).isEmpty())
        assertTrue(f.ok(f.history.list(filter.copy(trainingFocus = setOf(BodyPart.entries.last())))).isEmpty())
        assertEquals(2, f.ok(f.history.list(HistoryQuery())).size)
    }

    @Test fun detailKeepsSnapshotAndPrivateNotesWithoutConsultingCatalog() = f.test {
        val source = StableExerciseID.parse("fictional-missing-catalog-source")
        val completed = completeAt("2026-11-08T10:00:00Z", source)
        f.ok(f.historyCases.saveSummary(SaveCompletedSessionSummaryCommand(completed.sessionID, completed.revision,
            setOf(BodyPart.entries.first()), "虚构公开总结", "虚构私密备注", f.now)))
        f.reopen()
        val detail = f.ok(f.historyCases.detail(completed.sessionID))
        assertTrue(detail.content.exercises.single().displayNameSnapshot == "虚构快照动作")
        assertTrue(detail.content.exercises.single().actionPrivateNote == "虚构动作私密备注")
        assertTrue(detail.content.session.studentFacingSummary == "虚构公开总结")
        assertTrue(detail.content.session.privateCoachNote == "虚构私密备注")
        assertEquals(source, detail.content.exercises.single().sourceID)
        assertEquals(1, detail.statistics.completedSetCount)
        assertEquals(SessionCreditSettlementNote.noActivePackage, detail.creditNote!!.note)
        assertEquals(0L, f.count("exercise_catalog"))
    }

    @Test fun focusEditPreservesIdentityContentAndLedgerWithoutSecondSettlement() = f.test {
        val pkg = f.coursePackage()
        val completed = completeAt("2026-11-08T10:00:00Z")
        f.ok(f.finisher.debitAdhoc(completed.sessionID, pkg.coursePackageID))
        val before = f.ok(f.sessions.loadContent(completed.sessionID))!!
        val focus = setOf(BodyPart.entries.first())
        f.ok(f.historyCases.saveFocusEdit(UpdateHistoryTrainingFocusCommand(completed.sessionID, before.session.revision, focus)))
        f.reopen()
        val after = f.ok(f.sessions.loadContent(completed.sessionID))!!
        assertEquals(completed.sessionID, after.session.sessionID)
        assertEquals(before.session.completedAtUTC, after.session.completedAtUTC)
        assertEquals(before.session.studentID, after.session.studentID)
        assertTrue(before.exercises == after.exercises)
        assertEquals(focus, after.session.trainingFocus)
        assertEquals(before.session.revision.value + 1uL, after.session.revision.value)
        assertEquals(1L, f.count("credit_adjustments"))
        assertEquals(1L, f.ok(f.credits.balance(f.studentID, pkg.coursePackageID)))
    }

    @Test fun summaryFailureRetainsOriginalAndSameInputCanBeRetriedAfterReopen() = f.test {
        val completed = completeAt("2026-11-08T10:00:00Z")
        val command = SaveCompletedSessionSummaryCommand(completed.sessionID, completed.revision,
            setOf(BodyPart.entries.first()), "虚构总结", "虚构私密备注", f.now)
        f.failWrites("sessions", "UPDATE")
        f.error(ApplicationErrorCode.persistenceFailed, f.historyCases.saveSummary(command))
        val original = f.ok(f.sessions.find(completed.sessionID))!!
        assertEquals(completed.revision, original.revision)
        assertNull(original.studentFacingSummary)
        assertNull(original.privateCoachNote)
        f.clearFailure(); f.reopen()
        val saved = f.ok(f.historyCases.saveSummary(command))
        f.reopen()
        val persisted = f.ok(f.sessions.find(completed.sessionID))!!
        assertEquals(saved.revision, persisted.revision)
        assertTrue(persisted.studentFacingSummary == command.studentFacingSummary)
        assertTrue(persisted.privateCoachNote == command.privateCoachNote)
        assertEquals(0L, f.count("credit_adjustments"))
    }

    @Test fun staleFocusEditAndNoncompletedEditRejectWithoutMutation() = f.test {
        val completed = completeAt("2026-11-08T10:00:00Z")
        val focus = setOf(BodyPart.entries.first())
        f.ok(f.historyCases.saveFocusEdit(UpdateHistoryTrainingFocusCommand(completed.sessionID, completed.revision, focus)))
        f.error(ApplicationErrorCode.staleRevision, f.historyCases.saveFocusEdit(
            UpdateHistoryTrainingFocusCommand(completed.sessionID, completed.revision, emptySet())))
        val active = f.content(completed = false)
        f.error(ApplicationErrorCode.invalidState, f.historyCases.saveFocusEdit(
            UpdateHistoryTrainingFocusCommand(active.session.sessionID, active.session.revision, focus)))
        assertEquals(focus, f.ok(f.sessions.find(completed.sessionID))!!.trainingFocus)
        assertTrue(f.ok(f.sessions.find(active.session.sessionID))!!.trainingFocus.isEmpty())
    }

    @Test fun midFocusWriteFailureRollsBackMetadataAndFocusRows() = f.test {
        val completed = completeAt("2026-11-08T10:00:00Z")
        val command = UpdateHistoryTrainingFocusCommand(completed.sessionID, completed.revision, setOf(BodyPart.entries.first()))
        f.failWrites("session_training_focus", "INSERT")
        f.error(ApplicationErrorCode.persistenceFailed, f.historyCases.saveFocusEdit(command))
        f.clearFailure(); f.reopen()
        val original = f.ok(f.sessions.find(completed.sessionID))!!
        assertEquals(completed.revision, original.revision)
        assertTrue(original.trainingFocus.isEmpty())
        f.ok(f.historyCases.saveFocusEdit(command))
        assertEquals(command.trainingFocus, f.ok(f.sessions.find(completed.sessionID))!!.trainingFocus)
    }

    @Test fun noChangeFocusEditDoesNotIncrementRevisionOrWriteLedger() = f.test {
        val completed = completeAt("2026-11-08T10:00:00Z")
        f.ok(f.historyCases.saveFocusEdit(UpdateHistoryTrainingFocusCommand(completed.sessionID, completed.revision, emptySet())))
        assertEquals(completed.revision, f.ok(f.sessions.find(completed.sessionID))!!.revision)
        assertEquals(0L, f.count("credit_adjustments"))
    }

    @Test fun oldGenerationRejectsHistoryAndNotesAndDatabaseReopenRequiresNewObjects() = f.test {
        val completed = completeAt("2026-11-08T10:00:00Z")
        val old = f.history
        f.db.openHelper.writableDatabase.execSQL("UPDATE store_metadata SET value = ? WHERE `key` = ?",
            arrayOf(UUID.randomUUID().toString(), FineCoachDatabaseFactory.GENERATION_KEY))
        f.error(ApplicationErrorCode.incompatibleInput, old.list(HistoryQuery()))
        f.error(ApplicationErrorCode.incompatibleInput, old.updateTrainingFocus(
            UpdateHistoryTrainingFocusCommand(completed.sessionID, completed.revision, setOf(BodyPart.entries.first()))))
        f.error(ApplicationErrorCode.incompatibleInput, old.find(completed.sessionID))
        f.reopen()
        assertEquals(completed.sessionID, f.ok(f.history.list(HistoryQuery())).single().sessionID)
    }

    @Test fun pendingInLegacyCompletedRecordNeverCountsAsEffectiveTraining() = f.test {
        val content = f.content(pending = true)
        // A legacy/imported row may retain unresolved sets. Projection still excludes them from statistics.
        f.db.openHelper.writableDatabase.execSQL("UPDATE sessions SET state = 'completed', completedAtUTC = ? WHERE id = ?",
            arrayOf(f.now.toString(), content.session.sessionID.value))
        f.reopen()
        val detail = f.ok(f.historyCases.detail(content.session.sessionID))
        assertEquals(2, detail.content.exercises.single().sets.size)
        assertEquals(1, detail.statistics.completedSetCount)
        assertEquals(0, detail.statistics.ordinaryTrainingVolume!!.decimal.compareTo(java.math.BigDecimal("80")))
        assertEquals(listOf(content.session.sessionID), f.ok(f.history.list(HistoryQuery())).map { it.sessionID })
    }

    @Test fun malformedEmptyCompletedRecordIsExcludedFromHistoryAndDetail() = f.test {
        val content = f.content(completed = false)
        f.db.openHelper.writableDatabase.execSQL("UPDATE sessions SET state = 'completed', completedAtUTC = ? WHERE id = ?",
            arrayOf(f.now.toString(), content.session.sessionID.value))
        assertTrue(f.ok(f.history.list(HistoryQuery())).isEmpty())
        assertNull(f.ok(f.history.detail(content.session.sessionID)))
        f.error(ApplicationErrorCode.notFound, f.historyCases.detail(content.session.sessionID))
    }

    private suspend fun completeAt(time: String, sourceID: StableExerciseID? = null): SessionRecord {
        f.now = Instant.parse(time)
        return f.finish(f.content(sourceID = sourceID)).session
    }
}
