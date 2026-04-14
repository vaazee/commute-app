#!/usr/bin/env python3
"""
Build a slim SQLite database from NJ Transit's bus GTFS feed.

Keeps only:
- route 126 (Willow Ave + Clinton St variants; excludes Washington St)
- stops served by those trips
- stop_times, trips, calendar, calendar_dates relevant to those trips

Output: CommuteApp/Resources/njtransit_gtfs.sqlite
"""

import csv
import io
import os
import sqlite3
import sys
import urllib.request
import zipfile
from pathlib import Path

GTFS_URL = "https://content.njtransit.com/sites/default/files/developers-resources/bus_data.zip"
ROUTE_SHORT_NAME = "126"
EXCLUDE_HEADSIGN_KEYWORDS = ["WASHINGTON ST", "WASHINGTON STREET"]
INCLUDE_HEADSIGN_KEYWORDS = ["WILLOW", "CLINTON"]

REPO_ROOT = Path(__file__).resolve().parents[1]
OUT_DB = REPO_ROOT / "CommuteApp" / "Resources" / "njtransit_gtfs.sqlite"
CACHE_ZIP = REPO_ROOT / "scripts" / ".cache" / "bus_data.zip"


def download_gtfs() -> Path:
    CACHE_ZIP.parent.mkdir(parents=True, exist_ok=True)
    if not CACHE_ZIP.exists():
        print(f"downloading GTFS from {GTFS_URL}")
        urllib.request.urlretrieve(GTFS_URL, CACHE_ZIP)
    else:
        print(f"using cached zip at {CACHE_ZIP}")
    return CACHE_ZIP


def read_csv(zf: zipfile.ZipFile, name: str):
    with zf.open(name) as f:
        text = io.TextIOWrapper(f, encoding="utf-8-sig")
        reader = csv.DictReader(text)
        for row in reader:
            yield row


