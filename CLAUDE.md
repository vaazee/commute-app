# CLAUDE.md

Operational notes for Claude Code sessions on this repo. For product/design details and architecture, read `README.md` — don't duplicate that here. This file is specifically for "things that would cost you a round of mistakes to re-derive."

## Project identity

- **Single-user iOS app.** Owner: Vasanth. Two modes, two hardcoded anchors: `Anchors.home` (610 Clinton St, Hoboken) and `Anchors.office` (919 3rd Ave, NYC). Don't add a settings UI or generalize to other users.
- **Bundle ID:** `com.vaazee.CommuteApp` (may be renamed for free-account device signing; check `project.pbxproj` before assuming).
- **Target device:** iPhone 17 Pro Max. All simulator testing uses that destination.

## Build commands that work

```bash
xcodebuild -project CommuteApp.xcodeproj \
           -scheme CommuteApp \
           -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
           -configuration Debug build
```

Install + launch on booted simulator:
```bash
xcrun simctl install booted \
  ~/Library/Developer/Xcode/DerivedData/CommuteApp-*/Build/Products/Debug-iphonesimulator/CommuteApp.app
xcrun simctl launch booted com.vaazee.CommuteApp
```

If the simulator is shut down, `xcrun simctl boot "iPhone 17 Pro Max"` first.

## SourceKit diagnostics are noise — ignore them

The Xcode project uses a `PBXFileSystemSynchronizedRootGroup` (Xcode 16+, `objectVersion = 77`). SourceKit's in-editor indexer doesn't understand this and will surface `Cannot find 'SectionCard' in scope` / `Cannot find type 'CitiBikeService' in scope` type errors even when the code compiles fine.

**Rule:** the command-line `xcodebuild … build` result is authoritative. If it prints `** BUILD SUCCEEDED **`, the code is correct — do not try to "fix" SourceKit complaints by adding imports or touching file membership. I've lost time to this. If tempted, run xcodebuild first.

## The `Info.plist` trap

The synchronized folder group auto-adds every file in `CommuteApp/` to the build. `Info.plist` must be explicitly excepted or you get `Multiple commands produce Info.plist`. The exception lives in `project.pbxproj` as a `PBXFileSystemSynchronizedBuildFileExceptionSet` with `membershipExceptions = (Info.plist,)`. Don't remove it.

## `SQLITE_TRANSIENT` in Swift

The C macro isn't imported into Swift. `NJTransitScheduleService.swift` defines it at file scope:
```swift
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
```
If you add a new file that does SQLite text binding, either use this or re-declare it privately. Don't pass `nil` for the destructor on borrowed strings — you'll get nondeterministic garbage.

## GTFS preprocessor

`scripts/build_gtfs_db.py`, stdlib-only Python 3.

- Downloads `bus_data.zip` (~50 MB) into `scripts/.cache/` on first run. **That directory is gitignored** — never `git add scripts/.cache/` or you'll push 50 MB of zip into the repo.
- Writes `CommuteApp/Resources/njtransit_gtfs.sqlite` (~0.7 MB, committed).
- Keeps *all* 126 variants. Headsign filtering happens at query time in `NJTransitScheduleService`, not here. Don't "optimize" the preprocessor to drop Washington St variants — the current split lets the same DB serve both modes.
- Re-run before a TestFlight build or if the bundled service window expires. Service IDs live in `calendar_dates.txt` — NJ Transit's bus feed has no `calendar.txt` rows.

## NJ Transit GTFS specifics (hard-won)

- Route 126 is `route_id = "25"` in the current feed (mapped from `route_short_name = "126"`).
- Port Authority departure stop is `stop_id = "3511"` (`NJTransitStops.portAuthorityDeparture`).
- Times are `HH:MM:SS` and hours can exceed 24 for after-midnight service — always parse as seconds-from-startOfDay, not as a wall clock.
- Headsigns have a `-Exact Fare` suffix in mixed case. Strip with `options: .caseInsensitive`.
- Service activation **must** use `America/New_York` timezone for both the `yyyyMMdd` lookup and the weekday computation. Don't use the device's locale.

## Home mode's bus filter is load-bearing

```swift
let nycViaWillowOrClinton = ["NEW YORK VIA CLINTON", "NEW YORK VIA WILLOW"]
```
Both strings are needed — they select NYC-bound trips *and* exclude the Washington St variant in one pass. Losing either one silently breaks "nearest stop" selection: the nearest 126 stop to home also serves Hoboken-bound trips, so without the filter `nearestStops` returns a stop with zero usable departures and the UI shows "No scheduled departures."

## PATH — use RidePATH, not GTFS-RT

The protobuf feed at `path.transitdata.nyc` only emits a single `stop_time_update` per trip (the *next* stop), not full trip predictions, so it can't answer "when does this Hoboken train reach 33rd St?". We use `https://www.panynj.gov/bin/portauthority/ridepath.json` instead — per-station, per-destination next-train predictions with `secondsToArrival`. Don't re-add SwiftProtobuf.

## Origin in mode views is `Anchors.home` / `Anchors.office`, not GPS

`HomeModeView` and `OfficeModeView` use the anchor as origin, not `here` (the GPS coord). This keeps "nearest stop to home" actually nearest to home, and stops the displayed list from flickering as the user walks. The `here` parameter is kept in the view signatures for symmetry but isn't used — don't "clean up" by removing it unless you also refactor to decide deliberately.

## Mode detection wiring

`LocationService.didUpdateLocations` calls `ModeManager.shared.update(from:)` directly. Earlier wiring via SwiftUI `.onChange(of: location.current?.latitude)` was flaky. Keep the direct call.

## Device install (free Apple ID)

User installs directly from Xcode with a free Apple ID:
- Team set in Signing & Capabilities, automatic signing on.
- Bundle ID may need to be changed to `com.<something-unique>.CommuteApp` since free accounts can't reuse claimed IDs.
- Free provisioning expires every 7 days → re-build-and-run from Xcode to refresh.
- iPhone needs **Settings → Privacy & Security → Developer Mode** on.

No paid developer account, no TestFlight, no App Store distribution planned.

## Git hygiene

- `.claude/` and `scripts/.cache/` are gitignored. Never stage them.
- Prefer explicit `git add <path>` over `git add -A` / `git add .` so those don't slip in.
- Main is `origin/main` at `https://github.com/vaazee/commute-app.git`. There's no CI and no branching workflow.

## What's intentionally missing

Don't be helpful by adding:
- A settings screen, address picker, or multi-user support.
- Automated tests. Verification is manual (see README "Testing").
- Background refresh, push notifications, widgets, complications.
- A paid-account feature gate or TestFlight config.
- Real-time NJ Transit bus tracking as first-class data (the References link to MyBusNow is the workaround).
- Accessibility/Dynamic Type polish (not rejected, just not yet prioritized — ask before spending time on it).
