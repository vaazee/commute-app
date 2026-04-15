# CommuteApp

A personal iOS app that makes the daily commute legible at a glance. Two anchored modes — **Home** (610 Clinton St, Hoboken NJ) and **Office** (919 3rd Ave, New York NY) — each surfacing live transit options for the leg you're about to start. The app auto-picks the right mode by GPS, shows only the next ~20–30 minutes of departures, and is designed to be actionable in a single glance without any navigation.

---

## Table of contents

1. [What the app shows](#what-the-app-shows)
2. [Design decisions](#design-decisions)
3. [Architecture](#architecture)
4. [Data sources](#data-sources)
5. [Module details](#module-details)
6. [Project layout](#project-layout)
7. [Build & run](#build--run)
8. [GTFS preprocessor](#gtfs-preprocessor)
9. [App icon](#app-icon)
10. [Testing](#testing)
11. [Known limitations](#known-limitations)
12. [References](#references)

---

## What the app shows

The app opens to whichever mode GPS suggests. The top bar shows the current mode and a segmented control that can override the auto-detected mode (the override sticks until cleared).

### Home mode

Ordered top to bottom — the first section is what you'd check first when leaving the house.

1. **126 Bus → NYC.** Nearest 126 bus stop to 610 Clinton St that is served by the **Willow Ave or Clinton St NYC-bound variants** (the Washington St variant is excluded by the headsign filter). Lists the next ~5 scheduled departures within 20 minutes with minutes-away and absolute departure time.
2. **Citi Bike near home.** Three nearest rentable stations to 610 Clinton St, with name, walking distance, bikes available (including e-bikes), and docks available.
3. **Hoboken PATH.** Open Citi Bike docks at the station *named* "Hoboken Terminal" (so you can confirm there's room to drop the bike before boarding), followed by the next PATH trains from Hoboken → 33rd St within 30 minutes.
4. **References.** Links to official schedules (see below).

### Office mode

1. **Citi Bike near office.** Three nearest rentable stations to 919 3rd Ave.
2. **126 Bus from Port Authority.** Next ~6 scheduled departures from the Port Authority Bus Terminal departure stop (stop_id `3511`) within 30 minutes, filtered to headsigns containing `WILLOW` or `CLINTON`.
3. **PATH 23rd St → Hoboken.** Next trains from 23rd St → Hoboken within 30 minutes.
4. **References.**

### References section (both modes)

Tappable links to the official schedules: NJ Transit 126 PDF timetable, NJ Transit MyBusNow live tracker for route 126, PATH schedules & maps (PANYNJ), Citi Bike station map.

---

## Design decisions

All locked in early and unchanged since:

- **Native SwiftUI, iOS 17+.** Uses the `@Observable` macro for service-layer state. No Combine, no UIKit, no cross-platform frameworks.
- **No backend.** Every data source is hit directly from the device. The app has no server, no account, no analytics.
- **Bundled static GTFS, not realtime, for NJ Transit.** Real-time bus tracking (NJ Transit's `mybusnow` endpoint) is skipped. Bundling the schedule as a slim SQLite keeps everything offline-capable for bus data and removes a whole class of auth/rate-limit concerns. The UI labels bus times as "Scheduled — does not reflect live delays."
- **Two fixed geographic anchors.** The app is built for one user with one home and one office. `Anchors.home` and `Anchors.office` are hardcoded constants. No user settings UI, no address picker.
- **Mode detected via nearest-anchor haversine.** The `ModeManager` compares current location to both anchors and picks whichever is closer. Manual override via segmented picker when GPS is denied or the user wants to preview the other mode.
- **PATH via RidePATH JSON, not GTFS-RT.** Initially built against the GTFS-realtime protobuf feed at `path.transitdata.nyc`, but that feed only emits a single `stop_time_update` per trip (the next stop), not full trip predictions — so it couldn't answer "when will the next train leaving Hoboken reach 33rd St?". RidePATH (`panynj.gov/bin/portauthority/ridepath.json`) gives full next-train predictions per station and destination. SwiftProtobuf was added then removed.
- **Headsign filtering at query time, not preprocess time.** The GTFS preprocessor keeps *all* route 126 variants in the bundled DB. The two views apply `headsignContains` / `headsignExcludes` filters at query time. This keeps one preprocessor for multiple UI use cases (NYC-bound from home vs. Hoboken-bound from Port Authority).
- **Origin uses anchors, not GPS.** `HomeModeView` and `OfficeModeView` compute distances relative to `Anchors.home` / `Anchors.office`, not the current GPS coordinate. This keeps the displayed data stable even as you walk around, and guarantees the "nearest stop to home" is actually nearest to home.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                         ContentView                              │
│  ┌──────────┐   ┌──────────────────────────────────────────┐     │
│  │ ModeBar  │   │ HomeModeView  /  OfficeModeView          │     │
│  │ (picker) │   │   ├── BusSection     (SectionCard)       │     │
│  └──────────┘   │   ├── BikeSection    (SectionCard)       │     │
│                 │   ├── PathSection    (SectionCard)       │     │
│                 │   └── ReferencesSection (SectionCard)    │     │
│                 └──────────────────────────────────────────┘     │
│                                 │                                │
│                                 ▼                                │
│        ┌──────────────┬──────────────┬──────────────┐            │
│        │ CitiBike     │ PathService  │ NJTransit    │            │
│        │ Service      │              │ Schedule     │            │
│        │ (GBFS JSON)  │ (RidePATH)   │ (bundled DB) │            │
│        └──────────────┴──────────────┴──────────────┘            │
│                                 ▲                                │
│            ┌────────────────────┼──────────────┐                 │
│            │   LocationService ─▶ ModeManager  │                 │
│            │   (CoreLocation)    (home/office) │                 │
│            └───────────────────────────────────┘                 │
└──────────────────────────────────────────────────────────────────┘
```

- `ContentView` owns five singletons as `@State` and wires them into the mode views.
- Each service is `@Observable` and `final class` with a `shared` singleton.
- Refresh is coordinated: a 30-second `Timer` calls `refreshAll()` (fan-out to all services in parallel via `async let`), and pull-to-refresh does the same. The NJ Transit service doesn't need refreshing — it reads from the bundled SQLite.
- `LocationService.didUpdateLocations` calls `ModeManager.shared.update(from:)` directly. The earlier approach of watching `location.current` via SwiftUI `.onChange` was unreliable because `CLLocationCoordinate2D` is a value type without `Equatable` on the latitude/longitude pair and the change propagation missed updates.

---

## Data sources

| Source | URL | Auth | Format | Used for |
|---|---|---|---|---|
| NJ Transit static GTFS | `https://content.njtransit.com/sites/default/files/developers-resources/bus_data.zip` | None | CSVs in a zip → preprocessed SQLite | 126 bus schedule, both directions |
| Citi Bike GBFS — info | `https://gbfs.citibikenyc.com/gbfs/en/station_information.json` | None | JSON | Station name, lat/lon, capacity |
| Citi Bike GBFS — status | `https://gbfs.citibikenyc.com/gbfs/en/station_status.json` | None | JSON | Bikes/docks/rentable flags |
| PATH RidePATH | `https://www.panynj.gov/bin/portauthority/ridepath.json` | None | JSON | Per-station next-train predictions by destination |

All feeds are public and require no API key. Citi Bike's GBFS has included Hoboken stations since the Lyft acquisition, so a single feed covers both modes.

---

## Module details

### `CommuteApp/App/`
- `CommuteApp.swift` — `@main` struct, single scene, no state.
- `ContentView.swift` — top-level view. Holds the refresh `Timer`, fires `LocationService.start()` in `.task`, and binds the mode picker to `ModeManager`.

### `CommuteApp/Core/Location/`
- `Anchors.swift` — the two `CLLocationCoordinate2D` constants and the `CommuteMode` enum (`.home` / `.office`).
- `LocationService.swift` — `CLLocationManager` wrapper, `kCLLocationAccuracyHundredMeters`, `distanceFilter = 100`. Handles the `notDetermined → authorizedWhenInUse` flow. Silent on error; the UI falls back to manual mode toggle when permission is denied.
- `ModeManager.swift` — publishes `.detected` from haversine comparison, and `.override` settable from the picker. `current` returns `override ?? detected`.

### `CommuteApp/Core/Models/`
- `BikeStation.swift` — value type with a `distance(from:)` helper using `CLLocation.distance(from:)`.
- `BusDeparture.swift` — bus departure struct plus `NJTransitStops.portAuthorityDeparture = "3511"`.
- `PathTrain.swift` — PATH train struct plus station-ID constants (`HOB`, `23S`, `33S`).

### `CommuteApp/Services/CitiBikeService.swift`
- Fetches `station_information.json` with a 1-hour in-memory cache (station metadata doesn't change often), and `station_status.json` on every refresh.
- Joins the two on `station_id`, filtering to stations where `is_renting == 1` for `nearestStations(to:count:)`.
- `station(named:)` does a `localizedCaseInsensitiveContains` match, used for the "Hoboken Terminal" lookup.

### `CommuteApp/Services/PathService.swift`
- Decodes RidePATH JSON into `[stationCode: [PathTrain]]`.
- `departures(from:to:within:)` filters by origin, destination, and a time window (accepts trains up to 60 seconds in the past, to avoid "just missed it" flicker).
- Each train's `departure` is synthesized at parse time from `Date().addingTimeInterval(secondsToArrival)`.

### `CommuteApp/Services/NJTransitScheduleService.swift`
- Opens the bundled `njtransit_gtfs.sqlite` read-only via the SQLite3 C API. No third-party Swift SQLite wrappers — just `import SQLite3` and the raw calls.
- `nearestStops(to:limit:headsignContains:headsignExcludes:)` — when headsign filters are present, joins stops → stop_times → trips and keeps only stops served by at least one trip whose headsign matches. This is what picks the nearest NYC-bound 126 stop to home rather than the nearest 126 stop in *any* direction.
- `nextDepartures(stopId:stopName:withinMinutes:headsignContains:headsignExcludes:now:)` — intersects `stop_times.stop_id` with trips whose `service_id` is active today (see below), parses GTFS `HH:MM:SS` times against the day's start, and applies headsign filtering.
- `activeServiceIds(on:)` — unions `calendar.txt` weekday rows with `calendar_dates.txt` exceptions (type 1 = add service, type 2 = remove service), using the `America/New_York` timezone for both the `yyyyMMdd` date lookup and the weekday calculation. NJ Transit's bus GTFS ships without a `calendar.txt` — it uses `calendar_dates.txt` exclusively, so this code path is the primary one.
- `prettyHeadsign` strips the " -Exact Fare" suffix case-insensitively.
- `SQLITE_TRANSIENT` is defined at file scope as `unsafeBitCast(-1, to: sqlite3_destructor_type.self)` because the C macro isn't imported into Swift.

### `CommuteApp/Features/Shared/`
- `SectionCard.swift` — rounded card container with title + SF Symbol + content slot. Every section uses this.
- `BikeStationRow.swift` — row layouts for bike stations, bus departures, and PATH departures.
- `ReferencesSection.swift` — four `Link` rows (NJ Transit 126 PDF, MyBusNow 126 live, PATH schedules, Citi Bike station map). `Link` opens in Safari.

### `CommuteApp/Features/HomeMode/HomeModeView.swift`
- `origin = Anchors.home`
- Bus filter: `["NEW YORK VIA CLINTON", "NEW YORK VIA WILLOW"]`. This both picks the nearest stop *served by* those variants and filters departures at that stop to those variants.

### `CommuteApp/Features/OfficeMode/OfficeModeView.swift`
- `origin = Anchors.office`
- Bus stop is hardcoded to `NJTransitStops.portAuthorityDeparture` (`3511`). Filter is `["WILLOW", "CLINTON"]` (broader — any Willow or Clinton variant, inbound or outbound relative to NYC).

---

## Project layout

```
commute-app/
├── CommuteApp.xcodeproj/
│   └── project.pbxproj           # Hand-written Xcode 16+ synchronized-folder project
├── CommuteApp/
│   ├── App/
│   │   ├── CommuteApp.swift
│   │   └── ContentView.swift
│   ├── Core/
│   │   ├── Location/
│   │   │   ├── Anchors.swift
│   │   │   ├── LocationService.swift
│   │   │   └── ModeManager.swift
│   │   └── Models/
│   │       ├── BikeStation.swift
│   │       ├── BusDeparture.swift
│   │       └── PathTrain.swift
│   ├── Features/
│   │   ├── HomeMode/HomeModeView.swift
│   │   ├── OfficeMode/OfficeModeView.swift
│   │   └── Shared/
│   │       ├── BikeStationRow.swift
│   │       ├── ReferencesSection.swift
│   │       └── SectionCard.swift
│   ├── Services/
│   │   ├── CitiBikeService.swift
│   │   ├── NJTransitScheduleService.swift
│   │   └── PathService.swift
│   ├── Resources/
│   │   └── njtransit_gtfs.sqlite  # ~0.7 MB, built by the preprocessor below
│   ├── Assets.xcassets/
│   │   └── AppIcon.appiconset/    # 1024x1024 app icon, regenerable via scripts/make_app_icon.py
│   └── Info.plist
├── scripts/
│   ├── build_gtfs_db.py          # One-time NJ Transit GTFS → SQLite preprocessor
│   └── make_app_icon.py          # Regenerates Assets.xcassets/AppIcon.appiconset/icon-1024.png
├── .gitignore
└── README.md
```

The Xcode project uses a `PBXFileSystemSynchronizedRootGroup` (new in Xcode 16 / objectVersion 77). The `CommuteApp/` folder is auto-synced — new Swift files appear in the project without editing `project.pbxproj`. `Info.plist` is declared as an exception so it doesn't get picked up as a bundle resource (which would cause "Multiple commands produce Info.plist").

---

## Build & run

### Prerequisites
- **Xcode 16+** (for `PBXFileSystemSynchronizedRootGroup` support).
- **iOS 17+** target — the app uses `@Observable`.
- **macOS** (required to build iOS apps).
- For rebuilding the GTFS DB: **Python 3.9+** (standard library only — no `pip install` needed).

### From Xcode
1. Open `CommuteApp.xcodeproj`.
2. Select the **CommuteApp** scheme.
3. Pick a destination:
   - Simulator: any iPhone running iOS 17+. The app was developed against **iPhone 17 Pro Max**.
   - Device: requires setting a development team in project settings (Signing & Capabilities) for code signing.
4. ⌘R.

### From the command line
```bash
# Build for simulator
xcodebuild -project CommuteApp.xcodeproj \
           -scheme CommuteApp \
           -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
           -configuration Debug build

# Install on a booted simulator
xcrun simctl install booted \
    ~/Library/Developer/Xcode/DerivedData/CommuteApp-*/Build/Products/Debug-iphonesimulator/CommuteApp.app

# Launch
xcrun simctl launch booted com.vaazee.CommuteApp
```

### Simulator location
The simulator won't report a real location on its own. To exercise mode detection in the simulator:
- In the Simulator menu: **Features → Location → Custom Location…**
- Home test: `40.7451, -74.0332` (should pick Home mode).
- Office test: `40.7603, -73.9677` (should pick Office mode).

Location permission still prompts on first launch in the simulator; tap Allow.

---

## GTFS preprocessor

`scripts/build_gtfs_db.py` downloads NJ Transit's full bus GTFS zip (~50 MB), filters to route 126 (any variant), and writes `CommuteApp/Resources/njtransit_gtfs.sqlite` (~0.7 MB).

### Run it
```bash
python3 scripts/build_gtfs_db.py
```

No third-party dependencies — it uses only `urllib`, `zipfile`, `csv`, `sqlite3` from the standard library.

### What it does
1. Downloads `bus_data.zip` into `scripts/.cache/` (gitignored). Subsequent runs reuse the cache.
2. Reads `routes.txt`, keeps entries where `route_short_name == "126"`. (In the current feed this resolves to `route_id = 25`.)
3. Reads `trips.txt`, keeps all trips on route 126. Prints the histogram of `trip_headsign` values so you can sanity-check the variants seen in the feed. Typical counts:
   - `126 NEW YORK-Exact Fare` (Washington St variant) — ~297
   - `126 HOBOKEN-PATH-Exact Fare` — ~294
   - `126 NEW YORK VIA CLINTON-Exact Fare` — ~90
   - `126 HOBOKEN VIA WILLOW AVE-Exact Fare` — ~58
   - plus smaller Hamilton Park variants
4. Keeps all `stop_times` whose `trip_id` is in the kept set, plus the referenced stops, plus `calendar` + `calendar_dates` for every referenced `service_id`.
5. Writes a SQLite file with indices on `stop_times(stop_id)`, `stop_times(trip_id)`, and `calendar_dates(service_id, date)`.

### When to re-run
- The NJ Transit GTFS feed is updated periodically. Re-run before each TestFlight build to keep schedules current, or whenever `calendar.txt` / `calendar_dates.txt` would indicate your bundled service window has expired.

### Output schema
```sql
CREATE TABLE stops (stop_id, stop_name, stop_lat, stop_lon);
CREATE TABLE trips (trip_id, route_id, service_id, trip_headsign, direction_id, shape_id);
CREATE TABLE stop_times (trip_id, arrival_time, departure_time, stop_id, stop_sequence);
CREATE TABLE calendar (service_id, monday..sunday, start_date, end_date);
CREATE TABLE calendar_dates (service_id, date, exception_type);
```

Times are stored in GTFS format (`HH:MM:SS`, where hours may exceed 24 for after-midnight service). `NJTransitScheduleService.parseGtfsTime` handles this by adding the raw seconds to `Calendar.startOfDay(for: now)`.

---

## App icon

`scripts/make_app_icon.py` regenerates the 1024×1024 app icon at `CommuteApp/Assets.xcassets/AppIcon.appiconset/icon-1024.png`. Run it with Pillow installed:

```bash
python3 scripts/make_app_icon.py
```

The current design is a white bus-front silhouette on a diagonal gradient from PATH blue (`#003DA5`) to NJ Transit orange (`#F58025`) — a nod to the two transit systems the app serves. The output is flat RGB (no alpha) so iOS accepts it as an app icon. The asset catalog uses a single universal 1024×1024 slot; Xcode generates all device sizes from it at build time.

The target's build settings include `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` so `actool` knows which asset set to treat as the app icon. Without it, the icon won't be packed into the `.app` bundle.

---

## Testing

There is no automated test suite yet. The app is verified by:

1. **Build verification** — `xcodebuild … build` produces **BUILD SUCCEEDED**. SourceKit may surface stale "Cannot find X in scope" diagnostics because the synchronized folder group confuses its indexing; these can be ignored when the command-line build passes.
2. **Mode detection** — set simulator location to Hoboken coords → expect Home mode; set to Midtown coords → expect Office mode. Toggle the manual override and confirm it sticks.
3. **Citi Bike cross-check** — open [citibikenyc.com/stations](https://account.citibikenyc.com/map), click on one of the top three stations the app lists, and compare bikes/docks counts. They should match (within a minute of lag).
4. **PATH cross-check** — compare the app's next-train list at Hoboken or 23rd St against the official RidePATH iOS app at the same moment.
5. **126 cross-check** — compare the app's next departures against the NJ Transit 126 PDF timetable for today's service. Note the scheduled-only caveat: on detour/snow days the app will be wrong.
6. **End-to-end** — stand at home, open the app cold, confirm Home mode auto-selects and all three sections populate within ~2s. Same at the office.

---

## Known limitations

- **Scheduled, not live, bus data.** The 126 section is bundled GTFS. Detours, cancellations, and real-time delays aren't reflected. The UI labels this explicitly under each bus section: *"Scheduled — does not reflect live delays."* A user-visible link to MyBusNow in the References section is the current workaround.
- **Simulator can't auto-dismiss the location prompt.** First launch always shows the CoreLocation permission sheet. The segmented mode picker works regardless.
- **SourceKit noise.** Synchronized folder groups confuse Xcode's in-editor indexer. The command-line build is authoritative.
- **No background refresh / notifications.** The 30-second refresh only runs while the app is foregrounded.
- **"Hoboken Terminal" lookup is substring-based.** If Lyft renames the Citi Bike station at Hoboken Terminal, the `station(named: "Hoboken Terminal")` call will silently return nil. Stable enough for now; revisit if it breaks.
- **No accessibility pass, no Dynamic Type tuning, no dark-mode polish** beyond SwiftUI defaults.
- **Single user, hardcoded anchors.** Not designed to be generalized.

---

## References

- [NJ Transit 126 bus PDF schedule](https://content.njtransit.com/pdf/schedules/bus/126)
- [NJ Transit MyBusNow — route 126](https://mybusnow.njtransit.com/bustime/wireless/html/selectdirection.jsp?route=126)
- [PATH schedules & maps (PANYNJ)](https://www.panynj.gov/path/en/schedules-maps.html)
- [Citi Bike station map](https://account.citibikenyc.com/map)
- [GBFS specification](https://github.com/MobilityData/gbfs)
- [GTFS specification](https://gtfs.org/)
- [NJ Transit developer resources](https://www.njtransit.com/developer-resources)
