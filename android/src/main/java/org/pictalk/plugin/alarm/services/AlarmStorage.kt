package org.pictalk.plugin.alarm.services

import org.pictalk.plugin.alarm.models.AlarmSettings

import android.content.Context
import com.getcapacitor.Logger
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.serialization.json.Json
import kotlinx.serialization.encodeToString
import java.util.TimeZone

const val SHARED_PREFERENCES_NAME = "AlarmSharedPreferences"

private val Context.dataStore: DataStore<Preferences> by
preferencesDataStore(SHARED_PREFERENCES_NAME)

class AlarmStorage(context: Context) {
    companion object {
        private const val TAG = "AlarmStorage"
        private const val PREFIX = "__alarm_id__"
        // The zone an alarm was scheduled in, to move it when the phone changes zone (not under PREFIX: getSavedAlarms reads those).
        private const val ZONE_PREFIX = "__alarm_zone__"
    }

    private val dataStore = context.dataStore

    fun saveAlarm(alarmSettings: AlarmSettings) {
        return runBlocking {
            val key = stringPreferencesKey("$PREFIX${alarmSettings.id}")
            val value = Json.encodeToString(alarmSettings)
            dataStore.edit { preferences ->
                preferences[key] = value
                preferences[stringPreferencesKey("$ZONE_PREFIX${alarmSettings.id}")] = TimeZone.getDefault().id
            }
        }
    }

    fun unsaveAlarm(id: Int) {
        return runBlocking {
            val key = stringPreferencesKey("$PREFIX$id")
            dataStore.edit { preferences ->
                preferences.remove(key)
                preferences.remove(stringPreferencesKey("$ZONE_PREFIX$id"))
            }
        }
    }

    /** Null for alarms saved before the zone was kept. */
    fun getAlarmZone(id: Int): TimeZone? {
        return runBlocking {
            dataStore.data.first()[stringPreferencesKey("$ZONE_PREFIX$id")]?.let { TimeZone.getTimeZone(it) }
        }
    }

    fun getSavedAlarms(): List<AlarmSettings> {
        return runBlocking {
            val preferences = dataStore.data.map { prefs ->
                prefs.asMap().filterKeys { it.name.startsWith(PREFIX) }
            }.first()

            val alarms = mutableListOf<AlarmSettings>()
            preferences.forEach { (key, value) ->
                if (value is String) {
                    try {
                        val alarm = Json.decodeFromString<AlarmSettings>(value)
                        alarms.add(alarm)
                    } catch (e: Exception) {
                        Logger.error(
                            TAG,
                            "Error parsing alarm settings for key ${key.name}: ${e.message}",
                            e
                        )
                    }
                } else {
                    Logger.warn(TAG, "Skipping non-alarm preference with key: ${key.name}")
                }
            }
            alarms
        }
    }
}