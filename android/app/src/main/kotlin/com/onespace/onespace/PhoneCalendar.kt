package com.onespace.onespace

import android.content.ContentProviderOperation
import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.provider.CalendarContract
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

/**
 * R74: one-way export into a separate local "OneSpace" calendar. Only that
 * calendar is created, replaced or removed — the person's other calendars are
 * never read. The calendar is read-only for other apps.
 */
object PhoneCalendar {
    private const val ACCOUNT = "OneSpace"

    private fun asSyncAdapter(uri: Uri): Uri = uri.buildUpon()
        .appendQueryParameter(CalendarContract.CALLER_IS_SYNCADAPTER, "true")
        .appendQueryParameter(CalendarContract.Calendars.ACCOUNT_NAME, ACCOUNT)
        .appendQueryParameter(CalendarContract.Calendars.ACCOUNT_TYPE, CalendarContract.ACCOUNT_TYPE_LOCAL)
        .build()

    private fun findCalendar(context: Context): Long? {
        context.contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            arrayOf(CalendarContract.Calendars._ID),
            "${CalendarContract.Calendars.ACCOUNT_NAME}=? AND ${CalendarContract.Calendars.ACCOUNT_TYPE}=?",
            arrayOf(ACCOUNT, CalendarContract.ACCOUNT_TYPE_LOCAL), null
        )?.use { c -> if (c.moveToFirst()) return c.getLong(0) }
        return null
    }

    private fun ensureCalendar(context: Context, name: String): Long {
        findCalendar(context)?.let { return it }
        val values = ContentValues().apply {
            put(CalendarContract.Calendars.ACCOUNT_NAME, ACCOUNT)
            put(CalendarContract.Calendars.ACCOUNT_TYPE, CalendarContract.ACCOUNT_TYPE_LOCAL)
            put(CalendarContract.Calendars.NAME, name)
            put(CalendarContract.Calendars.CALENDAR_DISPLAY_NAME, name)
            put(CalendarContract.Calendars.CALENDAR_COLOR, 0xFFE0607E.toInt())
            put(CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL, CalendarContract.Calendars.CAL_ACCESS_READ)
            put(CalendarContract.Calendars.OWNER_ACCOUNT, ACCOUNT)
            put(CalendarContract.Calendars.VISIBLE, 1)
            put(CalendarContract.Calendars.SYNC_EVENTS, 1)
            put(CalendarContract.Calendars.CALENDAR_TIME_ZONE, TimeZone.getDefault().id)
        }
        val uri = context.contentResolver.insert(asSyncAdapter(CalendarContract.Calendars.CONTENT_URI), values)
            ?: throw IllegalStateException("Calendar could not be created")
        return uri.lastPathSegment!!.toLong()
    }

    private fun utcMidnight(date: String): Long {
        val f = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        f.timeZone = TimeZone.getTimeZone("UTC")
        return f.parse(date)!!.time
    }

    /** Replaces everything in the OneSpace calendar; returns how many were written. */
    fun replaceAll(context: Context, name: String, items: List<Map<*, *>>): Int {
        val calendar = ensureCalendar(context, name)
        val ops = ArrayList<ContentProviderOperation>()
        ops.add(ContentProviderOperation.newDelete(asSyncAdapter(CalendarContract.Events.CONTENT_URI))
            .withSelection("${CalendarContract.Events.CALENDAR_ID}=?", arrayOf(calendar.toString())).build())
        var count = 0
        for (item in items) {
            val title = item["title"]?.toString().orEmpty()
            if (title.isBlank()) continue
            val allDay = item["allDay"] == true
            val b = ContentProviderOperation.newInsert(asSyncAdapter(CalendarContract.Events.CONTENT_URI))
                .withValue(CalendarContract.Events.CALENDAR_ID, calendar)
                .withValue(CalendarContract.Events.TITLE, title)
                .withValue(CalendarContract.Events.DESCRIPTION, item["notes"]?.toString().orEmpty())
                .withValue(CalendarContract.Events.EVENT_LOCATION, item["location"]?.toString().orEmpty())
                .withValue(CalendarContract.Events.HAS_ALARM, 0)
            if (allDay) {
                b.withValue(CalendarContract.Events.ALL_DAY, 1)
                    .withValue(CalendarContract.Events.EVENT_TIMEZONE, "UTC")
                    .withValue(CalendarContract.Events.DTSTART, utcMidnight(item["startDate"].toString()))
                    .withValue(CalendarContract.Events.DTEND, utcMidnight(item["endDate"].toString()))
            } else {
                b.withValue(CalendarContract.Events.ALL_DAY, 0)
                    .withValue(CalendarContract.Events.EVENT_TIMEZONE, TimeZone.getDefault().id)
                    .withValue(CalendarContract.Events.DTSTART, (item["startMs"] as Number).toLong())
                    .withValue(CalendarContract.Events.DTEND, (item["endMs"] as Number).toLong())
            }
            ops.add(b.build())
            count++
        }
        // Large batches can exceed Android's 1 MB binder limit (TransactionTooLargeException) when a couple has
        // many events with long notes: apply the delete first, then the inserts in chunks of 100.
        context.contentResolver.applyBatch(CalendarContract.AUTHORITY, arrayListOf(ops[0]))
        ops.drop(1).chunked(100).forEach { chunk ->
            context.contentResolver.applyBatch(CalendarContract.AUTHORITY, ArrayList(chunk))
        }
        return count
    }

    fun removeCalendar(context: Context) {
        val id = findCalendar(context) ?: return
        context.contentResolver.delete(
            asSyncAdapter(Uri.withAppendedPath(CalendarContract.Calendars.CONTENT_URI, id.toString())), null, null)
    }
}
