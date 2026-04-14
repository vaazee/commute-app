import CoreLocation
import Observation

@Observable
final class ModeManager {
    static let shared = ModeManager()

    var override: CommuteMode?
    var detected: CommuteMode = .home

    var current: CommuteMode { override ?? detected }

    func update(from coord: CLLocationCoordinate2D?) {
        guard let coord else { return }
        let here = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        let dHome = here.distance(from: CLLocation(latitude: Anchors.home.latitude, longitude: Anchors.home.longitude))
        let dOffice = here.distance(from: CLLocation(latitude: Anchors.office.latitude, longitude: Anchors.office.longitude))
        detected = dHome <= dOffice ? .home : .office
    }

    func setOverride(_ mode: CommuteMode?) {
        override = mode
    }
}
