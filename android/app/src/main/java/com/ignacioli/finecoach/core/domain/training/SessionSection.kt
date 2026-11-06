package com.ignacioli.finecoach.core.domain.training

import com.ignacioli.finecoach.core.domain.common.*
import java.time.Instant

/** Typed polymorphic owner; maps to SectionRecord's exclusive owner columns. */
sealed interface SectionOwner {
    data class Session(val id: SessionID) : SectionOwner
    data class Template(val id: TemplateID) : SectionOwner
}

data class SessionSection(
    val sectionID: SectionID,
    val owner: SectionOwner,
    val name: NormalizedName,
    val orderIndex: UInt,
) {
    fun renamed(name: String): SessionSection = copy(name = parseDomainName(name, "sectionName"))

    companion object {
        fun create(id: SectionID, owner: SectionOwner, name: String, orderIndex: UInt): SessionSection =
            SessionSection(id, owner, parseDomainName(name, "sectionName"), orderIndex)
    }
}

sealed interface SessionSectionAxisItem {
    data class Section(val id: SectionID) : SessionSectionAxisItem
    // SessionExerciseID and TemplateExerciseID share the UUID wire shape, not their domain type.
    data class Exercise(val id: String) : SessionSectionAxisItem
}

sealed interface SessionSectionDeletionDisposition {
    data class MoveExercisesTo(val sectionID: SectionID?) : SessionSectionDeletionDisposition
    data object DeleteWithExercises : SessionSectionDeletionDisposition
}

/** One shared implementation for Session exercises and template planned exercises. */
internal class SectionLayout<E>(
    val owner: SectionOwner,
    val sections: List<SessionSection>,
    val exercises: List<E>,
    val id: (E) -> String,
    val order: (E) -> UInt,
    val section: (E) -> SectionID?,
    val relocate: (E, UInt, SectionID?) -> E,
) {
    init {
        if (sections.any { it.owner != owner } || sections.map { it.sectionID }.toSet().size != sections.size ||
            exercises.map(id).toSet().size != exercises.size
        ) fail(DomainError.invalidState)
        if (exercises.any { item -> section(item)?.let { target -> sections.none { it.sectionID == target } } == true }) {
            fail(DomainError.invalidState)
        }
        val indices = sections.map { it.orderIndex } + exercises.map(order)
        if (indices.toSet().size != indices.size) fail(DomainError.conflict)
    }

    fun axis(): List<SessionSectionAxisItem> = (
        sections.map { it.orderIndex to SessionSectionAxisItem.Section(it.sectionID) } +
            exercises.map { order(it) to SessionSectionAxisItem.Exercise(id(it)) }
        ).sortedBy { it.first }.map { it.second }

    fun reordered(axis: List<SessionSectionAxisItem>): Pair<List<SessionSection>, List<E>> {
        val current = this.axis()
        if (axis.size != current.size || axis.toSet() != current.toSet()) fail(DomainError.invalidState)
        val indices = axis.withIndex().associate { it.value to it.index.toUInt() }
        return sections.map { it.copy(orderIndex = indices.getValue(SessionSectionAxisItem.Section(it.sectionID))) }
            .sortedBy { it.orderIndex } to exercises.map {
            relocate(it, indices.getValue(SessionSectionAxisItem.Exercise(id(it))), section(it))
        }.sortedBy(order)
    }

    fun normalized(): Pair<List<SessionSection>, List<E>> = reordered(axis())

    fun addingSection(id: SectionID, name: String): Pair<List<SessionSection>, List<E>> {
        if (sections.any { it.sectionID == id }) fail(DomainError.conflict)
        val (headers, rows) = normalized()
        return (headers + SessionSection.create(id, owner, name, (headers.size + rows.size).toUInt())) to rows
    }

    fun renamingSection(id: SectionID, name: String): Pair<List<SessionSection>, List<E>> {
        requireSection(id)
        return sections.map { if (it.sectionID == id) it.renamed(name) else it } to exercises
    }

    fun movingExercise(exerciseID: String, target: SectionID?): Pair<List<SessionSection>, List<E>> {
        requireTarget(target)
        if (exercises.none { id(it) == exerciseID }) fail(DomainError.notFound)
        return withRows(exercises.map { if (id(it) == exerciseID) relocate(it, order(it), target) else it }).normalized()
    }

    fun deletingSection(
        sectionID: SectionID,
        disposition: SessionSectionDeletionDisposition?,
    ): Pair<List<SessionSection>, List<E>> {
        // null models a dismissed choice sheet: no validation, normalization or mutation.
        if (disposition == null) return sections to exercises
        requireSection(sectionID)
        val members = exercises.filter { section(it) == sectionID }.map(id).toSet()
        val rows = when (disposition) {
            is SessionSectionDeletionDisposition.MoveExercisesTo -> {
                if (disposition.sectionID == sectionID) fail(DomainError.invalidState)
                requireTarget(disposition.sectionID)
                exercises.map {
                    if (id(it) in members) relocate(it, order(it), disposition.sectionID) else it
                }
            }
            SessionSectionDeletionDisposition.DeleteWithExercises -> exercises.filterNot { id(it) in members }
        }
        return SectionLayout(owner, sections.filterNot { it.sectionID == sectionID }, rows, id, order, section, relocate)
            .normalized()
    }

    private fun withRows(rows: List<E>): SectionLayout<E> = SectionLayout(owner, sections, rows, id, order, section, relocate)

    private fun requireSection(id: SectionID) {
        if (sections.none { it.sectionID == id }) fail(DomainError.notFound)
    }

    private fun requireTarget(id: SectionID?) {
        if (id != null && sections.none { it.sectionID == id }) fail(DomainError.invalidState)
    }
}

