# Hearth Car Widget — Android → iOS Porting Spec

Precise extraction of the **Car widget vertical slice** plus the **Home Assistant client** from the Android/Kotlin/Jetpack Glance app `hearth` (package `com.rohit.hearth`), for a native Swift / WidgetKit reimplementation.

**Source (read-only):** `/Volumes/xHome/Github/hearth-cpauth/app/src/main/java/com/rohit/hearth/`
**Tests:** `/Volumes/xHome/Github/hearth-cpauth/app/src/test/java/com/rohit/hearth/`

> This document is a *spec*, not Swift. It reproduces the exact Kotlin so behaviour (types, nullability, defaults, parsing, formatting, color logic, tests) can be re-expressed 1:1 in Swift. All logic lives in pure Kotlin functions (`carFromTemplate`, `carView`, helpers) that are trivially portable; only the Glance `@Composable` rendering in `CarWidget.kt` is Android-specific and is summarised, not reproduced in full.

Key source files:

| Concern | File |
|---|---|
| Car model, template, parse, view-model, helpers | `CarState.kt` (265 lines) |
| Glance widget rendering + WorkManager receiver | `CarWidget.kt` (262 lines) |
| Repository + Worker (refresh/polling) | `CarRepository.kt` (99 lines) |
| HA REST client | `HaClient.kt` (166 lines) |
| HA config (persisted settings) | `HaConfig.kt` (138 lines) |
| HA OAuth (sign-in / token refresh) | `HaAuth.kt` (97 lines) |
| `DoorsTone` enum | `DoorsState.kt:34` |
| `beaconCarPair`, `beaconTireSummary`, `BeaconPair` + palette | `BeaconMetrics.kt:97-135` |
| `beaconCarEta`, `beaconNeedsSettings` | `BeaconPresentation.kt:29-49` |
| `sinceLabel`, `friendlyError` | `AlarmState.kt:50-61, 137-143` |
| `trustedSince`, `HaStart` (restart-stamp guard) | `HaStart.kt` |
| `beaconNow` | `BeaconChrome.kt:44` |

---

## 1. The `Car` data model

`CarState.kt:40-74`. **30 fields.** Immutable `data class` (Kotlin `data class` == Swift `struct` with value semantics — keep it a `struct`). Fields 1–19 are positional-required at the declaration site but many are nullable; fields 20 (`tires`) onward have defaults.

```kotlin
/** The car as Home Assistant last heard from it; null readings are ones it doesn't know. */
data class Car(
    val name: String,
    val battery: Int?,
    val range: Int?,
    val unit: String,
    val chargeState: String?,
    val plugged: Boolean,
    val chargerKw: Double?,
    val fullAt: Instant?,
    val limit: Int?,
    val locked: Boolean?,
    val open: List<String>,
    val tireWarning: Boolean,
    val sentry: Boolean,
    val place: String?,
    val inside: Int?,
    val tempUnit: String,
    val awake: Boolean?,
    val since: Instant?,
    /** Front left, front right, rear left, rear right; null if any isn't known. */
    val tires: List<Int>? = null,
    val pressureUnit: String = "",
    val outside: Int? = null,
    val odometer: Int? = null,
    /** Energy the last (or this) charge added, kWh. */
    val addedKwh: Double? = null,
    val climateOn: Boolean? = null,
    val sentryKnown: Boolean = true,
    val pluggedKnown: Boolean = true,
    val openKnown: Boolean = true,
    /** Keep pressure precision for integrations reporting bar. */
    val preciseTires: List<Double>? = null,
    val preciseInside: Double? = null,
    val preciseOutside: Double? = null,
)
```

Field-by-field (Kotlin type → suggested Swift type):

| # | Field | Kotlin type | Nullable | Default | Swift |
|---|---|---|---|---|---|
| 1 | `name` | `String` | no | — | `String` |
| 2 | `battery` | `Int?` | yes | — | `Int?` (percent 0–100) |
| 3 | `range` | `Int?` | yes | — | `Int?` |
| 4 | `unit` | `String` | no | — | `String` (e.g. `"mi"`) |
| 5 | `chargeState` | `String?` | yes | — | `String?` (lowercased) |
| 6 | `plugged` | `Boolean` | no | — | `Bool` |
| 7 | `chargerKw` | `Double?` | yes | — | `Double?` |
| 8 | `fullAt` | `Instant?` | yes | — | `Date?` |
| 9 | `limit` | `Int?` | yes | — | `Int?` |
| 10 | `locked` | `Boolean?` | yes | — | `Bool?` (null = unknown) |
| 11 | `open` | `List<String>` | no | — | `[String]` |
| 12 | `tireWarning` | `Boolean` | no | — | `Bool` |
| 13 | `sentry` | `Boolean` | no | — | `Bool` |
| 14 | `place` | `String?` | yes | — | `String?` |
| 15 | `inside` | `Int?` | yes | — | `Int?` |
| 16 | `tempUnit` | `String` | no | — | `String` |
| 17 | `awake` | `Boolean?` | yes | — | `Bool?` |
| 18 | `since` | `Instant?` | yes | — | `Date?` |
| 19 | `tires` | `List<Int>?` | yes | `null` | `[Int]?` (FL,FR,RL,RR) |
| 20 | `pressureUnit` | `String` | no | `""` | `String` |
| 21 | `outside` | `Int?` | yes | `null` | `Int?` |
| 22 | `odometer` | `Int?` | yes | `null` | `Int?` |
| 23 | `addedKwh` | `Double?` | yes | `null` | `Double?` |
| 24 | `climateOn` | `Boolean?` | yes | `null` | `Bool?` |
| 25 | `sentryKnown` | `Boolean` | no | `true` | `Bool` |
| 26 | `pluggedKnown` | `Boolean` | no | `true` | `Bool` |
| 27 | `openKnown` | `Boolean` | no | `true` | `Bool` |
| 28 | `preciseTires` | `List<Double>?` | yes | `null` | `[Double]?` |
| 29 | `preciseInside` | `Double?` | yes | `null` | `Double?` |
| 30 | `preciseOutside` | `Double?` | yes | `null` | `Double?` |

### Related view-model types (same file)

```kotlin
/** What a fact is about (its icon). */
enum class CarFactKind { Lock, Closed, Place, Tires, Sentry, Inside }

/** One thing worth knowing about the car ("Locked", "Frunk open"); [bad] ones are drawn in amber. */
data class CarFact(val kind: CarFactKind, val text: String, val bad: Boolean = false)

/**
 * Everything the car widget says: the headline ("57% · 175 mi"), the charge line, the [subline] under the big %
 * ("175 mi · Home", or "Charging 7 kW · full by 6:10 AM"), the chips, how old the readings are.
 */
data class CarView(
    val headline: String, val charge: String, val tone: DoorsTone, val facts: List<CarFact>, val asOf: String?, val tires: String? = null,
    val subline: String = "", val charging: Boolean = false, val sentry: Boolean = false,
)

/** The car widget's three designs, by its size: a charge ring (narrow), the hero (the car, 2 rows), the dashboard (taller). */
enum class CarLayout { Ring, Hero, Dashboard }

/** What the widget shows: the car now, or (no readings now) the last real ones, [stale]. */
data class CarShown(val car: Car, val stale: Boolean)
```

`DoorsTone` is **shared** with the Doors widget (`DoorsState.kt:34`):

```kotlin
/** The card's colour: all shut (green), something open (amber), a door open ≥ 30 min (red), not reporting (grey). */
enum class DoorsTone { Calm, Warn, Alert, Unknown }
```

> Note: There is **no** dedicated "doors/openings", "tires", or "charge" nested type. Doors/openings are modelled as a plain `List<String>` (`open`) of human labels (`"Door"`, `"Frunk"`, `"Trunk"`, `"Windows"`, `"Charge port"`). Tires are two parallel `List<Int>?`/`List<Double>?` (FL, FR, RL, RR). Charge is spread across `chargeState`/`plugged`/`chargerKw`/`fullAt`/`limit`/`addedKwh`.

