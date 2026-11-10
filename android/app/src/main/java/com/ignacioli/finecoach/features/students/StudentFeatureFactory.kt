package com.ignacioli.finecoach.features.students

import com.ignacioli.finecoach.core.application.AppClock
import com.ignacioli.finecoach.core.application.CreditUseCases
import com.ignacioli.finecoach.core.application.HistoryRepositoryPort
import com.ignacioli.finecoach.core.application.SessionRepositoryPort
import com.ignacioli.finecoach.core.application.StudentRecord
import com.ignacioli.finecoach.core.application.StudentUseCases
import com.ignacioli.finecoach.core.domain.common.StudentID
import java.time.Instant
import java.time.ZoneId

object StudentFeatureFactory {
    fun listViewModel(
        useCases: StudentUseCases,
        showsArchived: Boolean = false,
        sessionRepository: SessionRepositoryPort? = null,
        creditUseCases: CreditUseCases? = null,
        clock: AppClock = AppClock { Instant.now() },
        zoneId: ZoneId = ZoneId.systemDefault(),
    ) = StudentListViewModel(
        useCases = useCases,
        showsArchived = showsArchived,
        sessionRepository = sessionRepository,
        creditUseCases = creditUseCases,
        clock = clock,
        zoneId = zoneId,
    )

    fun editorViewModel(
        mode: StudentEditorMode,
        useCases: StudentUseCases,
        existing: StudentRecord? = null,
    ) = StudentEditorViewModel(
        mode = mode,
        useCases = useCases,
        existing = existing,
    )

    fun detailViewModel(
        studentID: StudentID,
        useCases: StudentUseCases,
        sessionRepository: SessionRepositoryPort,
        creditUseCases: CreditUseCases? = null,
        historyRepository: HistoryRepositoryPort? = null,
        clock: AppClock = AppClock { Instant.now() },
        zoneId: ZoneId = ZoneId.systemDefault(),
    ) = StudentDetailViewModel(
        studentID = studentID,
        useCases = useCases,
        sessionRepository = sessionRepository,
        creditUseCases = creditUseCases,
        historyRepository = historyRepository,
        clock = clock,
        zoneId = zoneId,
    )

    fun deleteViewModel(
        studentID: StudentID,
        useCases: StudentUseCases,
        sessionRepository: SessionRepositoryPort? = null,
        historyRepository: HistoryRepositoryPort? = null,
    ) = DeleteStudentViewModel(
        studentID = studentID,
        useCases = useCases,
        sessionRepository = sessionRepository,
        historyRepository = historyRepository,
    )
}
