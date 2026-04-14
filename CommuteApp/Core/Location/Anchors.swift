import CoreLocation

enum Anchors {
    // 610 Clinton St, Hoboken NJ — between 6th and 7th St
    static let home = CLLocationCoordinate2D(latitude: 40.7451, longitude: -74.0332)
    // 919 3rd Ave, New York NY — between 55th and 56th St
    static let office = CLLocationCoordinate2D(latitude: 40.7603, longitude: -73.9677)
}

enum CommuteMode: String, CaseIterable, Identifiable {
    case home, office
    var id: String { rawValue }
    var label: String { self == .home ? "From Home" : "From Office" }
}
