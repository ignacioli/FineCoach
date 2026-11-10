// fictional-data: isolated temporary databases and invented student values only.
package com.ignacioli.finecoach

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.runtime.Composable
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTextReplacement
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.width
import androidx.test.core.app.ApplicationProvider
import com.ignacioli.finecoach.core.application.AppClock
import com.ignacioli.finecoach.core.application.ApplicationResult
import com.ignacioli.finecoach.core.application.CreditUseCases
import com.ignacioli.finecoach.core.application.ExerciseCatalogLoader
import com.ignacioli.finecoach.core.application.StableIDGenerator
import com.ignacioli.finecoach.core.application.StartOrOpenSessionCommand
import com.ignacioli.finecoach.core.application.StudentRecord
import com.ignacioli.finecoach.core.application.StudentUseCases
import com.ignacioli.finecoach.core.domain.common.CoursePackageID
import com.ignacioli.finecoach.core.domain.common.CreditAdjustmentID
import com.ignacioli.finecoach.core.domain.common.SectionID
import com.ignacioli.finecoach.core.domain.common.SessionExerciseID
import com.ignacioli.finecoach.core.domain.common.SessionID
import com.ignacioli.finecoach.core.domain.common.StableExerciseID
import com.ignacioli.finecoach.core.domain.common.StudentID
import com.ignacioli.finecoach.core.domain.common.StudentLifecycle
import com.ignacioli.finecoach.core.domain.common.StudentSex
import com.ignacioli.finecoach.core.domain.common.TemplateExerciseID
import com.ignacioli.finecoach.core.domain.common.TemplateID
import com.ignacioli.finecoach.core.domain.common.TrainingSetID
import com.ignacioli.finecoach.core.domain.student.StudentDraft
import com.ignacioli.finecoach.designsystem.FineCoachTheme
import com.ignacioli.finecoach.features.students.StudentDetailScreen
import com.ignacioli.finecoach.features.students.StudentEditorMode
import com.ignacioli.finecoach.features.students.StudentEditorScreen
import com.ignacioli.finecoach.features.students.StudentFeatureFactory
import com.ignacioli.finecoach.features.students.StudentListScreen
import com.ignacioli.finecoach.features.students.StudentTestTags
import com.ignacioli.finecoach.navigation.S1Routes
import com.ignacioli.finecoach.storage.FineCoachDatabase
import com.ignacioli.finecoach.storage.FineCoachDatabaseFactory
import com.ignacioli.finecoach.storage.repository.CoursePackageRepository
import com.ignacioli.finecoach.storage.repository.ExerciseRepository
import com.ignacioli.finecoach.storage.repository.SessionRepository
import com.ignacioli.finecoach.storage.repository.StudentRepository
import java.time.Instant
import java.time.ZoneId
import java.util.UUID
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "zh-rCN-w320dp-h640dp-notnight-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class StudentEntryLayoutTests {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    private val worker = Executors.newSingleThreadExecutor()
    private lateinit var context: Context
    private lateinit var db: FineCoachDatabase
    private lateinit var sessions: SessionRepository
    private lateinit var credits: CreditUseCases
    private val now = Instant.parse("2026-11-06T08:09:10.123456789Z")
    private var clockNow = now
    private val clock = AppClock { clockNow }
    private val zoneId = ZoneId.of("Asia/Shanghai")
    private val sequence = AtomicInteger(1)
    private val ids = object : StableIDGenerator {
        override fun newStudentID() = StudentID.fromUUID(nextUuid())
        override fun newCoursePackageID() = CoursePackageID.fromUUID(nextUuid())
        override fun newCreditAdjustmentID() = CreditAdjustmentID.fromUUID(nextUuid())
        override fun newSessionID() = SessionID.fromUUID(nextUuid())
        override fun newTemplateID() = TemplateID.fromUUID(nextUuid())
        override fun newSectionID() = SectionID.fromUUID(nextUuid())
        override fun newSessionExerciseID() = SessionExerciseID.fromUUID(nextUuid())
        override fun newTemplateExerciseID() = TemplateExerciseID.fromUUID(nextUuid())
        override fun newTrainingSetID() = TrainingSetID.fromUUID(nextUuid())
        override fun newExerciseID() = StableExerciseID.parse(nextUuid().toString())
    }
    private val useCases get() = StudentUseCases(StudentRepository(db, clock), clock, ids)

    @Before fun prepare() {
        context = ApplicationProvider.getApplicationContext()
        context.deleteDatabase(FineCoachDatabaseFactory.DATABASE_NAME)
        db = FineCoachDatabaseFactory.create(context)
        worker.submit { bindStore() }.get(30, TimeUnit.SECONDS)
    }

    @After fun cleanUp() {
        try {
            worker.submit { db.close() }.get(30, TimeUnit.SECONDS)
        } finally {
            worker.shutdownNow()
            context.deleteDatabase(FineCoachDatabaseFactory.DATABASE_NAME)
        }
    }

    @Test fun emptyLibraryAppearsOnlyAfterASuccessfulLoad() {
        val viewModel = StudentFeatureFactory.listViewModel(useCases, clock = clock, zoneId = zoneId)
        val load = mutableStateOf(false)
        val route = AtomicReference<String?>(null)
        show {
            StudentListScreen(viewModel, onRoute = { route.set(it) }, autoLoad = load.value)
        }
        compose.waitForIdle()
        assertTrue(missing(StudentTestTags.STUDENT_LIST_EMPTY))
        load.value = true
        await { viewModel.uiState.isTrulyEmpty }
        node(StudentTestTags.STUDENT_LIST_EMPTY).assertIsDisplayed()
        compose.onNodeWithText("还没有学员").assertIsDisplayed()
        node(StudentTestTags.STUDENT_LIST_EMPTY_ADD).assertIsDisplayed().assertHasClickAction()
        assertFillsContent(StudentTestTags.STUDENT_LIST_EMPTY_ADD)
        node(StudentTestTags.STUDENT_LIST_EMPTY_ADD).performClick()
        assertEquals(S1Routes.STUDENT_CREATE, route.get())
        assertEquals(0L, tableCount("students"))
    }

    @Test fun searchMissStaysDistinctFromAnEmptyLibrary() {
        val first = createStudent("虚构甲")
        val second = createStudent("虚构乙")
        val viewModel = StudentFeatureFactory.listViewModel(
            useCases, sessionRepository = sessions, creditUseCases = credits, clock = clock, zoneId = zoneId,
        )
        val route = AtomicReference<String?>(null)
        show { StudentListScreen(viewModel, onRoute = { route.set(it) }, showRootSwitch = true) }
        await { viewModel.uiState.hasCompletedInitialLoad && viewModel.uiState.students.size == 2 }
        node("${StudentTestTags.STUDENT_LIST_SEGMENT}-0").performClick()
        assertEquals(S1Routes.TODAY, route.get())
        assertEquals(2L, tableCount("students"))
        node(StudentTestTags.STUDENT_LIST_SEARCH).performTextInput("甲")
        await { viewModel.uiState.query == "甲" && viewModel.isIdle && viewModel.uiState.students.size == 1 }
        node(StudentTestTags.studentRow(first.studentID)).assertIsDisplayed()
        assertTrue(missing(StudentTestTags.studentRow(second.studentID)))
        assertTrue(missing(StudentTestTags.STUDENT_LIST_EMPTY))
        node(StudentTestTags.STUDENT_LIST_SEARCH).performTextReplacement("没有")
        await { viewModel.uiState.query == "没有" && viewModel.isIdle && viewModel.uiState.students.isEmpty() }
        compose.onNodeWithText("没有找到匹配的学员").assertIsDisplayed()
        node(StudentTestTags.STUDENT_LIST_ADD).assertIsDisplayed().assertHasClickAction()
        assertTrue(missing(StudentTestTags.STUDENT_LIST_EMPTY_ADD))
        assertEquals(2L, tableCount("students"))
    }

    @Test fun createPersistsThroughRoomAndAllowsTheSameName() {
        val saved = AtomicReference<StudentRecord?>(null)
        val viewModel = StudentFeatureFactory.editorViewModel(StudentEditorMode.Add, useCases)
        val page = mutableStateOf(0)
        show {
            if (page.value == 0) {
                StudentEditorScreen(viewModel, onCancel = {}, onSaved = { saved.set(it) })
            } else {
                val list = remember {
                    StudentFeatureFactory.listViewModel(useCases, clock = clock, zoneId = zoneId)
                }
                StudentListScreen(list, onRoute = {})
            }
        }
        fillNameAndSex("虚构学员", StudentTestTags.EDITOR_SEX_FEMALE)
        node(StudentTestTags.EDITOR_SAVE).performClick()
        await { saved.get() != null || viewModel.uiState.saveError != null }
        val created = saved.get()
        assertNotNull(created)
        assertNull(viewModel.uiState.saveError)
        reopen()
        val stored = findStudent(created!!.studentID)
        assertEquals(created.studentID, stored!!.studentID)
        assertEquals(created.displayName, stored.displayName)
        assertEquals(StudentSex.female, stored.sex)
        val duplicate = createStudent(created.displayName)
        page.value = 1
        await {
            exists(StudentTestTags.studentRow(created.studentID)) &&
                exists(StudentTestTags.studentRow(duplicate.studentID))
        }
        node(StudentTestTags.studentRow(created.studentID)).assertIsDisplayed().assertHasClickAction()
        node(StudentTestTags.studentRow(duplicate.studentID)).assertIsDisplayed().assertHasClickAction()
    }

    @Test fun saveFailureKeepsInputAndRetryPersists() {
        failStudentInserts()
        val saved = AtomicReference<StudentRecord?>(null)
        val viewModel = StudentFeatureFactory.editorViewModel(StudentEditorMode.Add, useCases)
        show { StudentEditorScreen(viewModel, onCancel = {}, onSaved = { saved.set(it) }) }
        fillNameAndSex("虚构学员", StudentTestTags.EDITOR_SEX_MALE)
        node(StudentTestTags.EDITOR_SAVE).performClick()
        await { viewModel.uiState.saveError != null }
        assertNull(saved.get())
        node(StudentTestTags.EDITOR_NAME).assertTextEquals("虚构学员")
        assertEquals(StudentSex.male, viewModel.uiState.draft.sex)
        assertEquals(0L, tableCount("students"))
        clearStudentInsertFailure()
        node(StudentTestTags.EDITOR_SAVE).performClick()
        await { saved.get() != null }
        assertEquals(1L, tableCount("students"))
        assertEquals("虚构学员", findStudent(saved.get()!!.studentID)!!.displayName)
    }

    @Test fun cancelBackAndSkipWriteNothing() {
        val viewModel = StudentFeatureFactory.editorViewModel(StudentEditorMode.Add, useCases)
        val first = StudentFeatureFactory.editorViewModel(StudentEditorMode.FirstCreate, useCases)
        val cancelled = AtomicInteger(0)
        val skips = AtomicInteger(0)
        val page = mutableStateOf(0)
        show {
            if (page.value == 0) {
                StudentEditorScreen(viewModel, onCancel = { cancelled.incrementAndGet() }, onSaved = {})
            } else {
                StudentEditorScreen(first, onCancel = {}, onSaved = {
                    assertNull(it)
                    skips.incrementAndGet()
                })
            }
        }
        fillNameAndSex("虚构学员", StudentTestTags.EDITOR_SEX_OTHER)
        node(StudentTestTags.EDITOR_HEADER_BACK).performClick()
        assertEquals(1, cancelled.get())
        assertEquals(0L, tableCount("students"))
        compose.activity.onBackPressedDispatcher.onBackPressed()
        compose.waitForIdle()
        assertEquals(2, cancelled.get())
        assertEquals(0L, tableCount("students"))
        page.value = 1
        await { exists(StudentTestTags.EDITOR_SKIP) }
        node(StudentTestTags.EDITOR_SKIP).performScrollTo().performClick()
        compose.waitForIdle()
        assertEquals(1, skips.get())
        assertEquals(0L, tableCount("students"))
    }

    @Test fun permanentDeleteKeepsSingleLineTitleAndVisibleNoteAt320dp() {
        val created = createStudent("虚构排版学员")
        showEditorForDelete(created, AtomicInteger(0))
        node(StudentTestTags.DETAIL_DELETE).performScrollTo().assertIsDisplayed()
        assertFillsContent(StudentTestTags.DETAIL_DELETE)
        val title = compose.onNodeWithText("永久删除", useUnmergedTree = true).getUnclippedBoundsInRoot()
        assertTrue("Four title characters need their own width", title.width >= 64.dp)
        compose.onNodeWithText("删除学员和训练记录；课包与课时流水仍保留，需二次确认", useUnmergedTree = true).assertIsDisplayed()
    }

    @Test fun editorFieldsAndSaveButtonFillTheContentWidth() {
        val viewModel = StudentFeatureFactory.editorViewModel(StudentEditorMode.Add, useCases)
        show { StudentEditorScreen(viewModel, onCancel = {}, onSaved = {}) }
        listOf(
            StudentTestTags.EDITOR_ROW_NAME,
            StudentTestTags.EDITOR_ROW_SEX,
            StudentTestTags.EDITOR_ROW_GOAL,
            StudentTestTags.EDITOR_ROW_PHONE,
            StudentTestTags.EDITOR_ROW_WECHAT,
            StudentTestTags.EDITOR_ROW_PRIVATE_NOTE,
            StudentTestTags.EDITOR_ROW_INJURY_NOTES,
        ).forEach { tag ->
            node(tag).performScrollTo()
            assertFillsContent(tag)
        }
        assertFillsContent(StudentTestTags.EDITOR_SAVE)
        node(StudentTestTags.EDITOR_SAVE).assertHasClickAction()
    }

    @Test fun saveStaysReachableWhenTheImeInsetIsApplied() {
        val saved = AtomicReference<StudentRecord?>(null)
        val viewModel = StudentFeatureFactory.editorViewModel(StudentEditorMode.Add, useCases)
        show {
            StudentEditorScreen(
                viewModel,
                onCancel = {},
                onSaved = { saved.set(it) },
                insets = WindowInsets(left = 0.dp, top = 0.dp, right = 0.dp, bottom = 320.dp),
            )
        }
        val safe = node("platform-safe").getUnclippedBoundsInRoot()
        val button = node(StudentTestTags.EDITOR_SAVE).getUnclippedBoundsInRoot()
        assertTrue(button.bottom <= safe.bottom)
        node(StudentTestTags.EDITOR_SAVE).assertIsDisplayed().assertHasClickAction()
        fillNameAndSex("虚构学员", StudentTestTags.EDITOR_SEX_UNDISCLOSED)
        node(StudentTestTags.EDITOR_SAVE).performClick()
        await { saved.get() != null || viewModel.uiState.saveError != null }
        assertNotNull(saved.get())
        assertEquals(1L, tableCount("students"))
    }

    @Test fun blankNameAndMissingSexDoNotWrite() {
        val viewModel = StudentFeatureFactory.editorViewModel(StudentEditorMode.Add, useCases)
        show { StudentEditorScreen(viewModel, onCancel = {}, onSaved = {}) }
        node(StudentTestTags.EDITOR_SAVE).performClick()
        compose.waitForIdle()
        compose.onNodeWithText("还没填写显示名称").assertIsDisplayed()
        compose.onNodeWithText("还没选择性别").assertIsDisplayed()
        assertEquals(0L, tableCount("students"))
        node(StudentTestTags.EDITOR_SEX_FEMALE).performClick()
        node(StudentTestTags.EDITOR_SAVE).performClick()
        compose.waitForIdle()
        compose.onNodeWithText("还没填写显示名称").assertIsDisplayed()
        assertEquals(0L, tableCount("students"))
        node(StudentTestTags.EDITOR_NAME).performTextInput("   ")
        node(StudentTestTags.EDITOR_SAVE).performClick()
        compose.waitForIdle()
        compose.onNodeWithText("还没填写显示名称").assertIsDisplayed()
        assertEquals(0L, tableCount("students"))
    }

    @Test fun editKeepsIdentityAndClearsOptionalFields() {
        val created = createStudent(
            name = "虚构学员",
            sex = StudentSex.female,
            goal = "虚构目标",
            phone = "fictional-phone",
            wechat = "fictional-wechat",
            note = "虚构私密备注",
            injury = "虚构伤情",
        )
        clockNow = now.plusSeconds(90)
        val saved = AtomicReference<StudentRecord?>(null)
        val viewModel = StudentFeatureFactory.editorViewModel(
            StudentEditorMode.Edit(created.studentID), useCases, existing = created,
        )
        show { StudentEditorScreen(viewModel, onCancel = {}, onSaved = { saved.set(it) }) }
        node(StudentTestTags.EDITOR_GOAL).performTextReplacement("虚构目标乙")
        node(StudentTestTags.EDITOR_PHONE).performScrollTo().performTextReplacement("")
        node(StudentTestTags.EDITOR_SAVE).performClick()
        await { saved.get() != null || viewModel.uiState.saveError != null }
        val updated = saved.get()
        assertNotNull(updated)
        assertEquals(created.studentID, updated!!.studentID)
        assertEquals(created.createdAtUTC, updated.createdAtUTC)
        assertEquals("虚构目标乙", updated.trainingGoal)
        assertNull(updated.phone)
        reopen()
        val stored = findStudent(created.studentID)
        assertEquals(created.studentID, stored!!.studentID)
        assertEquals(created.createdAtUTC, stored.createdAtUTC)
        assertNull(stored.phone)
        assertEquals("虚构目标乙", stored.trainingGoal)
    }

    @Test fun archiveAndRestoreUseVisibleControls() {
        val created = createStudent("虚构学员")
        val archived = AtomicInteger(0)
        val archivedAgain = AtomicInteger(0)
        val page = mutableStateOf(0)
        val editor = StudentFeatureFactory.editorViewModel(
            StudentEditorMode.Edit(created.studentID), useCases, existing = created,
        )
        val detail = StudentFeatureFactory.detailViewModel(
            created.studentID, useCases, sessions, credits, clock = clock, zoneId = zoneId,
        )
        val editorAgain = StudentFeatureFactory.editorViewModel(
            StudentEditorMode.Edit(created.studentID), useCases, existing = created,
        )
        val archivedList = StudentFeatureFactory.listViewModel(
            useCases, showsArchived = true, clock = clock, zoneId = zoneId,
        )
        show {
            when (page.value) {
                0 -> StudentEditorScreen(
                    editor, onCancel = {}, onSaved = {}, onArchived = { archived.incrementAndGet() },
                )
                1 -> StudentDetailScreen(detail, onRoute = {}, onBack = {})
                2 -> StudentEditorScreen(
                    editorAgain, onCancel = {}, onSaved = {}, onArchived = { archivedAgain.incrementAndGet() },
                )
                else -> StudentListScreen(archivedList, onRoute = {}, onBack = {})
            }
        }
        node(StudentTestTags.DETAIL_ARCHIVE).performScrollTo().assertHasClickAction().performClick()
        compose.waitForIdle()
        node(StudentTestTags.ARCHIVE_CONFIRM).assertIsDisplayed().assertHasClickAction()
        assertFillsContent(StudentTestTags.ARCHIVE_CONFIRM)
        compose.activity.onBackPressedDispatcher.onBackPressed()
        compose.waitForIdle()
        assertEquals(0, archived.get())
        assertEquals(1L, tableCount("students"))
        assertEquals(StudentLifecycle.active, findStudent(created.studentID)!!.lifecycle)
        await { exists(StudentTestTags.DETAIL_ARCHIVE) }
        node(StudentTestTags.DETAIL_ARCHIVE).performScrollTo().performClick()
        compose.waitForIdle()
        node(StudentTestTags.ARCHIVE_CANCEL).performClick()
        compose.waitForIdle()
        assertEquals(StudentLifecycle.active, findStudent(created.studentID)!!.lifecycle)
        node(StudentTestTags.DETAIL_ARCHIVE).performScrollTo().performClick()
        compose.waitForIdle()
        node(StudentTestTags.ARCHIVE_CONFIRM).performClick()
        await { archived.get() == 1 }
        assertEquals(StudentLifecycle.archived, findStudent(created.studentID)!!.lifecycle)
        page.value = 1
        await { detail.uiState.showsRestore }
        assertTrue(missing(StudentTestTags.DETAIL_START_TRAINING))
        node(StudentTestTags.DETAIL_RESTORE).assertIsDisplayed().assertHasClickAction().performClick()
        await { detail.uiState.showsStartTraining }
        assertEquals(StudentLifecycle.active, findStudent(created.studentID)!!.lifecycle)
        page.value = 2
        await { exists(StudentTestTags.DETAIL_ARCHIVE) }
        node(StudentTestTags.DETAIL_ARCHIVE).performScrollTo().performClick()
        compose.waitForIdle()
        node(StudentTestTags.ARCHIVE_CONFIRM).performClick()
        await { archivedAgain.get() == 1 }
        page.value = 3
        await { exists(StudentTestTags.studentListRestore(created.studentID)) }
        node(StudentTestTags.studentListRestore(created.studentID)).assertHasClickAction().performClick()
        await { findStudent(created.studentID)?.lifecycle == StudentLifecycle.active }
    }

    @Test fun deleteRequiresTheTypedNameAndWrongNameWritesNothing() {
        val created = createStudent("虚构学员")
        val deleted = AtomicInteger(0)
        val page = mutableStateOf(0)
        show {
            key(page.value) {
                val editor = remember(page.value) {
                    StudentFeatureFactory.editorViewModel(
                        StudentEditorMode.Edit(created.studentID), useCases, existing = created,
                    )
                }
                StudentEditorScreen(
                    editor,
                    onCancel = {},
                    onSaved = {},
                    onDeleted = { deleted.incrementAndGet() },
                    sessionRepository = sessions,
                )
            }
        }
        node(StudentTestTags.DETAIL_DELETE).performScrollTo().assertHasClickAction().performClick()
        await { exists(StudentTestTags.DELETE_NAME) }
        compose.onAllNodesWithText("0 条已完成训练记录", substring = true).assertCountEquals(0)
        node(StudentTestTags.DELETE_CONFIRM).assertIsDisplayed()
        assertTrue(!enabled(StudentTestTags.DELETE_CONFIRM))
        node(StudentTestTags.DELETE_NAME).performScrollTo().performTextInput("另一个虚构学员")
        compose.waitForIdle()
        assertTrue(!enabled(StudentTestTags.DELETE_CONFIRM))
        assertEquals(1L, tableCount("students"))
        compose.activity.onBackPressedDispatcher.onBackPressed()
        compose.waitForIdle()
        assertEquals(0, deleted.get())
        assertEquals(1L, tableCount("students"))
        assertNotNull(findStudent(created.studentID))
        await { exists(StudentTestTags.DETAIL_DELETE) }
        node(StudentTestTags.DETAIL_DELETE).performScrollTo().performClick()
        await { exists(StudentTestTags.DELETE_NAME) }
        node(StudentTestTags.DELETE_NAME).performScrollTo().performTextInput("另一个虚构学员")
        compose.waitForIdle()
        assertTrue(!enabled(StudentTestTags.DELETE_CONFIRM))
        node(StudentTestTags.DELETE_CANCEL).performClick()
        compose.waitForIdle()
        assertEquals(0, deleted.get())
        assertEquals(1L, tableCount("students"))
        val rejected = offMain { useCases.delete(created.studentID, "另一个虚构学员") }
        assertTrue(rejected is ApplicationResult.Failure)
        assertEquals(1L, tableCount("students"))
        page.value = 1
        await { exists(StudentTestTags.DETAIL_DELETE) }
        node(StudentTestTags.DETAIL_DELETE).performScrollTo().performClick()
        await { exists(StudentTestTags.DELETE_NAME) }
        node(StudentTestTags.DELETE_NAME).performScrollTo().performTextInput(created.displayName)
        await { enabled(StudentTestTags.DELETE_CONFIRM) }
        assertFillsContent(StudentTestTags.DELETE_NAME)
        assertFillsContent(StudentTestTags.DELETE_CONFIRM)
        node(StudentTestTags.DELETE_CONFIRM).performClick()
        await { exists(StudentTestTags.DELETE_DONE) }
        assertEquals(0L, tableCount("students"))
        node(StudentTestTags.DELETE_BACK_TO_LIST).performClick()
        assertEquals(1, deleted.get())
        reopen()
        assertNull(findStudent(created.studentID))
    }

    @Test fun inProgressSessionBlocksDeleteAndWritesNothing() {
        val created = createStudent("虚构学员")
        val session = startSession(created.studentID)
        val route = AtomicReference<String?>(null)
        showEditorForDelete(created, AtomicInteger(0), route)
        node(StudentTestTags.DETAIL_DELETE).performScrollTo().performClick()
        await { exists(StudentTestTags.DELETE_BLOCKED) }
        node(StudentTestTags.DELETE_BLOCKED).assertIsDisplayed()
        assertTrue(missing(StudentTestTags.DELETE_CONFIRM))
        assertTrue(missing(StudentTestTags.DELETE_NAME))
        assertFillsContent(StudentTestTags.DELETE_CONTINUE_TRAINING)
        compose.activity.onBackPressedDispatcher.onBackPressed()
        compose.waitForIdle()
        assertEquals(1L, tableCount("students"))
        assertEquals(1L, tableCount("sessions"))
        assertNotNull(findStudent(created.studentID))
        assertNull(route.get())
        await { exists(StudentTestTags.DETAIL_DELETE) }
        node(StudentTestTags.DETAIL_DELETE).performScrollTo().performClick()
        await { exists(StudentTestTags.DELETE_BLOCKED) }
        node(StudentTestTags.DELETE_CONTINUE_TRAINING).assertIsDisplayed().assertHasClickAction().performClick()
        assertEquals(S1Routes.activeSession(session.sessionID), route.get())
        assertEquals(1L, tableCount("students"))
        assertEquals(1L, tableCount("sessions"))
        val rejected = offMain { useCases.delete(created.studentID, created.displayName) }
        assertTrue(rejected is ApplicationResult.Failure)
        assertNotNull(findStudent(created.studentID))
        assertEquals(1L, tableCount("sessions"))
    }

    @Test fun detailNavigationEmitsRoutesWithoutWriting() {
        val created = createStudent(
            name = "虚构学员",
            goal = "虚构目标",
            phone = "fictional-phone",
            wechat = "fictional-wechat",
            note = "虚构私密备注",
            injury = "虚构伤情",
        )
        clockNow = now.plusSeconds(120)
        val before = findStudent(created.studentID)!!
        val route = AtomicReference<String?>(null)
        val left = AtomicInteger(0)
        val viewModel = StudentFeatureFactory.detailViewModel(
            created.studentID, useCases, sessions, credits, clock = clock, zoneId = zoneId,
        )
        show { StudentDetailScreen(viewModel, onRoute = { route.set(it) }, onBack = { left.incrementAndGet() }) }
        await { viewModel.uiState.showsStartTraining }
        compose.onNodeWithText("新建课包后，上完课会按课时扣减").assertIsDisplayed()
        compose.onAllNodesWithText("上完第一节课后会显示在这里").assertCountEquals(0)
        node(StudentTestTags.DETAIL_COURSE_PACKAGES).performScrollTo().assertHasClickAction().performClick()
        assertEquals(S1Routes.studentPackages(created.studentID), route.get())
        node(StudentTestTags.DETAIL_RECENT_TRAINING).performScrollTo().performClick()
        assertEquals(S1Routes.studentHistory(created.studentID), route.get())
        node(StudentTestTags.DETAIL_HISTORY).performScrollTo().assertHasClickAction().performClick()
        assertEquals(S1Routes.studentHistory(created.studentID), route.get())
        node(StudentTestTags.DETAIL_HEADER_EDIT).performClick()
        assertEquals(S1Routes.studentEdit(created.studentID), route.get())
        node(StudentTestTags.DETAIL_NOTES_FOLD).performScrollTo().performClick()
        node(StudentTestTags.DETAIL_NOTES_BODY).assertIsDisplayed()
        node(StudentTestTags.DETAIL_HEADER_BACK).performScrollTo().performClick()
        assertEquals(1, left.get())
        compose.activity.onBackPressedDispatcher.onBackPressed()
        compose.waitForIdle()
        assertEquals(2, left.get())
        val after = findStudent(created.studentID)!!
        assertEquals(before.updatedAtUTC, after.updatedAtUTC)
        assertEquals(before.lifecycle, after.lifecycle)
        assertEquals(0L, tableCount("sessions"))
        assertFillsContent(StudentTestTags.DETAIL_START_TRAINING)
        node(StudentTestTags.DETAIL_START_TRAINING).assertIsDisplayed().assertHasClickAction()
    }

    @Test fun startTrainingPersistsASessionAndEmitsItsRoute() {
        val created = createStudent("虚构学员")
        val route = AtomicReference<String?>(null)
        val viewModel = StudentFeatureFactory.detailViewModel(
            created.studentID, useCases, sessions, credits, clock = clock, zoneId = zoneId,
        )
        show { StudentDetailScreen(viewModel, onRoute = { route.set(it) }, onBack = {}) }
        await { viewModel.uiState.showsStartTraining }
        node(StudentTestTags.DETAIL_START_TRAINING).performClick()
        await { route.get() != null || viewModel.uiState.errorMessage != null }
        assertNull(viewModel.uiState.errorMessage)
        val active = offMain {
            val result = sessions.active(created.studentID)
            check(result is ApplicationResult.Success)
            result.value
        }
        assertNotNull(active)
        assertEquals(S1Routes.activeSession(active!!.sessionID), route.get())
        assertEquals(created.studentID, active.studentID)
        assertEquals(1L, tableCount("sessions"))
        reopen()
        val again = offMain {
            val result = sessions.active(created.studentID)
            check(result is ApplicationResult.Success)
            result.value
        }
        assertEquals(active.sessionID, again!!.sessionID)
    }

    @Test fun listContinueOpensTheExistingSession() {
        val created = createStudent("虚构学员")
        val session = startSession(created.studentID)
        val route = AtomicReference<String?>(null)
        val viewModel = StudentFeatureFactory.listViewModel(
            useCases, sessionRepository = sessions, creditUseCases = credits, clock = clock, zoneId = zoneId,
        )
        show { StudentListScreen(viewModel, onRoute = { route.set(it) }) }
        await { exists(StudentTestTags.STUDENT_LIST_IN_PROGRESS) }
        node(StudentTestTags.STUDENT_LIST_IN_PROGRESS).assertIsDisplayed().assertHasClickAction().performClick()
        assertEquals(S1Routes.activeSession(session.sessionID), route.get())
        assertEquals(1L, tableCount("sessions"))
        node(StudentTestTags.studentRow(created.studentID)).assertHasClickAction()
        assertFillsContent(StudentTestTags.STUDENT_LIST_SEARCH)
        assertFillsContent(StudentTestTags.STUDENT_LIST_ADD)
    }

    private fun showEditorForDelete(
        student: StudentRecord,
        deleted: AtomicInteger,
        route: AtomicReference<String?> = AtomicReference(),
    ) {
        val editor = StudentFeatureFactory.editorViewModel(
            StudentEditorMode.Edit(student.studentID), useCases, existing = student,
        )
        show {
            StudentEditorScreen(
                editor,
                onCancel = {},
                onSaved = {},
                onDeleted = { deleted.incrementAndGet() },
                onRoute = { route.set(it) },
                sessionRepository = sessions,
            )
        }
    }

    private fun fillNameAndSex(name: String, sexTag: String) {
        node(StudentTestTags.EDITOR_NAME).performScrollTo().performTextInput(name)
        node(sexTag).performScrollTo().performClick()
        compose.waitForIdle()
    }

    private fun show(content: @Composable () -> Unit) {
        compose.setContent { FineCoachTheme { content() } }
    }

    private fun node(tag: String) = compose.onNodeWithTag(tag, useUnmergedTree = true)

    private fun exists(tag: String) =
        compose.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    private fun missing(tag: String) = !exists(tag)

    private fun enabled(tag: String): Boolean = try {
        node(tag).assertIsEnabled()
        true
    } catch (_: AssertionError) {
        false
    }

    private fun assertFillsContent(tag: String) {
        val parent = node("platform-content").getUnclippedBoundsInRoot().width
        val child = node(tag).getUnclippedBoundsInRoot().width
        assertEquals(parent, child)
    }

    private fun await(condition: () -> Boolean) {
        val start = System.nanoTime()
        while (!condition()) {
            compose.waitForIdle()
            if (System.nanoTime() - start > 20_000_000_000L) error("Timed out waiting for the student UI")
        }
    }

    private fun createStudent(
        name: String,
        sex: StudentSex = StudentSex.undisclosed,
        goal: String = "",
        phone: String = "",
        wechat: String = "",
        note: String = "",
        injury: String = "",
    ): StudentRecord = offMain {
        val result = useCases.create(StudentDraft(name, sex, goal, injury, note, phone, wechat))
        check(result is ApplicationResult.Success)
        result.value
    }

    private fun startSession(studentID: StudentID) = offMain {
        val result = sessions.startOrOpen(StartOrOpenSessionCommand(studentID, nowUTC = clock.now()))
        check(result is ApplicationResult.Success)
        result.value
    }

    private fun findStudent(studentID: StudentID): StudentRecord? = offMain {
        val result = useCases.find(studentID)
        check(result is ApplicationResult.Success)
        result.value
    }

    private fun tableCount(table: String): Long = offMain {
        db.openHelper.writableDatabase.query("SELECT COUNT(*) FROM `$table`").use { cursor ->
            check(cursor.moveToFirst())
            cursor.getLong(0)
        }
    }

    private fun failStudentInserts() = offMain {
        db.openHelper.writableDatabase.execSQL(
            "CREATE TRIGGER t010_fail_insert BEFORE INSERT ON `students` BEGIN SELECT RAISE(ABORT, 'injected'); END",
        )
    }

    private fun clearStudentInsertFailure() = offMain {
        db.openHelper.writableDatabase.execSQL("DROP TRIGGER IF EXISTS t010_fail_insert")
    }

    private fun reopen() = offMain {
        db.close()
        db = FineCoachDatabaseFactory.create(context)
        bindStore()
    }

    private fun bindStore() {
        val generation = UUID.fromString(
            db.storeMetadataDao().find(FineCoachDatabaseFactory.GENERATION_KEY)!!.value,
        )
        val exercises = ExerciseRepository(db, ExerciseCatalogLoader(context.assets), clock)
        sessions = SessionRepository(db, clock, ids, generation, exercises)
        credits = CreditUseCases(CoursePackageRepository(db, clock, ids, zoneId), clock, ids, zoneId)
    }

    private fun nextUuid() = UUID.fromString(
        "abcdef00-0000-4000-8000-${sequence.getAndIncrement().toString().padStart(12, '0')}",
    )

    private fun <T> offMain(action: suspend () -> T): T =
        worker.submit(Callable { runBlocking { action() } }).get(30, TimeUnit.SECONDS)
}
