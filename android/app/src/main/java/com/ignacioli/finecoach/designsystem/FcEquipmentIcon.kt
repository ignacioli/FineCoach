package com.ignacioli.finecoach.designsystem

import androidx.compose.material3.Icon
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.foundation.layout.size
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import com.ignacioli.finecoach.R
import com.ignacioli.finecoach.core.application.ExerciseCatalogLoader
import com.ignacioli.finecoach.core.application.ExerciseCatalogMetadata
import com.ignacioli.finecoach.core.domain.common.StableExerciseID
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Product-owned §7.1 artwork. No fallback for custom/unmapped equipment. */
enum class FcEquipmentIcon(val drawable: Int) {
    barbell(R.drawable.ic_equipment_barbell),
    bike(R.drawable.ic_equipment_bike),
    bodyweight(R.drawable.ic_equipment_bodyweight),
    cable_crossover(R.drawable.ic_equipment_cable_crossover),
    cable_machine(R.drawable.ic_equipment_cable_machine),
    dumbbell(R.drawable.ic_equipment_dumbbell),
    hack_squat(R.drawable.ic_equipment_hack_squat),
    hip_adduction(R.drawable.ic_equipment_hip_adduction),
    jump_rope(R.drawable.ic_equipment_jump_rope),
    kettlebell(R.drawable.ic_equipment_kettlebell),
    leg_extension(R.drawable.ic_equipment_leg_extension),
    pec_deck(R.drawable.ic_equipment_pec_deck),
    plate_loaded(R.drawable.ic_equipment_plate_loaded),
    pull_up_bar(R.drawable.ic_equipment_pull_up_bar),
    resistance_band(R.drawable.ic_equipment_resistance_band),
    rowing_machine(R.drawable.ic_equipment_rowing_machine),
    shoulder_press(R.drawable.ic_equipment_shoulder_press),
    smith_machine(R.drawable.ic_equipment_smith_machine),
    suspension_trainer(R.drawable.ic_equipment_suspension_trainer),
    tbar_row(R.drawable.ic_equipment_tbar_row),
    treadmill(R.drawable.ic_equipment_treadmill);
    companion object {
        fun icon(equipmentClass: String?, primaryMuscleGroup: String?): FcEquipmentIcon? = when (equipmentClass) {
            "杠铃" -> barbell
            "哑铃" -> dumbbell
            "徒手" -> bodyweight
            "绳索" -> cable_crossover
            "史密斯机" -> smith_machine
            "壶铃" -> kettlebell
            "哈克机" -> hack_squat
            "悍马机" -> plate_loaded
            "悬挂带" -> suspension_trainer
            "单杠" -> pull_up_bar
            "弹力带" -> resistance_band
            "固定器械" -> when (primaryMuscleGroup) {
                "胸" -> pec_deck; "肩" -> shoulder_press; "大腿" -> leg_extension
                "臀" -> hip_adduction; "小腿" -> hack_squat; "背" -> tbar_row
                else -> null
            }
            else -> null
        }
    }
}

@Composable
fun FcEquipmentIconView(icon: FcEquipmentIcon, modifier: Modifier = Modifier) {
    Icon(painterResource(icon.drawable), contentDescription = null,
        modifier = modifier.size(FcComponentMetrics.icon), tint = FcColors.actionPrimary)
}

/** Read the approved catalog facets only; never infer equipment from a display name. */
@Composable
fun FcEquipmentIconForExercise(id: StableExerciseID?, modifier: Modifier = Modifier) {
    if (id == null) return
    val metadata = rememberExerciseCatalogMetadata()
    val facet = metadata[id] ?: return
    FcEquipmentIcon.icon(facet.equipmentClass, facet.primaryMuscleGroup)?.let { FcEquipmentIconView(it, modifier) }
}

/** Composition only reads cached facets; a cold cache is filled off the main thread. */
@Composable
internal fun rememberExerciseCatalogMetadata(): Map<StableExerciseID, ExerciseCatalogMetadata> {
    val assets = LocalContext.current.applicationContext.assets
    val loader = remember(assets) { ExerciseCatalogLoader(assets) }
    val metadata by produceState(loader.cachedMetadata(), assets) {
        if (value.isEmpty()) {
            value = withContext(Dispatchers.IO) {
                try { loader.load(Instant.EPOCH).metadata }
                catch (cancelled: CancellationException) { throw cancelled }
                catch (_: Exception) { loader.cachedMetadata() }
            }
        }
    }
    return metadata
}