---

## 2. Template → `Car` → view model

### 2a. The exact Home Assistant Jinja template (`CAR_TEMPLATE`)

`CarState.kt:18-37`. Sent verbatim as the `template` field of `POST /api/template`. It auto-discovers the Tesla integration's entity prefix (the `<prefix>_battery_range` sensor whose `lock.<prefix>_lock` exists), preferring one currently reporting a numeric battery level, else the first candidate (asleep). Returns `{"found": false}` or a JSON object with `found/prefix/name/unit/tempUnit/pressureUnit/statusSince/s`, where `s` maps `"domain.what"` → raw HA state string.

```kotlin
internal const val CAR_TEMPLATE = """
{%- set ns = namespace(p='', any='') -%}
{%- set locks = states.lock | map(attribute='entity_id') | list -%}
{%- for s in states.sensor if s.entity_id.endswith('_battery_range') -%}
  {%- set p = s.entity_id[7:-14] -%}
  {%- if ('lock.' ~ p ~ '_lock') in locks -%}
    {#- a car: its range and its lock; the one reporting now first, else one whose readings are all unknown (asleep, or its integration not reporting) -#}
    {%- if ns.p == '' and states('sensor.' ~ p ~ '_battery_level') | is_number -%}{%- set ns.p = p -%}{%- endif -%}
    {%- if ns.any == '' -%}{%- set ns.any = p -%}{%- endif -%}
  {%- endif -%}
{%- endfor -%}
{%- set p = ns.p or ns.any -%}
{%- if p == '' -%}{{ {'found': false} | to_json }}{%- else -%}
{%- set keys = ['sensor.battery_level', 'sensor.battery_range', 'sensor.charging', 'sensor.charger_power', 'sensor.time_to_full_charge', 'sensor.inside_temperature', 'binary_sensor.status', 'binary_sensor.charge_cable', 'binary_sensor.front_driver_door', 'binary_sensor.front_passenger_door', 'binary_sensor.rear_driver_door', 'binary_sensor.rear_passenger_door', 'binary_sensor.tire_pressure_warning_front_left', 'binary_sensor.tire_pressure_warning_front_right', 'binary_sensor.tire_pressure_warning_rear_left', 'binary_sensor.tire_pressure_warning_rear_right', 'cover.frunk', 'cover.trunk', 'cover.windows', 'cover.charge_port_door', 'lock.lock', 'switch.sentry_mode', 'device_tracker.location', 'number.charge_limit', 'sensor.tire_pressure_front_left', 'sensor.tire_pressure_front_right', 'sensor.tire_pressure_rear_left', 'sensor.tire_pressure_rear_right', 'sensor.outside_temperature', 'sensor.odometer', 'sensor.charge_energy_added', 'climate.climate'] -%}
{%- set out = namespace(s={}) -%}
{%- for k in keys -%}{%- set e = k.split('.')[0] ~ '.' ~ p ~ '_' ~ k.split('.')[1] -%}{%- set out.s = dict(out.s, **{k: states(e)}) -%}{%- endfor -%}
{%- set st = 'binary_sensor.' ~ p ~ '_status' -%}
{{ {'found': true, 'prefix': p, 'name': (state_attr('sensor.' ~ p ~ '_battery_level', 'friendly_name') or p) | replace(' Battery level', '') | replace(' battery level', ''), 'unit': state_attr('sensor.' ~ p ~ '_battery_range', 'unit_of_measurement') or 'mi', 'tempUnit': state_attr('sensor.' ~ p ~ '_inside_temperature', 'unit_of_measurement') or '', 'pressureUnit': state_attr('sensor.' ~ p ~ '_tire_pressure_front_left', 'unit_of_measurement') or '', 'statusSince': (states[st].last_changed.isoformat() if states[st] is defined and states[st] else none), 's': out.s} | to_json }}
{%- endif -%}
"""
```

**Reply JSON shape** (top-level fields consumed by `carFromTemplate`):

| Key | Type | Meaning |
|---|---|---|
| `found` | bool | false → no car (`carFromTemplate` returns null) |
| `prefix` | string | discovered entity prefix (not read by parser) |
| `name` | string | friendly name, " Battery level" suffix stripped |
| `unit` | string | range unit, default `"mi"` |
| `tempUnit` | string | inside-temp unit (`"°F"`/`"°C"`/`""`) |
| `pressureUnit` | string | tire-pressure unit (`"psi"`/`"bar"`/`""`) |
| `statusSince` | string/null | ISO-8601 of `binary_sensor.<p>_status.last_changed` |
| `s` | object | `"domain.what"` → raw state string |

The 31 `s` keys (domain.what): `sensor.battery_level`, `sensor.battery_range`, `sensor.charging`, `sensor.charger_power`, `sensor.time_to_full_charge`, `sensor.inside_temperature`, `binary_sensor.status`, `binary_sensor.charge_cable`, `binary_sensor.front_driver_door`, `binary_sensor.front_passenger_door`, `binary_sensor.rear_driver_door`, `binary_sensor.rear_passenger_door`, `binary_sensor.tire_pressure_warning_front_left`, `binary_sensor.tire_pressure_warning_front_right`, `binary_sensor.tire_pressure_warning_rear_left`, `binary_sensor.tire_pressure_warning_rear_right`, `cover.frunk`, `cover.trunk`, `cover.windows`, `cover.charge_port_door`, `lock.lock`, `switch.sentry_mode`, `device_tracker.location`, `number.charge_limit`, `sensor.tire_pressure_front_left/_front_right/_rear_left/_rear_right`, `sensor.outside_temperature`, `sensor.odometer`, `sensor.charge_energy_added`, `climate.climate`.

### 2b. `carFromTemplate(json: String?): Car?`

`CarState.kt:78-139`. Parses the reply into a `Car`, or null. **Exact parsing & "unknown" semantics are the crux of the port.**

