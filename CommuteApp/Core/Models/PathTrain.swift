import Foundation

struct PathTrain: Identifiable, Hashable {
    let id: String
    let routeId: String
    let originStopId: String
    let destinationStopId: String
    let departure: Date

    var minutesAway: Int {
        max(0, Int(departure.timeIntervalSinceNow / 60))
    }
}

enum PathStation {
    static let hoboken = "HOB"
    static let thirtyThird = "33S"
    static let twentyThird = "23S"
}

enum PathRoute {
    static let hobokenThirtyThird = "HOB_33"
}
