import Foundation
import CoreLocation

struct BikeStation: Identifiable, Hashable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let capacity: Int
    let bikesAvailable: Int
    let ebikesAvailable: Int
    let docksAvailable: Int
    let isRenting: Bool
    let isReturning: Bool
    let lastReported: Date

    func distance(from coord: CLLocationCoordinate2D) -> CLLocationDistance {
        let a = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let b = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        return a.distance(from: b)
    }

    static func == (lhs: BikeStation, rhs: BikeStation) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
