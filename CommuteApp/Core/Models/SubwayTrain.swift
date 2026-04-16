import Foundation

struct SubwayTrain: Identifiable, Hashable {
    let id: String
    let routeId: String
    let stopId: String
    let stationName: String
    let tripId: String
    let arrival: Date

    var minutesAway: Int {
        max(0, Int(arrival.timeIntervalSinceNow / 60))
    }
}

enum MTAStops {
    // MTA GTFS stop IDs use an `N`/`S` suffix in realtime feeds to disambiguate direction.
    // 42 St-Port Authority on the A/C/E line; `N` = northbound (E→Jamaica).
    static let portAuthorityACEUptown = "A27N"

    // Lexington Av/53 St on the E line; `S` = downtown (E→WTC).
    static let lexAv53Downtown = "F11S"

    // Lexington Av/63 St on the M line; `S` = downtown (M→Essex/Middle Village).
    // The M currently uses the 63rd St tunnel rather than the 53rd St tunnel, so the
    // nearest M stop to the office is Lex/63, one block north of Lex/53.
    static let lexAv63Downtown = "B08S"

    static let stationName: [String: String] = [
        "A27N": "42 St-Port Authority",
        "F11S": "Lexington Av/53 St",
        "B08S": "Lexington Av/63 St",
    ]
}
