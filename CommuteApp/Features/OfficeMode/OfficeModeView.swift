import SwiftUI
import CoreLocation

struct OfficeModeView: View {
    let bikes: CitiBikeService
    let path: PathService
    let bus: NJTransitScheduleService
    let subway: MTASubwayService
    let here: CLLocationCoordinate2D?

    var body: some View {
        VStack(spacing: 12) {
            subwaySection
            bikeSection
            busSection
            pathSection
            ReferencesSection()
        }
    }

    private var origin: CLLocationCoordinate2D {
        Anchors.office
    }

    private var subwaySection: some View {
        SectionCard(title: "E / M / F downtown", systemImage: "tram.tunnel.fill") {
            let efTrains = subway.upcoming(
                stopId: MTAStops.lexAv53Downtown,
                routes: ["E", "F"],
                within: 30
            )
            let mfTrains = subway.upcoming(
                stopId: MTAStops.lexAv63Downtown,
                routes: ["M", "F"],
                within: 30
            )
            let merged = (efTrains + mfTrains).sorted { $0.arrival < $1.arrival }
            if merged.isEmpty {
                EmptyRow(text: "No trains in next 30 min")
            } else {
                ForEach(merged.prefix(6)) { t in
                    DepartureRow(
                        primary: "\(t.routeId) — downtown",
                        secondary: t.stationName,
                        minutes: t.minutesAway,
                        date: t.arrival
                    )
                }
            }
        }
    }

    private var bikeSection: some View {
        SectionCard(title: "Citi Bike near office", systemImage: "bicycle") {
            let stations = bikes.nearestStations(to: origin, count: 3)
            if stations.isEmpty {
                EmptyRow(text: "Loading…")
            } else {
                ForEach(stations) { s in
                    BikeStationRow(station: s, here: origin)
                }
            }
        }
    }

    private var busSection: some View {
        SectionCard(title: "126 Bus from Port Authority", systemImage: "bus.fill") {
            if let dock = bikes.nearestStations(to: Anchors.portAuthority, count: 1).first {
                HStack {
                    Text("Citi Bike docks near PABT")
                        .font(.subheadline)
                    Spacer()
                    Text("\(dock.docksAvailable) open")
                        .font(.subheadline.bold())
                        .foregroundStyle(dock.docksAvailable > 0 ? .green : .red)
                }
                Text(dock.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Divider()
            }
            let deps = bus.nextDepartures(
                stopId: NJTransitStops.portAuthorityDeparture,
                stopName: "Port Authority Bus Terminal",
                withinMinutes: 30,
                headsignContains: ["WILLOW", "CLINTON"]
            )
            if deps.isEmpty {
                EmptyRow(text: "No scheduled departures in next 30 min")
            } else {
                ForEach(deps.prefix(6)) { d in
                    DepartureRow(primary: d.headsign, secondary: nil, minutes: d.minutesAway, date: d.departure)
                }
            }
            Text("Scheduled — does not reflect live delays")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var pathSection: some View {
        SectionCard(title: "PATH 23rd St → Hoboken", systemImage: "tram.fill") {
            let trains = path.departures(from: PathStation.twentyThird, to: PathStation.hoboken, within: 30)
            if trains.isEmpty {
                EmptyRow(text: "No trains in next 30 min")
            } else {
                ForEach(trains.prefix(6)) { t in
                    DepartureRow(primary: "Hoboken", secondary: nil, minutes: t.minutesAway, date: t.departure)
                }
            }
        }
    }
}
