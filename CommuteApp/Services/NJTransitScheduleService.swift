import Foundation
import SQLite3
import CoreLocation

@Observable
final class NJTransitScheduleService {
    static let shared = NJTransitScheduleService()

    private var db: OpaquePointer?
    private(set) var lastError: String?

    init() {
        guard let url = Bundle.main.url(forResource: "njtransit_gtfs", withExtension: "sqlite") else {
            lastError = "njtransit_gtfs.sqlite missing from bundle"
            return
        }
        if sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            lastError = "failed to open sqlite: \(String(cString: sqlite3_errmsg(db)))"
        }
    }

    deinit {
        if db != nil { sqlite3_close(db) }
    }

    /// Find nearest stops, optionally restricted to stops served by trips whose headsign matches.
    func nearestStops(
        to coord: CLLocationCoordinate2D,
        limit: Int,
        headsignContains: [String] = [],
        headsignExcludes: [String] = []
    ) -> [(stopId: String, name: String, coord: CLLocationCoordinate2D)] {
        guard let db else { return [] }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        let sql: String
        if headsignContains.isEmpty && headsignExcludes.isEmpty {
            sql = "SELECT stop_id, stop_name, stop_lat, stop_lon FROM stops"
        } else {
            sql = """
                SELECT DISTINCT s.stop_id, s.stop_name, s.stop_lat, s.stop_lon
                FROM stops s
                JOIN stop_times st ON st.stop_id = s.stop_id
                JOIN trips t ON t.trip_id = st.trip_id
                """
        }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }

        let here = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        var rows: [(String, String, CLLocationCoordinate2D, CLLocationDistance)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let name = String(cString: sqlite3_column_text(stmt, 1))
            let lat = sqlite3_column_double(stmt, 2)
            let lon = sqlite3_column_double(stmt, 3)

            if !headsignContains.isEmpty || !headsignExcludes.isEmpty {
                if !stopHasMatchingHeadsign(stopId: id, contains: headsignContains, excludes: headsignExcludes) {
                    continue
                }
            }

            let c = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            let d = here.distance(from: CLLocation(latitude: lat, longitude: lon))
            rows.append((id, name, c, d))
        }
        return rows.sorted { $0.3 < $1.3 }.prefix(limit).map { ($0.0, $0.1, $0.2) }
    }

    private func stopHasMatchingHeadsign(stopId: String, contains: [String], excludes: [String]) -> Bool {
        guard let db else { return false }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = """
            SELECT DISTINCT t.trip_headsign
            FROM trips t
            JOIN stop_times st ON st.trip_id = t.trip_id
            WHERE st.stop_id = ?
            """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        sqlite3_bind_text(stmt, 1, stopId, -1, SQLITE_TRANSIENT)
        while sqlite3_step(stmt) == SQLITE_ROW {
            let hs = String(cString: sqlite3_column_text(stmt, 0)).uppercased()
            if !excludes.isEmpty && excludes.contains(where: { hs.contains($0.uppercased()) }) {
                continue
            }
            if contains.isEmpty || contains.contains(where: { hs.contains($0.uppercased()) }) {
                return true
            }
        }
        return false
    }

    /// Next departures from a given stop within `withinMinutes`, optionally filtered to headsigns
    /// matching any of `headsignContains` (case-insensitive). Excludes any headsign matching `headsignExcludes`.
    func nextDepartures(
        stopId: String,
        stopName: String,
        withinMinutes: Int,
        headsignContains: [String] = [],
        headsignExcludes: [String] = [],
        now: Date = Date()
    ) -> [BusDeparture] {
        guard let db else { return [] }
        let activeServices = activeServiceIds(on: now)
        if activeServices.isEmpty { return [] }

        let placeholders = activeServices.map { _ in "?" }.joined(separator: ",")
        let sql = """
            SELECT t.trip_id, t.trip_headsign, st.departure_time
            FROM stop_times st
            JOIN trips t ON t.trip_id = st.trip_id
            WHERE st.stop_id = ?
              AND t.service_id IN (\(placeholders))
            """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        sqlite3_bind_text(stmt, 1, stopId, -1, SQLITE_TRANSIENT)
        for (idx, sid) in activeServices.enumerated() {
            sqlite3_bind_text(stmt, Int32(2 + idx), sid, -1, SQLITE_TRANSIENT)
        }

        let cal = Calendar(identifier: .gregorian)
        let startOfDay = cal.startOfDay(for: now)
        let cutoff = now.addingTimeInterval(TimeInterval(withinMinutes * 60))

        var results: [BusDeparture] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let tripId = String(cString: sqlite3_column_text(stmt, 0))
            let headsign = String(cString: sqlite3_column_text(stmt, 1))
            let depStr = String(cString: sqlite3_column_text(stmt, 2))

            if !headsignContains.isEmpty {
                let upper = headsign.uppercased()
                if !headsignContains.contains(where: { upper.contains($0.uppercased()) }) { continue }
            }
            if !headsignExcludes.isEmpty {
                let upper = headsign.uppercased()
                if headsignExcludes.contains(where: { upper.contains($0.uppercased()) }) { continue }
            }

            guard let depTime = parseGtfsTime(depStr, dayStart: startOfDay) else { continue }
            if depTime < now.addingTimeInterval(-30) { continue }
            if depTime > cutoff { continue }

            results.append(BusDeparture(
                id: "\(tripId)-\(stopId)",
                routeShortName: "126",
                headsign: prettyHeadsign(headsign),
                stopId: stopId,
                stopName: stopName,
                departure: depTime
            ))
        }
        return results.sorted { $0.departure < $1.departure }
    }

    private func parseGtfsTime(_ s: String, dayStart: Date) -> Date? {
        let parts = s.split(separator: ":")
        guard parts.count == 3, let h = Int(parts[0]), let m = Int(parts[1]), let sec = Int(parts[2]) else { return nil }
        let total = h * 3600 + m * 60 + sec
        return dayStart.addingTimeInterval(TimeInterval(total))
    }

    private func prettyHeadsign(_ s: String) -> String {
        s.replacingOccurrences(of: "-Exact Fare", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Exact Fare", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespaces)
    }

    private func activeServiceIds(on date: Date) -> [String] {
        guard let db else { return [] }
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.timeZone = TimeZone(identifier: "America/New_York")
        fmt.dateFormat = "yyyyMMdd"
        let dateStr = fmt.string(from: date)

        let cal = Calendar(identifier: .gregorian)
        let weekday = cal.component(.weekday, from: date)
        let weekdayCol: String
        switch weekday {
        case 1: weekdayCol = "sunday"
        case 2: weekdayCol = "monday"
        case 3: weekdayCol = "tuesday"
        case 4: weekdayCol = "wednesday"
        case 5: weekdayCol = "thursday"
        case 6: weekdayCol = "friday"
        case 7: weekdayCol = "saturday"
        default: return []
        }

        var active = Set<String>()
        let calSql = "SELECT service_id FROM calendar WHERE \(weekdayCol)=1 AND start_date<=? AND end_date>=?"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, calSql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, dateStr, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, dateStr, -1, SQLITE_TRANSIENT)
            while sqlite3_step(stmt) == SQLITE_ROW {
                active.insert(String(cString: sqlite3_column_text(stmt, 0)))
            }
        }
        sqlite3_finalize(stmt)

        let exSql = "SELECT service_id, exception_type FROM calendar_dates WHERE date=?"
        if sqlite3_prepare_v2(db, exSql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, dateStr, -1, SQLITE_TRANSIENT)
            while sqlite3_step(stmt) == SQLITE_ROW {
                let sid = String(cString: sqlite3_column_text(stmt, 0))
                let ex = sqlite3_column_int(stmt, 1)
                if ex == 1 { active.insert(sid) }
                if ex == 2 { active.remove(sid) }
            }
        }
        sqlite3_finalize(stmt)

        return Array(active)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