/** Pure working content; persistence/revision checks belong to T008. */
data class SectionedSession(val session: Session, val sections: List<SessionSection> = emptyList()) {
    internal fun layout(): SectionLayout<SessionExercise> {
        if (session.exercises.any { it.sessionID != session.sessionID }) fail(DomainError.invalidState)
        return SectionLayout(
            SectionOwner.Session(session.sessionID), sections, session.exercises,
            { it.sessionExerciseID.value }, { it.orderIndex }, { it.sectionID },
            { row, index, target -> row.copy(orderIndex = index, sectionID = target) },
        )
    }

    fun addingSection(id: SectionID, name: String, nowUTC: Instant): SectionedSession =
        changed(layout().addingSection(id, name), nowUTC)

    fun renamingSection(id: SectionID, name: String, nowUTC: Instant): SectionedSession =
        changed(layout().renamingSection(id, name), nowUTC)

    fun movingExercise(id: SessionExerciseID, target: SectionID?, nowUTC: Instant): SectionedSession =
        changed(layout().movingExercise(id.value, target), nowUTC)

    fun reordering(axis: List<SessionSectionAxisItem>, nowUTC: Instant): SectionedSession =
        changed(layout().reordered(axis), nowUTC)

    fun deletingSection(
        id: SectionID,
        disposition: SessionSectionDeletionDisposition?,
        nowUTC: Instant,
    ): SectionedSession {
        if (disposition == null) return this
        return changed(layout().deletingSection(id, disposition), nowUTC)
    }

    private fun changed(content: Pair<List<SessionSection>, List<SessionExercise>>, nowUTC: Instant): SectionedSession {
        if (session.state != SessionState.inProgress) fail(DomainError.invalidState)
        if (session.revision.value == ULong.MAX_VALUE) fail(DomainError.invalidState, "revision")
        return SectionedSession(
            session.copy(
                exercises = content.second, revision = Revision(session.revision.value + 1u),
                updatedAtUTC = nowUTC, lastCheckpointUTC = nowUTC,
            ),
            content.first,
        )
    }
}