```kotlin
private val UNKNOWN = setOf("unknown", "unavailable", "none", "")

/** The car from [CAR_TEMPLATE]'s reply; null if Home Assistant has no car. */
fun carFromTemplate(json: String?): Car? {
    val o = runCatching { JSONObject(json ?: return null) }.getOrNull() ?: return null
    if (!o.optBoolean("found")) return null
    val s = o.optJSONObject("s") ?: JSONObject()
    fun raw(k: String) = s.optString(k).trim().takeIf { it.lowercase() !in UNKNOWN }
    fun num(k: String) = raw(k)?.toDoubleOrNull()?.takeIf { it.isFinite() }
    fun on(k: String) = raw(k) == "on"
    fun time(v: String?) = v?.let { runCatching { OffsetDateTime.parse(it).toInstant() }.getOrNull() }
    val plugged = on("binary_sensor.charge_cable")
    val pluggedKnown = raw("binary_sensor.charge_cable") in setOf("on", "off")
    val open = listOfNotNull(
        "Door".takeIf { listOf("front_driver", "front_passenger", "rear_driver", "rear_passenger").any { on("binary_sensor.${it}_door") } },
        "Frunk".takeIf { raw("cover.frunk") == "open" },
        "Trunk".takeIf { raw("cover.trunk") == "open" },
        "Windows".takeIf { raw("cover.windows") == "open" },
        // open because it's plugged in: as it should be
        "Charge port".takeIf { raw("cover.charge_port_door") == "open" && pluggedKnown && !plugged },
    )
    return Car(
        name = o.optString("name").ifBlank { "Car" },
        battery = num("sensor.battery_level")?.roundToInt(),
        range = num("sensor.battery_range")?.roundToInt(),
        unit = o.optString("unit").ifBlank { "mi" },
        chargeState = raw("sensor.charging")?.lowercase(),
        plugged = plugged,
        chargerKw = num("sensor.charger_power"),
        fullAt = time(raw("sensor.time_to_full_charge")),
        limit = num("number.charge_limit")?.roundToInt(),
        locked = when (raw("lock.lock")) { "locked" -> true; "unlocked", "open" -> false; else -> null },
        open = open,
        tireWarning = listOf("front_left", "front_right", "rear_left", "rear_right").any { on("binary_sensor.tire_pressure_warning_$it") },
        sentry = on("switch.sentry_mode"),
        place = when (val p = raw("device_tracker.location")) {
            null -> null
            "home" -> "Home"
            "not_home" -> "Away"
            else -> p.replaceFirstChar { it.titlecase() }
        },
        inside = num("sensor.inside_temperature")?.roundToInt(),
        tempUnit = o.optString("tempUnit"),
        awake = raw("binary_sensor.status")?.let { it == "on" },
        since = time(o.optString("statusSince").takeIf { it.isNotBlank() && it != "null" }),
        tires = listOf("front_left", "front_right", "rear_left", "rear_right").map { num("sensor.tire_pressure_$it")?.roundToInt() }
            .takeIf { t -> t.all { it != null } }?.filterNotNull(),
        pressureUnit = o.optString("pressureUnit"),
        outside = num("sensor.outside_temperature")?.roundToInt(),
        odometer = num("sensor.odometer")?.roundToInt(),
        addedKwh = num("sensor.charge_energy_added")?.let { Math.round(it * 10) / 10.0 },
        climateOn = raw("climate.climate")?.let { it != "off" },
        sentryKnown = raw("switch.sentry_mode") in setOf("on", "off"),
        pluggedKnown = pluggedKnown,
        openKnown = listOf("front_driver", "front_passenger", "rear_driver", "rear_passenger")
            .all { raw("binary_sensor.${it}_door") in setOf("on", "off") } &&
            listOf("frunk", "trunk", "windows").all { raw("cover.$it") in setOf("open", "closed") } &&
            (plugged || raw("cover.charge_port_door") == "closed" ||
                (pluggedKnown && raw("cover.charge_port_door") == "open")),
        preciseTires = listOf("front_left", "front_right", "rear_left", "rear_right")
            .map { num("sensor.tire_pressure_$it") }.takeIf { it.all { n -> n != null && n.isFinite() } }?.filterNotNull(),
        preciseInside = num("sensor.inside_temperature"),
        preciseOutside = num("sensor.outside_temperature"),
    )
}
```

**Porting notes — reproduce exactly:**
- `raw(k)`: JSON string value, `.trim()`, then **null if (lowercased) is in `{"unknown","unavailable","none",""}`**. This `UNKNOWN` filtering is pervasive — any sensor not in the set of concrete values is treated as "not known", never as a default.
- `num(k)`: `raw` then parse to Double, **must `.isFinite()`** (rejects `NaN`/`Infinity` strings — see test §6). Ints come from `.roundToInt()`.
- `on(k)`: `raw(k) == "on"`.
- `time(v)`: parse `OffsetDateTime` (ISO-8601 with offset) → `Instant`, swallow failures → null.
- `locked`: `"locked"`→true; `"unlocked"`/`"open"`→false; **everything else (incl. `"locking"`, unknown)→null**.
- `plugged` = cable sensor `== "on"`. `pluggedKnown` = cable in `{"on","off"}`.
- `open` list order is fixed: Door, Frunk, Trunk, Windows, Charge port. "Charge port" only when open **and** `pluggedKnown && !plugged` (an open port while plugged is expected, not flagged).
- `openKnown`: true only when **all four doors** are `on`/`off` **and** frunk/trunk/windows are `open`/`closed` **and** (cable is confirmed connected OR charge-port is confirmed closed OR charge-port is open with cable state confirmed). An open port with unknown cable state cannot produce `All shut`; a confirmed closed port remains known even when cable state is unknown. The existing connected-cable exception still excludes the expected open charging port from warnings.
- `place`: `"home"`→`"Home"`, `"not_home"`→`"Away"`, else title-cased first char, null if unknown.
- `addedKwh`: rounded to 1 decimal via `Math.round(x*10)/10.0`.
- `climateOn`: null if unknown, else `(state != "off")`.
- `tires`: all four must be present (non-null) or the whole list is null. `preciseTires`: same but keeps Double precision and requires finite.
- `since`: from top-level `statusSince`; guarded against literal `"null"` / blank.

### 2c. `carToShow(current, lastGood): CarShown?`

`CarState.kt:216-220`. Decides whether to show fresh readings or fall back to the last good (stale) ones.

```kotlin
/** What the widget shows: the car now, or (no readings now) the last real ones, [stale]. */
data class CarShown(val car: Car, val stale: Boolean)

fun carToShow(current: Car?, lastGood: Car?): CarShown? = when {
    current == null -> null
    current.battery == null && lastGood?.battery != null -> CarShown(lastGood, stale = true)
    else -> CarShown(current, stale = false)
}
```

### 2d. `carView(...): CarView`

`CarState.kt:222-265`. Pure function `Car + now + zone + locale + stale` → `CarView`. **This is the primary string/colour formatter — port literally, including `" · "` joins and the amber/red tone precedence.**

```kotlin
fun carView(car: Car, now: Instant, zone: ZoneId = ZoneId.systemDefault(), locale: Locale = Locale.getDefault(), stale: Boolean = false): CarView {
    val headline = listOfNotNull(car.battery?.let { "$it%" }, car.range?.let { "$it ${car.unit}" }).joinToString(" · ").ifEmpty { "No reading" }
    val limit = car.limit?.let { " · limit $it%" }.orEmpty()
    val charge = when {
        car.chargeState in setOf("charging", "starting") -> listOfNotNull(
            "Charging",
            car.chargerKw?.takeIf { it > 0 }?.let { "${if (it % 1.0 == 0.0) it.toInt().toString() else "%.1f".format(locale, it)} kW" },
            car.fullAt?.takeIf { it.isAfter(now) }?.let { "full at ${clock(it, now, zone, locale)}" } ?: car.limit?.let { "to $it%" },
        ).joinToString(" · ")
        car.chargeState == "complete" -> car.limit?.let { "Charged to $it%" } ?: "Charged"
        car.plugged -> "Plugged in, not charging$limit"
        !car.pluggedKnown -> "Plug status unknown$limit"
        else -> "Not plugged in$limit"
    }
    val unlocked = car.locked == false
    val tone = when {
        unlocked && car.place != "Home" -> DoorsTone.Alert
        unlocked || car.open.isNotEmpty() || car.tireWarning || carLowBattery(car) -> DoorsTone.Warn
        else -> DoorsTone.Calm
    }
    // where it is goes under the charge, Sentry in the small print: the chips are what you'd check
    val facts = listOfNotNull(
        car.locked?.let { if (it) CarFact(CarFactKind.Lock, "Locked") else CarFact(CarFactKind.Lock, "Unlocked", bad = true) },
        if (car.open.isNotEmpty()) CarFact(CarFactKind.Closed, car.open.joinToString(", ") + " open", bad = true)
        else if (car.openKnown) CarFact(CarFactKind.Closed, "All shut") else CarFact(CarFactKind.Closed, "Openings unknown"),
        CarFact(CarFactKind.Tires, "Check tires", bad = true).takeIf { car.tireWarning },
        car.inside?.let { CarFact(CarFactKind.Inside, listOfNotNull("$it° in", car.outside?.let { o -> "$o° out" }).joinToString(" · ")) },
    )
    val charging = car.chargeState in setOf("charging", "starting")
    val subline = if (charging) listOfNotNull(
        "Charging" + (car.chargerKw?.takeIf { it > 0 }?.let { " ${if (it % 1.0 == 0.0) it.toInt().toString() else "%.1f".format(locale, it)} kW" } ?: ""),
        car.fullAt?.takeIf { it.isAfter(now) }?.let { "full by ${clock(it, now, zone, locale)}" },
    ).joinToString(" · ")
    else listOfNotNull(car.range?.let { "$it ${car.unit}" }, car.place).joinToString(" · ")
    // asleep, the car's readings are from when it fell asleep
    val asOf = if (stale) "No new readings from the car" + (sinceLabel(car.since, now, zone, locale)?.let { " · these are from ${it.removePrefix("since ")}" } ?: "")
    else when (car.awake) {
        true -> "Awake"
        false -> sinceLabel(car.since, now, zone, locale)?.let { "Asleep $it" } ?: "Asleep"
        null -> null
    }
    val tires = car.tires?.let { (fl, fr, rl, rr) -> "Tires $fl · $fr front, $rl · $rr rear ${car.pressureUnit}".trim() }
    return CarView(headline, charge, tone, facts, asOf, tires, subline, charging, car.sentry)
}
```

