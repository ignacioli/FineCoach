package com.ignacioli.finecoach.navigation

import androidx.navigation.NavHostController
import com.ignacioli.finecoach.core.domain.common.*
import java.time.LocalDate

/** Reconstruct only frozen routes and stable IDs; arbitrary strings never reach NavController. */
class S1Navigator(private val nav: NavHostController) {
    fun back() {
        if (Thread.currentThread() != android.os.Looper.getMainLooper().thread) {
            android.os.Handler(android.os.Looper.getMainLooper()).post { back() }; return
        }
        if (!nav.popBackStack()) open(S1Routes.TODAY)
    }
    fun open(route: String) {
        if (Thread.currentThread() != android.os.Looper.getMainLooper().thread) {
            android.os.Handler(android.os.Looper.getMainLooper()).post { open(route) }; return
        }
        val parts = route.split('/')
        when {
            route == S1Routes.TODAY -> nav.navigate(S1Routes.TODAY) { popUpTo(S1Routes.TODAY); launchSingleTop = true }
            route == S1Routes.STUDENTS -> nav.navigate(S1Routes.STUDENTS) { popUpTo(S1Routes.TODAY); launchSingleTop = true }
            route == S1Routes.STUDENT_CREATE -> nav.navigate(S1Routes.STUDENT_CREATE)
            route == S1Routes.RESOURCE_HUB -> nav.navigate(S1Routes.RESOURCE_HUB)
            route == S1Routes.TEMPLATES -> nav.navigate(S1Routes.TEMPLATES)
            route == S1Routes.EXERCISES -> nav.navigate(S1Routes.EXERCISES)
            route == S1Routes.INSIGHTS -> nav.navigate(S1Routes.INSIGHTS)
            parts.size == 5 && parts.take(2) == listOf("appointments", "create") && parts[3] == "student" -> {
                val date = runCatching { LocalDate.parse(parts[2]) }.getOrNull() ?: return
                val id = runCatching { StudentID.parse(parts[4]) }.getOrNull() ?: return
                if (route == S1Routes.insightAppointment(date, id)) nav.navigate(S1Routes.insightAppointment(date, id))
            }
            parts.size == 4 && parts[0] == S1Routes.STUDENTS && parts[2] == S1Routes.STUDENT_TRENDS.substringAfterLast('/') -> {
                val id = runCatching { StudentID.parse(parts[1]) }.getOrNull() ?: return
                val exercise = runCatching { StableExerciseID.parse(parts[3]) }.getOrNull() ?: return
                nav.navigate(S1Routes.insightTrend(id, exercise))
            }
            parts.size in 2..3 && parts[0] == S1Routes.STUDENTS -> {
                val id = runCatching { StudentID.parse(parts[1]) }.getOrNull() ?: return
                when {
                    parts.size == 2 -> nav.navigate(S1Routes.studentDetail(id))
                    parts[2] == S1Routes.STUDENT_EDIT.substringAfterLast('/') -> nav.navigate(S1Routes.studentEdit(id))
                    parts[2] == S1Routes.STUDENT_PACKAGES.substringAfterLast('/') -> nav.navigate(S1Routes.studentPackages(id))
                    parts[2] == S1Routes.STUDENT_HISTORY.substringAfterLast('/') -> nav.navigate(S1Routes.studentHistory(id))
                    parts[2] == S1Routes.STUDENT_TRENDS.substringAfterLast('/') -> nav.navigate(S1Routes.studentTrends(id))
                    parts[2] == S1Routes.STUDENT_BODY.substringAfterLast('/') -> nav.navigate(S1Routes.studentBody(id))
                }
            }
            parts.size == 2 && parts[0] == S1Routes.PACKAGE_DETAIL.substringBefore('/') -> runCatching { CoursePackageID.parse(parts[1]) }.getOrNull()?.let { nav.navigate(S1Routes.packageDetail(it)) }
            parts.size == 2 && parts[0] == S1Routes.SESSION_ACTIVE.substringBefore('/') -> runCatching { SessionID.parse(parts[1]) }.getOrNull()?.let { nav.navigate(S1Routes.activeSession(it)) { launchSingleTop = true } }
            parts.size == 2 && parts[0] == S1Routes.HISTORY_DETAIL.substringBefore('/') -> runCatching { SessionID.parse(parts[1]) }.getOrNull()?.let { nav.navigate(S1Routes.historyDetail(it)) }
            parts.size == 2 && parts[0] == S1Routes.TEMPLATE_DETAIL.substringBefore('/') -> runCatching { TemplateID.parse(parts[1]) }.getOrNull()?.let { nav.navigate(S1Routes.templateDetail(it)) }
        }
    }
}
