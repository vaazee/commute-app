import SwiftUI
import CoreLocation

struct HomeModeView: View {
    let bikes: CitiBikeService
    let path: PathService
    let bus: NJTransitScheduleService
    let subway: MTASubwayService
    let here: CLLocationCoordinate2D?

    var body: some View {
        VStack(spacing: 12) {
            busSection
            subwaySection
            bikeSection
            pathSection
            ReferencesSection()
        }
    }

    private var origin: CLLocationCoordinate2D {
        Anchors.home
    }

    private var busSection: some View {
        SectionCard(title: "126 Bus → NYC", systemImage: "bus.fill") {
            let nycViaWillowOrClinton = ["NEW YORK VIA CLINTON", "NEW YORK VIA WILLOW"]
            let nearestStop = bus.nearestStops(
                to: origin,
                limit: 1,
                headsignContains: nycViaWillowOrClinton,
                headsignExcludes: []
            ).first
            if let stop = nearestStop {
                let deps = bus.nextDepartures(
                    stopId: stop.stopId,
                    stopName: stop.name,
                    withinMinutes: 20,
                    headsignContains: nycViaWillowOrClinton,
                    headsignExcludes: []
                )
                Text(stop.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if deps.isEmpty {
                    EmptyRow(text: "No scheduled departures in next 20 min")
                } else {
                    ForEach(deps.prefix(5)) { d in
                        DepartureRow(primary: d.headsign, secondary: nil, minutes: d.minutesAway, date: d.departure)
                    }
                }
                Text("Scheduled — does not reflect live delays")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                EmptyRow(text: "No nearby 126 stop")
            }
        }
    }

    private var subwaySection: some View {
        SectionCard(title: "E uptown @ Port Auth", systemImage: "tram.tunnel.fill") {
            let trains = subway.upcoming(
                stopId: MTAStops.portAuthorityACEUptown,
                routes: ["E"],
                within: 30
            )
            if trains.isEmpty {
                EmptyRow(text: "No trains in next 30 min")
            } else {
                ForEach(trains.prefix(6)) { t in
                    DepartureRow(primary: "E — uptown", secondary: nil, minutes: t.minutesAway, date: t.arrival)
                }
            }
        }
    }

    private var bikeSection: some View {
        SectionCard(title: "Citi Bike near home", systemImage: "bicycle") {
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

    private var pathSection: some View {
        SectionCard(title: "Hoboken PATH", systemImage: "tram.fill") {
            if let dock = bikes.station(named: "Hoboken Terminal") {
                HStack {
                    Text("Citi Bike docks at terminal")
                        .font(.subheadline)
                    Spacer()
                    Text("\(dock.docksAvailable) open")
                        .font(.subheadline.bold())
                        .foregroundStyle(dock.docksAvailable > 0 ? .green : .red)
                }
            }
            Divider()
            Text("Next trains Hoboken → 33rd St")
                .font(.caption)
                .foregroundStyle(.secondary)
            let trains = path.departures(from: PathStation.hoboken, to: PathStation.thirtyThird, within: 30)
            if trains.isEmpty {
                EmptyRow(text: "No trains in next 30 min")
            } else {
                ForEach(trains.prefix(5)) { t in
                    DepartureRow(primary: "33rd Street", secondary: nil, minutes: t.minutesAway, date: t.departure)
                }
            }
        }
    }
}
