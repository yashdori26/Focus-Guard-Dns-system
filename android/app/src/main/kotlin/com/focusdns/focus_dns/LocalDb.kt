package com.focusdns.focus_dns

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

/** Local SQLite store: key/value settings, rule sets (per source) and query logs. */
class LocalDb private constructor(ctx: Context) : SQLiteOpenHelper(ctx, "focusdns.db", null, 1) {

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE kv(k TEXT PRIMARY KEY, v TEXT NOT NULL)")
        db.execSQL("CREATE TABLE rules(kind TEXT NOT NULL, src TEXT NOT NULL, value TEXT NOT NULL, PRIMARY KEY(kind, src, value))")
        db.execSQL("CREATE TABLE logs(id INTEGER PRIMARY KEY AUTOINCREMENT, ts INTEGER NOT NULL, domain TEXT NOT NULL, status TEXT NOT NULL, rule TEXT NOT NULL)")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {}

    @Synchronized
    fun getKv(key: String, def: String = ""): String {
        readableDatabase.rawQuery("SELECT v FROM kv WHERE k=?", arrayOf(key)).use { c ->
            return if (c.moveToFirst()) c.getString(0) else def
        }
    }

    @Synchronized
    fun putKv(key: String, value: String) {
        val cv = ContentValues().apply { put("k", key); put("v", value) }
        writableDatabase.insertWithOnConflict("kv", null, cv, SQLiteDatabase.CONFLICT_REPLACE)
    }

