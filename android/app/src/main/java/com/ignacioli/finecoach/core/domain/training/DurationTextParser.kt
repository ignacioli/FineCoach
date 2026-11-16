package com.ignacioli.finecoach.core.domain.training

import java.math.BigDecimal
import java.math.RoundingMode

object DurationTextParser {
    private val fullChinesePattern = Regex("^(\\d+)\\s*分\\s*(\\d+)\\s*秒$")
    private val fullLatinPattern = Regex("^(\\d+)\\s*[mM]\\s*(\\d+)\\s*[sS]$")
    private val minutesOnlyPattern = Regex("^(\\d+)\\s*[分mM]$")
    private val secondsOnlyPattern = Regex("^(\\d+)\\s*[秒sS]$")

    private val sessionChinesePattern = Regex("^(\\d+)\\s*小时\\s*(\\d+)\\s*分(?:钟)?$")
    private val sessionLatinPattern = Regex("^(\\d+)\\s*[hH]\\s*(\\d+)\\s*[mM]$")
    private val sessionHoursPattern = Regex("^(\\d+)\\s*(?:小时|[hH])$")
    private val sessionMinutesPattern = Regex("^(\\d+)(?:\\s*(?:分钟|分|[mM]))?$")

    fun parseSessionDurationSeconds(text: String): String? {
        val trimmed = text.trim()
        val (hours, minutes) = when {
            sessionChinesePattern.matches(trimmed) -> {
                val m = sessionChinesePattern.find(trimmed) ?: return null
                Pair(m.groupValues[1].toIntOrNull() ?: return null, m.groupValues[2].toIntOrNull() ?: return null)
            }

            sessionLatinPattern.matches(trimmed) -> {
                val m = sessionLatinPattern.find(trimmed) ?: return null
                Pair(m.groupValues[1].toIntOrNull() ?: return null, m.groupValues[2].toIntOrNull() ?: return null)
            }

            sessionHoursPattern.matches(trimmed) -> {
                val m = sessionHoursPattern.find(trimmed) ?: return null
                Pair(m.groupValues[1].toIntOrNull() ?: return null, 0)
            }

            sessionMinutesPattern.matches(trimmed) -> {
                val m = sessionMinutesPattern.find(trimmed) ?: return null
                Pair(0, m.groupValues[1].toIntOrNull() ?: return null)
            }

            else -> return null
        }
        val hourSeconds = try {
            Math.multiplyExact(hours, 3600)
        } catch (_: ArithmeticException) {
            return null
        }
        val minuteSeconds = try {
            Math.multiplyExact(minutes, 60)
        } catch (_: ArithmeticException) {
            return null
        }
        val total = try {
            Math.addExact(hourSeconds, minuteSeconds)
        } catch (_: ArithmeticException) {
            return null
        }
        return total.toString()
    }

    fun formatSessionDurationForEditing(seconds: String): String {
        val value = runCatching { DecimalValue.parse(seconds) }.getOrNull() ?: return ""
        if (value < DecimalValue.ZERO) {
            return ""
        }
        val roundedMinutes = value.decimal
            .divide(BigDecimal("60"), 0, RoundingMode.HALF_UP)
            .toInt()
        val hours = roundedMinutes / 60
        val minutes = roundedMinutes % 60
        return when {
            hours > 0 && minutes > 0 -> "${hours} 小时 ${minutes} 分"
            hours > 0 -> "${hours} 小时"
            else -> "${minutes} 分"
        }
    }

    fun parseSeconds(text: String): String? {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) {
            return null
        }
        if (fullChinesePattern.matches(trimmed)) {
            val m = fullChinesePattern.find(trimmed) ?: return null
            val minutes = m.groupValues[1].toIntOrNull() ?: return null
            val seconds = m.groupValues[2].toIntOrNull() ?: return null
            return (minutes * 60 + seconds).toString()
        }
        if (fullLatinPattern.matches(trimmed)) {
            val m = fullLatinPattern.find(trimmed) ?: return null
            val minutes = m.groupValues[1].toIntOrNull() ?: return null
            val seconds = m.groupValues[2].toIntOrNull() ?: return null
            return (minutes * 60 + seconds).toString()
        }
        if (minutesOnlyPattern.matches(trimmed)) {
            val m = minutesOnlyPattern.find(trimmed) ?: return null
            val minutes = m.groupValues[1].toIntOrNull() ?: return null
            return (minutes * 60).toString()
        }
        if (secondsOnlyPattern.matches(trimmed)) {
            val m = secondsOnlyPattern.find(trimmed) ?: return null
            return m.groupValues[1].toIntOrNull()?.toString()
        }
        return runCatching { DecimalValue.parse(trimmed).canonicalString }.getOrNull()
    }

    fun formatForEditing(secondsText: String?): String {
        val text = secondsText ?: return ""
        val value = runCatching { DecimalValue.parse(text) }.getOrNull() ?: return ""
        if (value < DecimalValue.ZERO) {
            return text
        }
        val totalSeconds = value.decimal.toInt()
        val minutes = totalSeconds / 60
        val seconds = totalSeconds % 60
        return when {
            minutes > 0 && seconds > 0 -> "${minutes} 分 ${seconds} 秒"
            minutes > 0 -> "${minutes} 分"
            else -> "${seconds} 秒"
        }
    }
}
