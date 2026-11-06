package com.ignacioli.finecoach.navigation

import com.ignacioli.finecoach.core.domain.common.CoursePackageID
import com.ignacioli.finecoach.core.domain.common.SessionID
import com.ignacioli.finecoach.core.domain.common.StudentID
import com.ignacioli.finecoach.core.domain.common.TemplateID

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
    const val PACKAGE_DETAIL = "packages/{$ARG_PACKAGE_ID}"
    const val SESSION_ACTIVE = "session/{$ARG_SESSION_ID}"
    const val TEMPLATES = "templates"
    const val TEMPLATE_DETAIL = "templates/{$ARG_TEMPLATE_ID}"
    const val EXERCISES = "exercises"
    const val HISTORY_DETAIL = "history/{$ARG_SESSION_ID}"

    val allPatterns: Set<String> = setOf(
        TODAY,
        STUDENTS,
        STUDENT_CREATE,
        STUDENT_DETAIL,
        STUDENT_EDIT,
        STUDENT_PACKAGES,
        STUDENT_HISTORY,
        PACKAGE_DETAIL,
        SESSION_ACTIVE,
        TEMPLATES,
        TEMPLATE_DETAIL,
        EXERCISES,
        HISTORY_DETAIL,
    )

    fun studentDetail(studentID: StudentID): String = "students/${studentID.value}"
    fun studentEdit(studentID: StudentID): String = "students/${studentID.value}/edit"
    fun studentPackages(studentID: StudentID): String = "students/${studentID.value}/packages"
    fun studentHistory(studentID: StudentID): String = "students/${studentID.value}/history"
    fun packageDetail(coursePackageID: CoursePackageID): String = "packages/${coursePackageID.value}"
    fun activeSession(sessionID: SessionID): String = "session/${sessionID.value}"
    fun templateDetail(templateID: TemplateID): String = "templates/${templateID.value}"
    fun historyDetail(sessionID: SessionID): String = "history/${sessionID.value}"
}
