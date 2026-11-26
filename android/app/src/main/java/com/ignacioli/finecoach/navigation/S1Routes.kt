package com.ignacioli.finecoach.navigation

import com.ignacioli.finecoach.core.domain.common.CoursePackageID
import com.ignacioli.finecoach.core.domain.common.SessionID
import com.ignacioli.finecoach.core.domain.common.StudentID
import com.ignacioli.finecoach.core.domain.common.TemplateID
import com.ignacioli.finecoach.core.domain.common.StableExerciseID
import java.time.LocalDate

object S1Routes {
    const val ARG_STUDENT_ID = "studentID"
    const val ARG_PACKAGE_ID = "coursePackageID"
    const val ARG_SESSION_ID = "sessionID"
    const val ARG_TEMPLATE_ID = "templateID"

    const val TODAY = "today"
    const val STUDENTS = "students"
    const val STUDENT_CREATE = "students/create"
    const val STUDENT_DETAIL = "students/{$ARG_STUDENT_ID}"
    const val STUDENT_EDIT = "students/{$ARG_STUDENT_ID}/edit"
    const val STUDENT_PACKAGES = "students/{$ARG_STUDENT_ID}/packages"
    const val STUDENT_HISTORY = "students/{$ARG_STUDENT_ID}/history"
    const val STUDENT_TRENDS = "students/{$ARG_STUDENT_ID}/trends"
    const val STUDENT_BODY = "students/{$ARG_STUDENT_ID}/body"
    const val PACKAGE_DETAIL = "packages/{$ARG_PACKAGE_ID}"
    const val SESSION_ACTIVE = "session/{$ARG_SESSION_ID}"
    const val RESOURCE_HUB = "resources"
    const val TEMPLATES = "templates"
    const val TEMPLATE_DETAIL = "templates/{$ARG_TEMPLATE_ID}"
    const val EXERCISES = "exercises"
    const val HISTORY_DETAIL = "history/{$ARG_SESSION_ID}"
    const val INSIGHTS = "insights"
    const val INSIGHT_APPOINTMENT = "appointments/create/{date}/student/{$ARG_STUDENT_ID}"
    const val INSIGHT_TREND = "students/{$ARG_STUDENT_ID}/trends/{exerciseID}"

    val allPatterns: Set<String> = setOf(
        TODAY,
        STUDENTS,
        STUDENT_CREATE,
        STUDENT_DETAIL,
        STUDENT_EDIT,
        STUDENT_PACKAGES,
        STUDENT_HISTORY,
        STUDENT_TRENDS,
        STUDENT_BODY,
        PACKAGE_DETAIL,
        SESSION_ACTIVE,
        RESOURCE_HUB,
        TEMPLATES,
        TEMPLATE_DETAIL,
        EXERCISES,
        HISTORY_DETAIL,
        INSIGHTS,
        INSIGHT_APPOINTMENT,
        INSIGHT_TREND,
    )

    fun studentDetail(studentID: StudentID): String = "students/${studentID.value}"
    fun studentEdit(studentID: StudentID): String = "students/${studentID.value}/edit"
    fun studentPackages(studentID: StudentID): String = "students/${studentID.value}/packages"
    fun studentHistory(studentID: StudentID): String = "students/${studentID.value}/history"
    fun studentTrends(studentID: StudentID): String = "students/${studentID.value}/trends"
    fun studentBody(studentID: StudentID): String = "students/${studentID.value}/body"
    fun insightTrend(studentID: StudentID, exerciseID: StableExerciseID): String = "students/${studentID.value}/trends/${exerciseID.value}"
    fun insightAppointment(date: LocalDate, studentID: StudentID): String = "appointments/create/$date/student/${studentID.value}"
    fun packageDetail(coursePackageID: CoursePackageID): String = "packages/${coursePackageID.value}"
    fun activeSession(sessionID: SessionID): String = "session/${sessionID.value}"
    fun templateDetail(templateID: TemplateID): String = "templates/${templateID.value}"
    fun historyDetail(sessionID: SessionID): String = "history/${sessionID.value}"
}