def main() -> int:
    zip_path = download_gtfs()

    print("inspecting routes...")
    with zipfile.ZipFile(zip_path) as zf:
        route_ids = set()
        for r in read_csv(zf, "routes.txt"):
            if r.get("route_short_name", "").strip() == ROUTE_SHORT_NAME:
                route_ids.add(r["route_id"])
        if not route_ids:
            print(f"no routes found with short_name={ROUTE_SHORT_NAME}", file=sys.stderr)
            return 1
        print(f"  matched route_ids: {sorted(route_ids)}")

        print("scanning trips on route 126 (keeping all variants; query-time filter handles Willow/Clinton vs Washington)...")
        kept_trip_ids = set()
        kept_service_ids = set()
        kept_trips = []
        headsign_counts = {}
        for t in read_csv(zf, "trips.txt"):
            if t["route_id"] not in route_ids:
                continue
            headsign = (t.get("trip_headsign") or "").upper()
            headsign_counts[headsign] = headsign_counts.get(headsign, 0) + 1
            kept_trip_ids.add(t["trip_id"])
            kept_service_ids.add(t["service_id"])
            kept_trips.append(t)

        print(f"  headsigns seen on route 126:")
        for h, n in sorted(headsign_counts.items(), key=lambda x: -x[1]):
            print(f"    {h or '(blank)'}: {n}")
        print(f"  kept {len(kept_trip_ids)} trips total")

        print("collecting stop_times for kept trips...")
        kept_stop_ids = set()
        kept_stop_times = []
        for st in read_csv(zf, "stop_times.txt"):
            if st["trip_id"] not in kept_trip_ids:
                continue
            kept_stop_ids.add(st["stop_id"])
            kept_stop_times.append(st)
        print(f"  kept {len(kept_stop_times)} stop_times across {len(kept_stop_ids)} stops")

        print("collecting stops...")
        kept_stops = [s for s in read_csv(zf, "stops.txt") if s["stop_id"] in kept_stop_ids]

        print("collecting calendar + calendar_dates for kept services...")
        kept_calendar = []
        try:
            for c in read_csv(zf, "calendar.txt"):
                if c["service_id"] in kept_service_ids:
                    kept_calendar.append(c)
        except KeyError:
            pass
        kept_calendar_dates = []
        try:
            for c in read_csv(zf, "calendar_dates.txt"):
                if c["service_id"] in kept_service_ids:
                    kept_calendar_dates.append(c)
        except KeyError:
            pass

    print(f"writing sqlite to {OUT_DB}")
    OUT_DB.parent.mkdir(parents=True, exist_ok=True)
    if OUT_DB.exists():
        OUT_DB.unlink()
    conn = sqlite3.connect(OUT_DB)
    cur = conn.cursor()
    cur.executescript(
        """
        CREATE TABLE stops (
            stop_id TEXT PRIMARY KEY,
            stop_name TEXT,
            stop_lat REAL,
            stop_lon REAL
        );
        CREATE TABLE trips (
            trip_id TEXT PRIMARY KEY,
            route_id TEXT,
            service_id TEXT,
            trip_headsign TEXT,
            direction_id INTEGER,
            shape_id TEXT
        );
        CREATE TABLE stop_times (
            trip_id TEXT,
            arrival_time TEXT,
            departure_time TEXT,
            stop_id TEXT,
            stop_sequence INTEGER
        );
        CREATE INDEX idx_stop_times_stop ON stop_times(stop_id);
        CREATE INDEX idx_stop_times_trip ON stop_times(trip_id);
        CREATE TABLE calendar (
            service_id TEXT PRIMARY KEY,
            monday INTEGER, tuesday INTEGER, wednesday INTEGER,
            thursday INTEGER, friday INTEGER, saturday INTEGER, sunday INTEGER,
            start_date TEXT, end_date TEXT
        );
        CREATE TABLE calendar_dates (
            service_id TEXT,
            date TEXT,
            exception_type INTEGER
        );
        CREATE INDEX idx_caldates_service ON calendar_dates(service_id, date);
        """
    )

    cur.executemany(
        "INSERT INTO stops VALUES (?,?,?,?)",
        [(s["stop_id"], s.get("stop_name"), float(s["stop_lat"]), float(s["stop_lon"])) for s in kept_stops],
    )
    cur.executemany(
        "INSERT INTO trips VALUES (?,?,?,?,?,?)",
        [
            (
                t["trip_id"],
                t["route_id"],
                t["service_id"],
                t.get("trip_headsign"),
                int(t["direction_id"]) if t.get("direction_id") not in (None, "") else None,
                t.get("shape_id"),
            )
            for t in kept_trips
        ],
    )
    cur.executemany(
        "INSERT INTO stop_times VALUES (?,?,?,?,?)",
        [
            (
                st["trip_id"],
                st["arrival_time"],
                st["departure_time"],
                st["stop_id"],
                int(st["stop_sequence"]),
            )
            for st in kept_stop_times
        ],
    )
    cur.executemany(
        "INSERT INTO calendar VALUES (?,?,?,?,?,?,?,?,?,?)",
        [
            (
                c["service_id"],
                int(c["monday"]), int(c["tuesday"]), int(c["wednesday"]),
                int(c["thursday"]), int(c["friday"]), int(c["saturday"]), int(c["sunday"]),
                c["start_date"], c["end_date"],
            )
            for c in kept_calendar
        ],
    )
    cur.executemany(
        "INSERT INTO calendar_dates VALUES (?,?,?)",
        [(c["service_id"], c["date"], int(c["exception_type"])) for c in kept_calendar_dates],
    )
    conn.commit()
    conn.close()

    size_mb = OUT_DB.stat().st_size / (1024 * 1024)
    print(f"done. {len(kept_stops)} stops, {len(kept_trips)} trips, {len(kept_stop_times)} stop_times. db={size_mb:.2f} MB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
