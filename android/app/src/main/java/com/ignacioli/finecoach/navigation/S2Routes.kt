package com.ignacioli.finecoach.navigation

import java.time.LocalDate
import java.util.UUID

/** S2 core destinations; date and identity are canonical, local-only path arguments. */
object S2Routes {
    const val ARG_DATE = "date"
    const val ARG_APPOINTMENT = "appointmentID"
    const val SETTINGS = "settings/reminders"
    const val CALENDAR = "calendar"
    const val APPOINTMENT_CREATE = "appointments/create/{$ARG_DATE}"
    const val APPOINTMENT_EDIT = "appointments/{$ARG_APPOINTMENT}/edit"
    fun createAppointment(date: LocalDate) = "appointments/create/$date"
    fun editAppointment(id: UUID) = "appointments/$id/edit"
}
