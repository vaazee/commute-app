import Foundation

struct BusDeparture: Identifiable, Hashable {
    let id: String
    let routeShortName: String
    let headsign: String
    let stopId: String
    let stopName: String
    let departure: Date

    var minutesAway: Int {
        max(0, Int(departure.timeIntervalSinceNow / 60))
    }
}

enum NJTransitStops {
    static let portAuthorityDeparture = "3511"
}
