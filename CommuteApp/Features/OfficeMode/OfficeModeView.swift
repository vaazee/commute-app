import SwiftUI
import CoreLocation

struct OfficeModeView: View {
    let bikes: CitiBikeService
    let path: PathService
    let bus: NJTransitScheduleService
    let here: CLLocationCoordinate2D?

    var body: some View {
        VStack(spacing: 12) {
            bikeSection
            busSection
            pathSection
        }
    }

    private var origin: CLLocationCoordinate2D {
        Anchors.office
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