Private time formatter used above (`CarState.kt:204-207`):

```kotlin
private fun clock(at: Instant, now: Instant, zone: ZoneId, locale: Locale): String {
    val days = ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), at.atZone(zone).toLocalDate())
    return at.atZone(zone).format(DateTimeFormatter.ofPattern(if (days == 0L) "h:mm a" else "EEE h:mm a", locale))
}
```

**`carView` logic to reproduce exactly:**
- `headline`: `"<battery>%"` and `"<range> <unit>"` joined by `" · "`; `"No reading"` if both null.
- `charge` (priority): charging/starting → `"Charging"` [+ `"N kW"` if kW>0] [+ `"full at <clock>"` if `fullAt` future, else `"to <limit>%"`]; `complete` → `"Charged to N%"` or `"Charged"`; plugged → `"Plugged in, not charging"` + optional `" · limit N%"`; `!pluggedKnown` → `"Plug status unknown"` + limit; else `"Not plugged in"` + limit.
- `tone`: unlocked **and** not Home → `Alert`; else if unlocked OR any openings OR tire warning OR `carLowBattery` → `Warn`; else `Calm`.
- `facts` order: Lock (`"Locked"` / `"Unlocked"`bad) → openings (`"<list> open"`bad / `"All shut"` / `"Openings unknown"`) → optional `"Check tires"`bad → optional inside temp (`"<in>° in · <out>° out"`).
- `subline`: if charging → `"Charging[ N kW]"` + optional `"full by <clock>"`; else `"<range> <unit>"` + `place`.
- `asOf`: if stale → `"No new readings from the car"` + optional `" · these are from <when>"`; else by `awake`: true→`"Awake"`, false→`"Asleep <sinceLabel>"` or `"Asleep"`, null→null.
- `tires` string: `"Tires FL · FR front, RL · RR rear <unit>"` then trimmed (uses the rounded-Int `tires`, not `preciseTires`).
- kW formatting: integer if whole (`7 kW`), else one decimal with locale (`7.5 kW`); never shown when `0`.

### Layout sizing (optional for Widget — only if you reproduce 3 size classes)

`CarState.kt:142-178`:

```kotlin
/** A dashboard panel's height at 1× text, and the gap above a row of them. */
const val CAR_PANEL_DP = 72f
private const val CAR_PANEL_GAP_DP = 8f

private fun dashboardDp(fontScale: Float) = 54f + 228f * maxOf(1f, fontScale)

/** Rows of panels (0–2) in the [roomDp] left under the hero: tyres and cabin first, then last charge and odometer. */
fun carPanelRows(roomDp: Float, fontScale: Float): Int =
    (roomDp / (CAR_PANEL_DP * maxOf(1f, fontScale) + CAR_PANEL_GAP_DP)).toInt().coerceIn(0, 2)

fun carLayout(innerWidthDp: Float, heightDp: Float, fontScale: Float): CarLayout = when {
    innerWidthDp < 300f -> CarLayout.Ring
    heightDp - 28f >= dashboardDp(fontScale) -> CarLayout.Dashboard
    else -> CarLayout.Hero
}
```

---

## 3. `DoorsTone` and `beaconCarPair` (state → tone/colour)

`DoorsTone` (`DoorsState.kt:34`) — see §1. It is the tone type `carView` returns.

`beaconCarPair` (`BeaconMetrics.kt:121-127`) maps the car's tone + flags to a fill/ink colour pair. **`stale` or no reading wins (grey); then Alert red; Warn amber; charging blue; else mint.**

```kotlin
fun beaconCarPair(tone: DoorsTone, charging: Boolean, stale: Boolean, hasReading: Boolean): BeaconPair = when {
    stale || !hasReading -> BeaconOffline
    tone == DoorsTone.Alert -> BeaconRed
    tone == DoorsTone.Warn -> BeaconYellow
    charging -> BeaconBlue
    else -> BeaconMint
}
```

`BeaconPair` + the palette (`BeaconMetrics.kt:97-102`). Colours are `0xAARRGGBB` `Long`s (fill, ink):

```kotlin
data class BeaconPair(val fillArgb: Long, val inkArgb: Long)
val BeaconOffline = BeaconPair(0xFFBCC2B9, 0xFF29342D)
val BeaconBlue    = BeaconPair(0xFFA6D5FF, 0xFF1C3B53)
val BeaconRed     = BeaconPair(0xFFF2A0A4, 0xFF4D2029)
val BeaconYellow  = BeaconPair(0xFFF6D58A, 0xFF493614)
val BeaconMint    = BeaconPair(0xFFB6D9C1, 0xFF244232)
```

| Condition | Pair | fill |
|---|---|---|
| `stale \|\| !hasReading` | `BeaconOffline` (grey) | `0xFFBCC2B9` |
| `tone == Alert` | `BeaconRed` | `0xFFF2A0A4` |
| `tone == Warn` | `BeaconYellow` | `0xFFF6D58A` |
| `charging` | `BeaconBlue` | `0xFFA6D5FF` |
| else (Calm, has reading) | `BeaconMint` | `0xFFB6D9C1` |

> In `CarWidget.kt` the battery-bar fill specifically overrides mint to a brighter `0xFF8FF0C4` (`rail == BeaconMint ? 0xFF8FF0C4 : rail.fillArgb`). Sentry-ON ink uses `0xFFB3261E` (light) / `0xFFF2A0A4` (dark).

---

## 4. Car helper functions (exact code)

### `carLowBattery` — `CarState.kt:181-185`

```kotlin
/** Low enough to want charging tonight. */
private const val LOW_BATTERY = 20

/** A low battery is only a "charge me" warning when we actually know the car isn't plugged in. */
fun carLowBattery(car: Car): Boolean =
    car.battery != null && car.battery <= LOW_BATTERY && car.pluggedKnown && !car.plugged
```

### `carChargeShort` — `CarState.kt:193-202`

The compact/Beacon charge line, deliberately kept parallel to `carView`'s `charge`/`subline`.

```kotlin
fun carChargeShort(car: Car?, withPower: Boolean, locale: Locale = Locale.getDefault()): String = when {
    car?.battery == null -> "No reading"
    car.chargeState in setOf("charging", "starting") -> listOfNotNull("Charging",
        car.chargerKw?.takeIf { withPower && it > 0 }?.let { "${if (it % 1.0 == 0.0) it.toInt().toString() else "%.1f".format(locale, it)} kW" },
    ).joinToString(" · ")
    car.chargeState == "complete" -> "Charged"
    car.plugged -> "Plugged in"
    car.pluggedKnown -> "Unplugged"
    else -> "Plug status —"
}
```

Outputs: `"No reading"` (no battery) · `"Charging"` [+ `" · N kW"` only if `withPower && kW>0`] · `"Charged"` · `"Plugged in"` · `"Unplugged"` · `"Plug status —"`.

