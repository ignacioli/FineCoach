package com.ignacioli.finecoach

/** NBSP has the same visible text identity as an ordinary space. */
internal fun normalizeConformanceText(text: String): String = text.replace('\u00a0', ' ')
