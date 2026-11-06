package com.ignacioli.finecoach

import com.ignacioli.finecoach.core.domain.common.StudentID
import com.ignacioli.finecoach.core.domain.common.StudentLifecycle
import com.ignacioli.finecoach.core.domain.common.StudentSex
import com.ignacioli.finecoach.core.domain.student.StudentDeletionPolicy
import com.ignacioli.finecoach.core.domain.student.StudentDomainError
import com.ignacioli.finecoach.core.domain.student.StudentDomainException
import com.ignacioli.finecoach.core.domain.student.StudentDraft
import com.ignacioli.finecoach.core.domain.student.ValidatedText
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class StudentDomainTests {
    private val now: Instant = Instant.parse("2026-11-06T06:00:00Z")
    private val firstID: StudentID = StudentID.parse("11111111-1111-4111-8111-111111111111")
    private val secondID: StudentID = StudentID.parse("22222222-2222-4222-8222-222222222222")

    @Test
    fun requiredFieldsRejectBlankDisplayNameAndMissingSex() {
        assertDomainError(StudentDomainError.emptyText) {
            StudentDraft(displayName = "   ", sex = StudentSex.female).makeStudent(firstID, now)
        }
        assertDomainError(StudentDomainError.invalidState) {
            StudentDraft(displayName = "Coach Student", sex = null).makeStudent(firstID, now)
        }
    }

    @Test
    fun optionalFieldsPersistWhenFilledAndClearWhenBlank() {
        val filled = StudentDraft(
            displayName = "  Coach Student  ",
            sex = StudentSex.female,
            trainingGoal = " Build baseline strength ",
            injuryNotes = " Synthetic note: keep movement smooth. ",
            privateCoachNote = " evening slot ",
            phone = " 000-0000-0000 ",
            wechatID = " coach_student ",
        ).makeStudent(firstID, now)

        assertEquals("Coach Student", filled.displayName.value)
        assertEquals("Build baseline strength", filled.trainingGoal?.value)
        assertEquals("Synthetic note: keep movement smooth.", filled.injuryNotes?.value)
        assertEquals("evening slot", filled.privateCoachNote?.value)
        assertEquals("000-0000-0000", filled.phone?.value)
        assertEquals("coach_student", filled.wechatID?.value)
        assertEquals(StudentLifecycle.active, filled.lifecycle)

        val cleared = filled.updateFromDraft(
            StudentDraft(displayName = "Coach Student", sex = StudentSex.undisclosed),
            now.plusSeconds(60),
        )
        assertEquals(filled.studentID, cleared.studentID)
        assertEquals(filled.createdAtUTC, cleared.createdAtUTC)
        assertEquals(now.plusSeconds(60), cleared.updatedAtUTC)
        assertNull(cleared.trainingGoal)
        assertNull(cleared.injuryNotes)
        assertNull(cleared.privateCoachNote)
        assertNull(cleared.phone)
        assertNull(cleared.wechatID)
    }

    @Test
    fun sameDisplayNameCanCoexistWithDistinctStableIDs() {
        val first = StudentDraft(displayName = "Same Name", sex = StudentSex.other).makeStudent(firstID, now)
        val second = StudentDraft(displayName = "Same Name", sex = StudentSex.female).makeStudent(secondID, now)

        assertEquals(first.displayName, second.displayName)
        assertNotEquals(first.studentID, second.studentID)

        val renamed = first.updateFromDraft(
            StudentDraft(displayName = "Renamed", sex = StudentSex.other),
            now.plusSeconds(10),
        )
        assertEquals(first.studentID, renamed.studentID)
        assertEquals("Renamed", renamed.displayName.value)
    }

    @Test
    fun textOverUtf8CeilingIsRejectedBeforeSave() {
        val oversized = String(CharArray(ValidatedText.maximumUTF8Bytes + 1) { 'a' })

        assertDomainError(StudentDomainError.textTooLong) {
            StudentDraft(displayName = oversized, sex = StudentSex.male).makeStudent(firstID, now)
        }
        assertDomainError(StudentDomainError.textTooLong) {
            StudentDraft(displayName = "Coach Student", sex = StudentSex.male, injuryNotes = oversized)
                .makeStudent(firstID, now)
        }
    }

    @Test
    fun allSexCasesAreAccepted() {
        StudentSex.entries.forEach { sex ->
            val student = StudentDraft(displayName = "Any Student", sex = sex).makeStudent(firstID, now)
            assertEquals(sex, student.sex)
        }
        assertEquals(
            listOf("male", "female", "other", "undisclosed"),
            StudentSex.entries.map { it.wireValue },
        )
    }

    @Test
    fun archiveRestoreAndIllegalTransitions() {
        val active = StudentDraft(displayName = "Coach Student", sex = StudentSex.male).makeStudent(firstID, now)
        assertTrue(active.canStartSession())

        val archived = active.archived(now.plusSeconds(5))
        assertEquals(StudentLifecycle.archived, archived.lifecycle)
        assertFalse(archived.canStartSession())
        assertEquals(active.studentID, archived.studentID)

        assertDomainError(StudentDomainError.invalidState) {
            archived.archived(now)
        }

        val restored = archived.restored(now.plusSeconds(10))
        assertEquals(StudentLifecycle.active, restored.lifecycle)
        assertTrue(restored.canStartSession())

        assertDomainError(StudentDomainError.invalidState) {
            active.restored(now)
        }
    }

    @Test
    fun deletionRequiresMatchingDisplayNameAndNoInProgressSession() {
        val student = StudentDraft(displayName = "Coach Student", sex = StudentSex.female).makeStudent(firstID, now)

        assertDomainError(StudentDomainError.invalidState) {
            StudentDeletionPolicy.ensureCanDelete(hasInProgressSession = true)
        }
        StudentDeletionPolicy.ensureCanDelete(hasInProgressSession = false)

        assertDomainError(StudentDomainError.invalidState) {
            StudentDeletionPolicy.confirmDisplayName(expected = student.displayName, typed = "Coach  Student")
        }
        assertDomainError(StudentDomainError.invalidState) {
            StudentDeletionPolicy.confirmDisplayName(expected = student.displayName, typed = "")
        }
        StudentDeletionPolicy.confirmDisplayName(expected = student.displayName, typed = " Coach Student ")
    }

    @Test
    fun nfcNormalizationDoesNotChangeStableIdentity() {
        val composed = StudentDraft(displayName = "Cafe\u00E9", sex = StudentSex.female).makeStudent(firstID, now)
        val decomposed = composed.updateFromDraft(
            StudentDraft(displayName = "Cafe\u0065\u0301", sex = StudentSex.female),
            now.plusSeconds(1),
        )

        assertEquals(composed.studentID, decomposed.studentID)
        assertEquals(composed.displayName, decomposed.displayName)
        assertEquals("Cafe\u00E9", decomposed.displayName.value)
    }

    private fun assertDomainError(expected: StudentDomainError, block: () -> Unit) {
        try {
            block()
            fail("Expected StudentDomainException($expected)")
        } catch (error: StudentDomainException) {
            assertEquals(expected, error.code)
        }
    }
}
