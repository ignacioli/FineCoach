package com.ignacioli.finecoach.features.packages

import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import com.ignacioli.finecoach.core.application.AppClock
import com.ignacioli.finecoach.core.application.CreditUseCases
import com.ignacioli.finecoach.core.application.StudentUseCases
import com.ignacioli.finecoach.core.domain.common.CoursePackageID
import com.ignacioli.finecoach.core.domain.common.StudentID
import com.ignacioli.finecoach.navigation.S1Routes
import java.time.ZoneId

/**
 * Student course packages. Editor, replacement confirmation, ending, and manual
 * adjustment stay on [S1Routes.STUDENT_PACKAGES] because that contract has no
 * separate patterns for them. Opening a package's ledger emits
 * [S1Routes.packageDetail] and does not invent a route.
 */
sealed interface PackagePage {
    data object List : PackagePage
    data object Editor : PackagePage
    data class Manual(val coursePackageID: CoursePackageID) : PackagePage
}

@Composable
fun CoursePackagesFeature(
    studentID: StudentID,
    useCases: CreditUseCases,
    clock: AppClock,
    zoneID: ZoneId,
    onNavigate: (String) -> Unit,
    onBack: () -> Unit,
    students: StudentUseCases? = null,
    initialPage: PackagePage = PackagePage.List,
) {
    var page by rememberSaveableState(initialPage)
    when (val current = page) {
        PackagePage.List -> CoursePackageListScreen(
            studentID = studentID,
            useCases = useCases,
            zoneID = zoneID,
            onBack = onBack,
            onCreate = { page = PackagePage.Editor },
            onManual = { page = PackagePage.Manual(it) },
            onOpenPackage = { onNavigate(S1Routes.packageDetail(it)) },
            students = students,
        )
        PackagePage.Editor -> CoursePackageEditorScreen(
            studentID = studentID,
            useCases = useCases,
            clock = clock,
            zoneID = zoneID,
            onBack = { page = PackagePage.List },
            onSaved = { page = PackagePage.List },
        )
        is PackagePage.Manual -> ManualCreditAdjustmentScreen(
            coursePackageID = current.coursePackageID,
            useCases = useCases,
            onBack = { page = PackagePage.List },
            onSaved = { page = PackagePage.List },
        )
    }
}

@Composable
private fun rememberSaveableState(initialPage: PackagePage): MutableState<PackagePage> {
    // These pages are not route arguments. Remember them for this composition
    // only; a process restore returns to the list, which reloads from Room.
    return remember { mutableStateOf(initialPage) }
}

/**
 * Hosts the two package routes that already exist. The student id stays with
 * the host because [S1Routes.PACKAGE_DETAIL] carries only the package id and
 * the frozen use cases address a package through its student.
 */
@Composable
fun PackageRouteHost(
    studentID: StudentID,
    useCases: CreditUseCases,
    clock: AppClock,
    zoneID: ZoneId,
    onExit: () -> Unit,
    students: StudentUseCases? = null,
) {
    var route by rememberSaveable(studentID) { mutableStateOf(S1Routes.studentPackages(studentID)) }
    val detailId = packageIdFromDetailRoute(route)
    if (detailId == null) {
        CoursePackagesFeature(
            studentID = studentID,
            useCases = useCases,
            clock = clock,
            zoneID = zoneID,
            onNavigate = { requested ->
                if (packageIdFromDetailRoute(requested) != null) route = requested
            },
            onBack = onExit,
            students = students,
        )
    } else {
        CreditAdjustmentTrailScreen(
            studentID = studentID,
            coursePackageID = detailId,
            useCases = useCases,
            zoneID = zoneID,
            onBack = { route = S1Routes.studentPackages(studentID) },
        )
    }
}

fun packageIdFromDetailRoute(route: String): CoursePackageID? {
    val prefix = "packages/"
    if (!route.startsWith(prefix)) return null
    val raw = route.removePrefix(prefix)
    if (raw.isEmpty() || raw.contains('/')) return null
    val id = runCatching { CoursePackageID.parse(raw) }.getOrNull() ?: return null
    return if (route == S1Routes.packageDetail(id)) id else null
}
