package dev.andresmontano.netum_bluetooth_scanner.core

import android.content.Context

/** The saved-scanner list (JSON written by Dart) in the plugin's SharedPreferences. */
class SavedStore(context: Context) {
    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun load(): String? = prefs.getString(KEY, null)

    fun save(json: String) {
        prefs.edit().putString(KEY, json).apply()
    }

    private companion object {
        const val PREFS = "dev.andresmontano.netum_bluetooth_scanner"
        const val KEY = "saved_scanners"
    }
}
