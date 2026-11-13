package com.ignacioli.finecoach

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import java.io.File

/** Measurement artifacts only. Images are drawn at native pixel size, without comparison. */
internal object P7SheetWriter {
    private val app get() = File(checkNotNull(System.getProperty("finecoach.storageProjectDirectory")))
    private val output get() = File(app, "build/outputs/p7").apply { mkdirs() }
    private val rows = sortedMapOf<String, String>()

    fun placeholder(reason: String): Bitmap = Bitmap.createBitmap(780, 1688, Bitmap.Config.ARGB_8888).also {
        val canvas = Canvas(it)
        canvas.drawColor(Color.WHITE)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.DKGRAY; textSize = 24f }
        canvas.drawText("PLACEHOLDER: unable to render matching content", 24f, 80f, paint)
        reason.chunked(48).take(30).forEachIndexed { index, line ->
            canvas.drawText(line, 24f, 120f + index * 32f, paint)
        }
    }

    @Synchronized
    fun write(id: String, android: Bitmap, composable: String, fixture: String, mismatches: String, reason: String? = null) {
        val path = "design/m1-b-hifi/screens/$id.png"
        val design = checkNotNull(BitmapFactory.decodeFile(File(app.parentFile.parentFile, path).path)) {
            "Cannot read design PNG: $path"
        }
        check(design.width == android.width && android.width == 780 && android.height in listOf(1688, 3376)) {
            "Expected native-scale 780px columns and 780x1688 viewport or two vertically stitched viewports"
        }
        save(android, File(output, "$id.android.png"))
        val sheet = Bitmap.createBitmap(design.width * 2, maxOf(design.height, android.height) + 40, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(sheet)
        canvas.drawColor(Color.WHITE)
        canvas.drawBitmap(design, 0f, 40f, null)
        canvas.drawBitmap(android, design.width.toFloat(), 40f, null)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.BLACK; textSize = 22f }
        canvas.drawText("$id | design | Android", 12f, 28f, paint)
        if (design.height > 1688 && android.height == 1688) {
            canvas.drawText("Android: first viewport only", design.width + 12f, 28f, paint)
        }
        if (android.height > 1688) {
            val evidence = File(output, "$id.scroll.txt").readText()
            val moved = Regex("before=([0-9.]+); after=([0-9.]+)").find(evidence)
            val delta = moved?.let { it.groupValues[2].toFloat() - it.groupValues[1].toFloat() }
            canvas.drawText("Android: 2 viewports; scroll ${delta ?: "unknown"}px", design.width + 12f, 28f, paint)
        }
        save(sheet, File(output, "$id.sheet.png"))
        val status = reason?.let { "placeholder: $it" } ?: "rendered"
        fun cell(value: String) = value.replace("|", " / ").replace('\n', ' ')
        rows[id] = "| $id | $path | $composable | ${cell(status)}; ${cell(fixture)} | ${cell(mismatches)} |"
        File(output, "index.md").writeText(
            "# P7 design / Android 测量\n\n" +
                "仅测量，未进行 OK/minor/rework 判定；无 comparator、baseline 或视觉验收。fictional data。\n" +
                "sdk 36; zh-rCN-w390dp-h844dp-notnight-xhdpi; NATIVE; Density(2f, 1f); status inset 52dp。\n" +
                "左右均为原始像素 1:1，40px 标签行；Android 默认首个 viewport；history 为两个完整 viewport 竖拼，保留产品布局和文案。\n\n" +
                "| id | design path | Android composable | status / fixture notes | unmatched content |\n" +
                "|---|---|---|---|---|\n" + rows.values.joinToString("\n") + "\n",
        )
        design.recycle()
        sheet.recycle()
    }

    private fun save(bitmap: Bitmap, file: File) {
        file.outputStream().use { check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) }
    }
}