### `beaconCarEta` — `BeaconPresentation.kt:45-49`

```kotlin
internal fun beaconCarEta(at: Instant?, now: Instant, zone: ZoneId = ZoneId.systemDefault(), locale: Locale = Locale.getDefault()): String? =
    at?.takeIf { it.isAfter(now) }?.let {
        val sameDay = now.atZone(zone).toLocalDate() == it.atZone(zone).toLocalDate()
        "Full by " + it.atZone(zone).format(DateTimeFormatter.ofPattern(if (sameDay) "h:mm a" else "EEE h:mm a", locale))
    }
```

Returns null if `at` is null or not strictly after `now`; else `"Full by h:mm a"` (same local day) or `"Full by EEE h:mm a"` (different day).

### `beaconTireSummary` — `BeaconMetrics.kt:129-135`

```kotlin
fun beaconTireSummary(car: Car?): String {
    if (car == null) return "—"
    val tires = car.preciseTires ?: car.tires?.map(Int::toDouble) ?: return "—"
    fun fmt(n: Double) = if (car.pressureUnit.equals("bar", true)) "%.1f".format(java.util.Locale.getDefault(), n)
        else n.roundToInt().toString()
    return "${fmt(tires.min())}–${fmt(tires.max())}${car.pressureUnit.takeIf { it.isNotBlank() }?.let { " $it" }.orEmpty()}"
}
```

`"<min>–<max>[ unit]"`, prefers `preciseTires`; **bar keeps 1 decimal, everything else rounds to Int**. Note the separator is an en-dash `–` (U+2013), not a hyphen. `"—"` (em-dash, U+2014) when no car / no tire data.

### Temperature / pressure / number formatting

`number(...)` — local in `CarWidget.kt:238` (integer if whole, else 1 decimal, default locale):

```kotlin
private fun number(n: Double) = if (n % 1.0 == 0.0) n.toInt().toString() else "%.1f".format(n)
```

Used in the widget for Cabin/Outside temps (`"${number(it)}${tempUnit.ifBlank { "°" }}"`), charge energy (`"${number(it)} kWh"`), and per-tire pressures (`"${number(it)} <pressureUnit>"`). Odometer uses `"%,d %s".format(odometer, unit)` (grouped thousands). The inline kW formatter (`if (it % 1.0 == 0.0) it.toInt() else "%.1f".format(locale, it)`) recurs in `carView`/`carChargeShort`; factor it into a shared Swift helper.