    /** Replaces all values of [kind] that came from [src]. */
    @Synchronized
    fun replaceRules(kind: String, src: String, values: Collection<String>) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            db.delete("rules", "kind=? AND src=?", arrayOf(kind, src))
            for (v in values) {
                val clean = v.trim().lowercase()
                if (clean.isEmpty()) continue
                val cv = ContentValues().apply { put("kind", kind); put("src", src); put("value", clean) }
                db.insertWithOnConflict("rules", null, cv, SQLiteDatabase.CONFLICT_IGNORE)
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    /** Union of every source's values for [kind]. */
    @Synchronized
    fun getRules(kind: String): Set<String> {
        val out = HashSet<String>()
        readableDatabase.rawQuery("SELECT value FROM rules WHERE kind=?", arrayOf(kind)).use { c ->
            while (c.moveToNext()) out.add(c.getString(0))
        }
        return out
    }

    @Synchronized
    fun addLog(domain: String, status: String, rule: String) {
        val db = writableDatabase
        val cv = ContentValues().apply {
            put("ts", System.currentTimeMillis()); put("domain", domain); put("status", status); put("rule", rule)
        }
        db.insert("logs", null, cv)
        db.execSQL("DELETE FROM logs WHERE id <= (SELECT MAX(id) FROM logs) - 5000")
    }

    /** Returns query logs ordered newest-first, supporting optional filter. */
    @Synchronized
    fun getLogs(limit: Int = 100, offset: Int = 0, filter: String = "ALL"): List<Map<String, Any>> {
        val out = ArrayList<Map<String, Any>>()
        val sql: String
        val args: Array<String>
        if (filter.equals("BLOCKED", ignoreCase = true)) {
            sql = "SELECT id, ts, domain, status, rule FROM logs WHERE status='BLOCKED' ORDER BY id DESC LIMIT ? OFFSET ?"
            args = arrayOf(limit.toString(), offset.toString())
        } else if (filter.equals("ALLOWED", ignoreCase = true)) {
            sql = "SELECT id, ts, domain, status, rule FROM logs WHERE status='ALLOWED' ORDER BY id DESC LIMIT ? OFFSET ?"
            args = arrayOf(limit.toString(), offset.toString())
        } else {
            sql = "SELECT id, ts, domain, status, rule FROM logs ORDER BY id DESC LIMIT ? OFFSET ?"
            args = arrayOf(limit.toString(), offset.toString())
        }
        readableDatabase.rawQuery(sql, args).use { c ->
            while (c.moveToNext()) {
                out.add(mapOf(
                    "id" to c.getLong(0).toString(),
                    "timestampMs" to c.getLong(1),
                    "domain" to c.getString(2),
                    "status" to c.getString(3),
                    "reason" to c.getString(4)
                ))
            }
        }
        return out
    }

    /** Aggregates real query metrics across a specified window (hours). */
    @Synchronized
    fun getAggregatedStats(timeframeHours: Int = 168): Map<String, Any> {
        val cutoff = System.currentTimeMillis() - (timeframeHours.toLong() * 3600_000L)
        val cutoffStr = arrayOf(cutoff.toString())
        var total = 0
        var blocked = 0

        readableDatabase.rawQuery("SELECT COUNT(*) FROM logs WHERE ts >= ?", cutoffStr).use { c ->
            if (c.moveToFirst()) total = c.getInt(0)
        }
        readableDatabase.rawQuery("SELECT COUNT(*) FROM logs WHERE ts >= ? AND status='BLOCKED'", cutoffStr).use { c ->
            if (c.moveToFirst()) blocked = c.getInt(0)
        }

        val topBlocked = ArrayList<Map<String, Any>>()
        readableDatabase.rawQuery(
            "SELECT domain, COUNT(*) as cnt FROM logs WHERE ts >= ? AND status='BLOCKED' GROUP BY domain ORDER BY cnt DESC LIMIT 5",
            cutoffStr
        ).use { c ->
            while (c.moveToNext()) {
                val dom = c.getString(0)
                val cnt = c.getInt(1)
                val pct = if (blocked > 0) String.format("%.0f%%", (cnt.toDouble() / blocked.toDouble()) * 100.0) else "0%"
                topBlocked.add(mapOf("domain" to dom, "count" to cnt, "percentage" to pct))
            }
        }

        // Calculate 7-12 histogram bucket points for UI chart painting
        val bucketCount = if (timeframeHours <= 24) 8 else 7
        val bucketSpan = (timeframeHours.toLong() * 3600_000L) / bucketCount
        val bucketTotals = ArrayList<Int>()
        val bucketBlockeds = ArrayList<Int>()

        for (i in 0 until bucketCount) {
            val bStart = cutoff + (i * bucketSpan)
            val bEnd = bStart + bucketSpan
            val bArgs = arrayOf(bStart.toString(), bEnd.toString())
            var bTot = 0
            var bBlk = 0
            readableDatabase.rawQuery("SELECT COUNT(*) FROM logs WHERE ts >= ? AND ts < ?", bArgs).use { c ->
                if (c.moveToFirst()) bTot = c.getInt(0)
            }
            readableDatabase.rawQuery("SELECT COUNT(*) FROM logs WHERE ts >= ? AND ts < ? AND status='BLOCKED'", bArgs).use { c ->
                if (c.moveToFirst()) bBlk = c.getInt(0)
            }
            bucketTotals.add(bTot)
            bucketBlockeds.add(bBlk)
        }

        val ratio = if (total == 0) 0.0 else blocked.toDouble() / total.toDouble()
        val ratioStr = String.format("%.1f%%", ratio * 100.0)

        return mapOf(
            "totalQueries" to total,
            "blockedQueries" to blocked,
            "blockedPercentage" to ratioStr,
            "threatRatio" to ratio,
            "topBlockedDomains" to topBlocked,
            "bucketTotals" to bucketTotals,
            "bucketBlockeds" to bucketBlockeds
        )
    }

    @Synchronized
    fun clearLogs() {
        writableDatabase.execSQL("DELETE FROM logs")
    }

    companion object {
        @Volatile private var instance: LocalDb? = null
        fun get(ctx: Context): LocalDb =
            instance ?: synchronized(this) {
                instance ?: LocalDb(ctx.applicationContext).also { instance = it }
            }
    }
}