`sinceLabel` — `AlarmState.kt:50-61` (shared; used by `carView`'s `asOf`):

```kotlin
/** "since 9:42 AM" today, "since Mon 9:42 PM" this week, else "since Oct 3". */
fun sinceLabel(changed: Instant?, now: Instant, zone: ZoneId = ZoneId.systemDefault(), locale: Locale = Locale.getDefault()): String? {
    if (changed == null) return null
    val then = changed.atZone(zone)
    val today = now.atZone(zone).toLocalDate()
    val days = ChronoUnit.DAYS.between(then.toLocalDate(), today)
    val pattern = when {
        days == 0L -> "h:mm a"
        days in 1..6 -> "EEE h:mm a"
        else -> "MMM d"
    }
    return "since " + then.format(DateTimeFormatter.ofPattern(pattern, locale))
}
```

`beaconNeedsSettings` / `friendlyError` (used by the refresh error path and whether the widget shows a Settings CTA vs a Retry):

```kotlin
// BeaconPresentation.kt:30-33
internal fun beaconNeedsSettings(error: String?): Boolean = error?.let {
    it.startsWith("Set up", true) || it.contains("sign in", true) || it.contains("sign-in", true) ||
        it.contains("check the entity", true) || it.contains("check the token", true)
} == true

// AlarmState.kt:137-143
fun friendlyError(e: Throwable): String = when (e) {
    is HaClient.HaError -> e.message ?: "Home Assistant didn't answer"
    is java.net.UnknownHostException, is java.net.ConnectException, is java.net.SocketTimeoutException,
    is javax.net.ssl.SSLException, is java.net.NoRouteToHostException -> "Can't reach Home Assistant"
    is java.io.IOException -> "Can't reach Home Assistant"
    else -> "Couldn't check the alarm"
}
```

---

## 5. Home Assistant client & config

### 5a. HA endpoint paths (full inventory)

All relative to `config.baseUrl` with trailing `/` trimmed. The **car widget itself only uses `POST /api/template`** (plus `POST /auth/token` for sign-in refresh, and `HaStart` issues another `POST /api/template`). The rest are listed for completeness since the client is shared.

| Method | Path | Used by |
|---|---|---|
| `POST` | `/auth/token` | `HaAuth.exchange` / `HaAuth.renew` (OAuth) |
| (browser) | `/auth/authorize?response_type=code&client_id=…&redirect_uri=…&state=…` | `HaAuth.startUrl` (sign-in) |
| `POST` | `/api/template` | **`HaClient.template` — car widget + `HaStart`** |
| `GET` | `/api/states` | `entities(prefix)`, `allStatesJson()` |
| `GET` | `/api/states/{entityId}` | `state()`, `lockState()`, `stateJson(id)` |
| `GET` | `/api/config` | `homeName()` |
| `GET` | `/api/logbook/{since}?entity={ids}` | `logbookJson()` |
| `POST` | `/api/services/{domain}/{service}` | `callService()` |
| `POST` | `/api/services/alarm_control_panel/{service}` | alarm `call()` |
| `POST` | `/api/services/lock/{service}` | lock `call()` |
| `GET` | `/api/hearth/update` | `updateInfo()` |
| `GET` | `/api/hearth/update/apk` | `downloadUpdate()` |

### 5b. Auth flow (OAuth) — `HaAuth.kt`

HA's native "Sign in with Home Assistant" authorization-code flow. `client_id` is the dashboard page HA serves; redirect URI `hearth://auth-callback`.

```kotlin
object HaAuth {
    const val REDIRECT = "hearth://auth-callback"
    fun clientId(baseUrl: String) = baseUrl.trimEnd('/') + "/dashboard/"
    // startUrl(...) opens: <baseUrl>/auth/authorize?response_type=code&client_id=<clientId>&redirect_uri=hearth://auth-callback&state=<uuid>

    data class Tokens(val access: String, val expiresAt: Long, val refresh: String?)

    /** The one-time code → access token + refresh token. */
    suspend fun exchange(baseUrl: String, code: String): Tokens =
        token(baseUrl, mapOf("grant_type" to "authorization_code", "code" to code, "client_id" to clientId(baseUrl)))

    suspend fun renew(baseUrl: String, refresh: String): Tokens =
        token(baseUrl, mapOf("grant_type" to "refresh_token", "refresh_token" to refresh, "client_id" to clientId(baseUrl)))

    private suspend fun token(baseUrl: String, form: Map<String, String>): Tokens = withContext(Dispatchers.IO) {
        val conn = URL(baseUrl.trimEnd('/') + "/auth/token").openConnection() as HttpURLConnection
        try {
            conn.requestMethod = "POST"
            conn.connectTimeout = 8_000
            conn.readTimeout = 10_000
            conn.doOutput = true
            conn.setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
            val body = form.entries.joinToString("&") { (k, v) -> "$k=" + URLEncoder.encode(v, "UTF-8") }
            conn.outputStream.use { it.write(body.toByteArray()) }
            if (conn.responseCode !in 200..299) throw HaClient.HaError(if (conn.responseCode == 400) "Signed out: sign in again" else "Sign-in failed (${conn.responseCode})")
            val o = JSONObject(conn.inputStream.bufferedReader().use { it.readText() })
            Tokens(
                access = o.getString("access_token"),
                expiresAt = System.currentTimeMillis() + o.optLong("expires_in", 1800) * 1000,
                refresh = o.optString("refresh_token").takeIf { it.isNotBlank() },
            )
        } finally { conn.disconnect() }
    }

    // A short-lived access token, renewed from the refresh token a minute before it runs out.
    private val lock = Mutex()
    private var cached: Pair<String, Tokens>? = null // refresh token → its current access token

    suspend fun accessToken(config: HaConfig): String = lock.withLock {
        val c = cached
        if (c != null && c.first == config.refreshToken && c.second.expiresAt - 60_000 > System.currentTimeMillis()) return c.second.access
        val t = renew(config.baseUrl, config.refreshToken)
        cached = config.refreshToken to t
        t.access
    }

    fun forget() { cached = null }
}
```

**Auth porting notes:**
- **Token endpoint:** `POST <base>/auth/token`, `Content-Type: application/x-www-form-urlencoded`, body is `key=urlencoded(value)` joined by `&`.
  - Exchange body: `grant_type=authorization_code&code=<code>&client_id=<base>/dashboard/`
  - Refresh body: `grant_type=refresh_token&refresh_token=<refresh>&client_id=<base>/dashboard/`
- Response JSON: `access_token` (required), `expires_in` (seconds, default **1800**), `refresh_token` (optional; refresh calls usually omit it).
- `expiresAt` = `now + expires_in*1000` (ms epoch).
- **Access-token cache:** in-memory, keyed by refresh token; reused until **60 s before expiry**, then re-renewed. Concurrency-guarded by a mutex (Swift: `actor` or lock). `forget()` clears it on 401.
- HTTP 400 on token → `"Signed out: sign in again"`; other non-2xx → `"Sign-in failed (<code>)"`.
- Timeouts: connect 8 s, read 10 s.

### 5c. Request plumbing & the template / all-states methods — `HaClient.kt`

```kotlin
class HaClient(private val config: HaConfig) {
    class HaError(message: String, val code: Int = 0) : IOException(message)

    /** Renders a Home Assistant template (used to find what belongs with the thermostat). */
    suspend fun template(template: String): String =
        request("POST", "/api/template", JSONObject().put("template", template).toString())

    /** Every entity's state (a JSON array): to find the doors. */
    suspend fun allStatesJson(): String = request("GET", "/api/states", null)

    suspend fun stateJson(entityId: String): String = request("GET", "/api/states/$entityId", null)

    /** A pasted token as is; a sign-in gives a short-lived access token (renewed as needed). */
    private suspend fun bearer(): String = if (config.token.isNotBlank()) config.token else HaAuth.accessToken(config)

    private suspend fun request(method: String, path: String, json: String?): String {
        val token = bearer()
        return withContext(Dispatchers.IO) { send(method, path, json, token) }
    }

    private fun send(method: String, path: String, json: String?, token: String): String {
        val conn = URL(config.baseUrl.trimEnd('/') + path).openConnection() as HttpURLConnection
        try {
            conn.requestMethod = method
            conn.connectTimeout = 8_000
            conn.readTimeout = 10_000
            conn.setRequestProperty("Authorization", "Bearer $token")
            conn.setRequestProperty("Content-Type", "application/json")
            if (json != null) {
                conn.doOutput = true
                conn.outputStream.use { it.write(json.toByteArray()) }
            }
            val code = conn.responseCode
            if (code == 401) {
                HaAuth.forget()
                throw HaError(if (config.isSignedIn) "Signed out: sign in again" else "Sign-in rejected: check the token", code)
            }
            if (code == 404) throw HaError("Alarm not found: check the entity", code)
            if (code !in 200..299) throw HaError("Home Assistant replied $code", code)
            return conn.inputStream.bufferedReader().use { it.readText() }
        } finally { conn.disconnect() }
    }
}
```

**Client porting notes:**
- **Template method (car's call):** `POST <base>/api/template`, headers `Authorization: Bearer <token>` + `Content-Type: application/json`, body `{"template": "<CAR_TEMPLATE>"}`. **Response is a raw string** (HA renders the template; here it's the JSON text the template emits — the car code then `JSONObject(...)`-parses it).
- **All-states:** `GET <base>/api/states` → JSON array of `{entity_id, state, attributes:{…}}`.
- **Bearer selection:** if `config.token` (pasted long-lived token) is non-blank, use it verbatim; otherwise fetch a cached/renewed OAuth access token via `HaAuth.accessToken(config)`.
- **Status handling:** 401 → `HaAuth.forget()` + `HaError` (`"Signed out…"` if signed-in, else `"Sign-in rejected: check the token"`); 404 → `HaError("Alarm not found: check the entity")`; other non-2xx → `HaError("Home Assistant replied <code>")`. `HaError.code` carries the HTTP status (0 if none).
- Timeouts: connect 8 s, read 10 s. All network on IO dispatcher.

### 5d. `HaConfig` — persisted settings — `HaConfig.kt`

Primary constructor (every stored field + default). Only `baseUrl`, `token`, `entityId` are positionally required; the rest default.

```kotlin
data class HaConfig(val baseUrl: String, val token: String, val entityId: String, val refreshToken: String = "", val lockId: String = "", val lockName: String = "", val confirmWith: String = CONFIRM_BIOMETRIC,
    val climateId: String = "", val comfortId: String = "", val resumeId: String = "", val sensorsJson: String = "[]",
    val doorIdsJson: String = "[]",
    val scriptIdsJson: String = "[]",
    val lightPinsJson: String = "[]",
    val favouriteIdsJson: String = "[]",
)
```

| Field | Type | Default | SharedPrefs key | Notes |
|---|---|---|---|---|
| `baseUrl` | `String` | — | `url` | must `startsWith("https://")` |
| `token` | `String` | — | `token` | pasted long-lived token (blank if signed-in) |
| `entityId` | `String` | — | `entity` | alarm entity (`alarm_control_panel.…`) |
| `refreshToken` | `String` | `""` | `refresh` | OAuth refresh token |
| `lockId` | `String` | `""` | `lock` | `lock.…` |
| `lockName` | `String` | `""` | `lock_name` | |
| `confirmWith` | `String` | `CONFIRM_BIOMETRIC` (`"biometric"`) | `confirm` | or `"dialog"` |
| `climateId` | `String` | `""` | `climate` | |
| `comfortId` | `String` | `""` | `comfort` | |
| `resumeId` | `String` | `""` | `resume` | |
| `sensorsJson` | `String` | `"[]"` | `sensors` | JSON array |
| `doorIdsJson` | `String` | `"[]"` | `doors` | JSON array |
| `scriptIdsJson` | `String` | `"[]"` | `scripts` | JSON array |
| `lightPinsJson` | `String` | `"[]"` | `light_pins` | JSON array |
| `favouriteIdsJson` | `String` | `"[]"` | `favourites` | JSON array |

Derived (computed) properties:

```kotlin
val favouriteIds: List<String>   // parse favouriteIdsJson
val lightPins: Set<String>       // parse lightPinsJson
val scriptIds: List<String>      // parse scriptIdsJson
val doorIds: List<String>        // parse doorIdsJson
val hasClimate get() = climateId.startsWith("climate.") && baseUrl.startsWith("https://") && hasAuth
val confirmWithBiometric get() = confirmWith != CONFIRM_DIALOG
val hasLock get() = lockId.startsWith("lock.")
val isSignedIn get() = refreshToken.isNotBlank()
val hasAuth get() = token.isNotBlank() || isSignedIn
val isComplete get() = baseUrl.startsWith("https://") && hasAuth && entityId.startsWith("alarm_control_panel.")
```

> **There is no car-specific config field.** The car is auto-discovered by `CAR_TEMPLATE` at query time (no stored "car entity"). The only config the car refresh needs: `baseUrl` (must be `https://`) and `hasAuth` (a pasted token or a refresh token). See `CarRepository.refresh` guard in §7. Constants: `CONFIRM_BIOMETRIC = "biometric"`, `CONFIRM_DIALOG = "dialog"`.
>
> **Storage:** Android uses `EncryptedSharedPreferences` (AES256-SIV keys / AES256-GCM values, Android Keystore master key), file `"ha_config"`. iOS equivalent: **Keychain** (or an App-Group-shared encrypted store, since the widget extension must read it). There is also a debug-only `provision.json` import path (adb) that can be ignored for iOS.

---

## 6. Car unit tests → input/expected (for Swift test re-expression)

**23 car-related test methods.** All timing tests use zone `America/Los_Angeles` and `Locale.US`. `CarStateTest` uses `now = 2026-10-14T09:30:00Z` (= 2:30 AM PDT) and a default `statusSince = 2026-10-14T05:33:23.678473+00:00` (= Tue 10:33 PM PDT previous evening).

### `CarStateTest.kt` (16 tests)

The shared `reply(...)` baseline `s` map (overridable per test) represents the car asleep at home, locked, unplugged: battery `57`, range `175.31`, charging `disconnected`, charger_power `0`, time_to_full_charge `unavailable`, inside_temperature `68.9`, status `off`, charge_cable `off`, all four doors `off`, all four tire warnings `off`, frunk/trunk/windows/charge_port_door `closed`, lock `locked`, sentry `off`, location `home`, charge_limit `80`, tire pressures `39.16 / 39.52 / 39.52 / 40.25`. Top-level: `name="Stargate"`, `unit="mi"`, `tempUnit="°F"`, `pressureUnit="psi"`. `view(json) = carView(carFromTemplate(json)!!, now, zone, Locale.US)`.

| # | Test | Input (delta from baseline) | Expected |
|---|---|---|---|
| 1 | no car found reads as none | `{"found": false}` | `carFromTemplate` → `null` |
| 2 | asleep at home, locked, unplugged | baseline | `headline="57% · 175 mi"`; `charge="Not plugged in · limit 80%"`; `tone=Calm`; `facts.text=["Locked","All shut","69° in"]`; `asOf="Asleep since Tue 10:33 PM"`; `tires="Tires 39 · 40 front, 40 · 40 rear psi"` |
| 3 | charging says how fast + when full | charging=`charging`, cable=`on`, power=`7`, ttf=`2026-10-14T13:10:00+00:00`, port=`open`, status=`on` | `charge="Charging · 7 kW · full at 6:10 AM"`; `facts[1].text="All shut"` (open port while plugged not flagged); `asOf="Awake"` |
| 4 | charged and plugged in | (a) charging=`complete`, cable=`on`  (b) charging=`stopped`, cable=`on` | (a) `charge="Charged to 80%"`  (b) `charge="Plugged in, not charging · limit 80%"` |
| 5 | unlocked/open amber, unlocked-away red | (a) frunk=`open`, rear_driver_door=`on`  (b) lock=`unlocked`  (c) lock=`unlocked`, location=`not_home` | (a) `tone=Warn`, `facts[1].text="Door, Frunk open"`, `facts[1].bad=true`  (b) `tone=Warn`  (c) `tone=Alert`, `facts.text=["Unlocked","All shut","69° in"]` |
| 6 | low+unplugged amber, tire warning is a fact | (a) battery=`18`  (b) tire_warning_rear_left=`on`, sentry=`on` | (a) `tone=Warn`  (b) `facts.text=["Locked","All shut","Check tires","69° in"]`, `tone=Warn` |
| 7 | low battery warns only when known unplugged | (a) battery=`18`, cable=`unavailable`  (b) battery=`18`  (c) battery=`18`, cable=`on` | (a) `tone=Calm`  (b) `tone=Warn`  (c) `tone=Calm` |
| 8 | open charge port flagged only if known unplugged | (a) port=`open`, cable=`unavailable`  (b) port=`open`, cable=`off` | (a) `car.open == []`  (b) `car.open == ["Charge port"]` |
| 9 | short charge line parallel across layouts | via `car(charging, kw, cable)` + `carChargeShort` | `carChargeShort(complete,on,withPower=true)="Charged"`; `(complete,on,false)="Charged"`; `(charging,7,on,true)="Charging · 7 kW"`; `(charging,0,on,true)="Charging"`; `(charging,7,on,false)="Charging"`; `(disconnected,off,true)="Unplugged"`; `(disconnected,unavailable,true)="Plug status —"` |
| 10 | unknown readings left out | range=`unavailable`, inside=`unknown`, lock=`unavailable`, since=`null` | `headline="57%"`; `facts.text=["All shut"]`; `asOf="Asleep"`; and separately (`tire_pressure_rear_left=unknown`) → `tires == null` |
| 11 | subline: range+where, or charging | (a) baseline  (b) charging=`charging`, cable=`on`, power=`7`, ttf=`2026-10-14T13:10:00+00:00`  (c) location=`not_home` | (a) `subline="175 mi · Home"`  (b) `subline="Charging 7 kW · full by 6:10 AM"`  (c) `subline="175 mi · Away"` |
| 12 | dashboard readings / odometer / last charge / cabin | outside=`55.4`, odometer=`20961.011817`, charge_energy_added=`20.82`, climate=`off`, sentry=`on` | `car.outside=55`; `car.odometer=20961`; `car.addedKwh≈20.8`; `car.climateOn=false`; `view.facts.last().text="69° in · 55° out"`; `view.sentry=true`; `car.tires==[39,40,40,40]` |
| 13 | design follows size | `carLayout(w,h,scale)` | `(272,200,1)=Ring`; `(352,180,1)=Hero`; `(352,290,1)=Hero`; `(315,343,1.1)=Dashboard`; `(352,340,1.3)=Hero` |
| 14 | panel rows by height left | `carPanelRows(room,scale)` | `(60,1)=0`; `(90,1)=1`; `(170,1)=2`; `(170,1.3)=1` |
| 15 | no readings keeps last good, stale | `good=baseline`; `empty=`(battery/range/lock/status all `unknown`) | `carToShow(empty,good)=CarShown(good,stale=true)`; `carToShow(good,empty)=CarShown(good,stale=false)`; `carToShow(empty,null)=CarShown(empty,stale=false)`; `carToShow(null,good)=null` |
| 16 | old readings say so vs asleep/awake | `carView(baseline, …, stale=true)` | `asOf="No new readings from the car · these are from Tue 10:33 PM"` |

### `CarAvailabilityTest.kt` (5 tests) — raw JSON inputs

| # | Test | Input JSON (`s` shown) | Expected |
|---|---|---|---|
| 1 | unavailable security telemetry not reported as off/shut | `battery_level=57, sentry_mode=unavailable, charge_cable=unknown, lock.lock=locking` | `sentryKnown=false`; `pluggedKnown=false`; `openKnown=false`; `locked=null`; `view.charge` does **not** start with `"Not plugged"`; no fact text `"All shut"` |
| 2 | known-open trunk reported though another opening unknown | `battery_level=57, cover.trunk=open, sentry_mode=off, charge_cable=off` | `sentryKnown=true`; `pluggedKnown=true`; `openKnown=false`; `open==["Trunk"]`; `carView.tone=Warn` |
| 3 | pressure keeps decimals for bar | `pressureUnit="bar"`, tire pressures `2.7/2.8/2.6/2.7` | `preciseTires==[2.7,2.8,2.6,2.7]`; `beaconTireSummary=="2.6–2.8 bar"` (en-dash) |
| 4 | celsius keeps decimals, unknown stays unknown | `tempUnit="°C"`, inside=`21.5`, outside=`-2.5` | `preciseInside==21.5`; `preciseOutside==-2.5` |
| 5 | nonfinite can't become huge values | `battery_level=NaN, charge_limit=Infinity, inside_temperature=Infinity` | `battery=null`; `limit=null`; `inside=null` |

### `beaconCarPair` — `BeaconMetricsTest.kt:160-167`

```kotlin
assertEquals(0xFFB6D9C1, beaconCarPair(DoorsTone.Calm, false, false, true).fillArgb)  // mint (calm, has reading)
assertEquals(0xFFA6D5FF, beaconCarPair(DoorsTone.Calm, true,  false, true).fillArgb)  // blue (charging)
assertEquals(0xFFF6D58A, beaconCarPair(DoorsTone.Warn, true,  false, true).fillArgb)  // amber (warn > charging)
assertEquals(0xFFF2A0A4, beaconCarPair(DoorsTone.Alert,true,  false, true).fillArgb)  // red (alert)
assertEquals(0xFFBCC2B9, beaconCarPair(DoorsTone.Alert,true,  true,  true).fillArgb)  // grey (stale wins)
assertEquals(0xFFBCC2B9, beaconCarPair(DoorsTone.Calm, false, false, false).fillArgb) // grey (no reading)
```

### `beaconCarEta` — `BeaconPresentationTest.kt:44-51`

`now = 2026-10-20T17:00:00Z`, zone `America/Los_Angeles`, `Locale.US`:

```kotlin
assertNull(beaconCarEta(now.minusSeconds(1), now, zone, Locale.US))               // past → null
assertNull(beaconCarEta(now, now, zone, Locale.US))                               // == now → null
assertEquals("Full by 11:00 AM",     beaconCarEta(now.plusSeconds(3600),  now, zone, Locale.US)) // +1h same day
assertEquals("Full by Wed 11:00 AM", beaconCarEta(now.plusSeconds(90000), now, zone, Locale.US)) // +25h next day
```

> `beaconTireSummary` is additionally exercised by `CarAvailabilityTest` #3 above.

---

## 7. Refresh flow (for a WidgetKit `TimelineProvider` port)

**Who calls what:** `CarWorker` (a `WorkManager` `CoroutineWorker`) → `CarRepository.refresh(context)` → `HaClient.template(CAR_TEMPLATE)` → parses/guards → writes the reply JSON into the widget's Glance `Preferences` (DataStore) → Glance re-renders.

**Polling interval:** **15 minutes**, periodic (`PeriodicWorkRequestBuilder<CarWorker>(15, TimeUnit.MINUTES)`, unique work `"car-periodic"`, policy `KEEP`). Plus expedited one-shots (`"car-refresh"`, policy `REPLACE`) on widget enable, every `onUpdate`, and the manual "Check again" button (`CarRefreshAction`). `CarWidgetReceiver.onEnabled` schedules the periodic + fires one now; `onUpdate` fires one now; `onDisabled` stops background work.

**State keys** written to Glance `Preferences` (`CarRepository.kt:24-30`):

```kotlin
object VKeys {
    val car = stringPreferencesKey("v_car")          // CAR_TEMPLATE's reply as last read
    val lastGood = stringPreferencesKey("v_last_good")// last reply that had readings (shown stale when none)
    val error = stringPreferencesKey("v_error")
    val checkedAt = longPreferencesKey("v_checked_at")
    val checking = stringPreferencesKey("v_checking")
}
```

**`CarRepository.refresh` — exact logic (`CarRepository.kt:36-65`):**

```kotlin
suspend fun refresh(context: Context) {
    val config = HaConfig.load(context)
    if (!config.baseUrl.startsWith("https://") || !config.hasAuth) {
        write(context) { it[VKeys.error] = "Set up Home Assistant in Settings" }
        return
    }
    try {
        val client = HaClient(config)
        val reply = JSONObject(client.template(CAR_TEMPLATE))
        // asleep "since" a Home Assistant restart isn't when it fell asleep: no time, rather than a wrong one
        val since = reply.optString("statusSince").takeIf { it.isNotBlank() && it != "null" }
            ?.let { runCatching { OffsetDateTime.parse(it).toInstant() }.getOrNull() }
        if (since != null && trustedSince(since, HaStart.get(context, client)) == null) reply.put("statusSince", JSONObject.NULL)
        write(context) { p ->
            p[VKeys.car] = reply.toString()
            if (carFromTemplate(reply.toString())?.battery != null) p[VKeys.lastGood] = reply.toString()
            p[VKeys.checkedAt] = System.currentTimeMillis()
            p.remove(VKeys.error)
        }
        OnlineRetry.reached(context, "car-retry")
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        write(context) { it[VKeys.error] = friendlyError(e) }
        // can't reach it (not a refusal): again once online
        if (e !is HaClient.HaError) OnlineRetry.schedule(context, "car-retry", CarWorker::class.java)
    } finally {
        write(context) { it.remove(VKeys.checking) }
    }
}
```

**`CarWorker` scheduling (`CarRepository.kt:81-91`):**

```kotlin
fun refreshNow(context: Context) {
    val work = OneTimeWorkRequestBuilder<CarWorker>().setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST).build()
    WorkManager.getInstance(context).enqueueUniqueWork("car-refresh", ExistingWorkPolicy.REPLACE, work)
}
fun schedulePeriodic(context: Context) {
    val work = PeriodicWorkRequestBuilder<CarWorker>(15, TimeUnit.MINUTES).build()
    WorkManager.getInstance(context).enqueueUniquePeriodicWork("car-periodic", ExistingPeriodicWorkPolicy.KEEP, work)
}
```

**Restart-stamp guard (`HaStart.kt`)** — a HA restart stamps every entity's `last_changed` with the start time, so a "since" within the first 5 minutes after start is meaningless and is nulled out:

```kotlin
private val SETTLE = Duration.ofMinutes(5)
fun trustedSince(since: Instant?, haStart: Instant?): Instant? {
    if (since == null || haStart == null) return since
    val restartStamp = !since.isBefore(haStart.minusSeconds(60)) && since.isBefore(haStart.plus(SETTLE))
    return if (restartStamp) null else since
}
```
`HaStart.get` caches HA's start time (earliest `last_changed` across all entities, template `{{ (states | map(attribute='last_changed') | min).isoformat() }}`) for up to 30 minutes, falling back to the cached value on error.

### iOS `TimelineProvider` mapping

- **Timeline cadence:** request a refresh roughly every **15 min** (`TimelineProvider.getTimeline` returning entries with `.after(Date().addingTimeInterval(15*60))`, or a BackgroundTask). Android's "refresh now on widget update / manual" maps to WidgetKit's `reloadTimelines(ofKind:)` + an in-widget "Check again" intent (`AppIntent`).
- **Fetch:** load `HaConfig` from Keychain/App-Group → guard `baseUrl` is `https://` and `hasAuth` (else emit the `"Set up Home Assistant in Settings"` error state) → `POST /api/template` with `CAR_TEMPLATE` → parse via `carFromTemplate` → `carToShow(current, lastGood)` → `carView(...)`.
- **State to persist (App Group / shared store), mirroring `VKeys`:** last raw reply (`v_car`), last reply that had a battery (`v_last_good`, used for the stale fallback), `v_error`, `v_checked_at`, and a transient `v_checking` flag. The stale decision and the restart-stamp `trustedSince`/`HaStart` guard should be reproduced server-of-truth-side before building the entry.
- **Error handling:** `friendlyError` classifies network vs HA-refusal; `beaconNeedsSettings(error)` decides whether the widget shows a "connect / sign in / check entity / check token" Settings CTA instead of a Retry. Network (non-`HaError`) failures schedule an on-reconnect retry (Android `OnlineRetry`); on iOS, rely on the next timeline reload / `NWPathMonitor`.
- **Clock for tests:** inject `now`/`zone`/`locale` into `carView`/`beaconCarEta`/`sinceLabel` exactly as Kotlin does (all four take them as parameters) so the formatting tests port verbatim.
