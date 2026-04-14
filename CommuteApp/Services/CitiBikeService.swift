import Foundation
import CoreLocation

@Observable
final class CitiBikeService {
    static let shared = CitiBikeService()

    private let infoURL = URL(string: "https://gbfs.citibikenyc.com/gbfs/en/station_information.json")!
    private let statusURL = URL(string: "https://gbfs.citibikenyc.com/gbfs/en/station_status.json")!

    private var infoCache: [String: StationInfo] = [:]
    private var infoCacheTimestamp: Date?
    private let infoCacheTTL: TimeInterval = 3600

    private(set) var stations: [BikeStation] = []
    private(set) var lastUpdated: Date?
    private(set) var lastError: String?

    func refresh() async {
        do {
            let info = try await loadInfoIfNeeded()
            let status = try await fetchStatus()
            let merged = status.compactMap { s -> BikeStation? in
                guard let i = info[s.station_id] else { return nil }
                return BikeStation(
                    id: s.station_id,
                    name: i.name,
                    coordinate: CLLocationCoordinate2D(latitude: i.lat, longitude: i.lon),
                    capacity: i.capacity,
                    bikesAvailable: s.num_bikes_available,
                    ebikesAvailable: s.num_ebikes_available ?? 0,
                    docksAvailable: s.num_docks_available,
                    isRenting: s.is_renting == 1,
                    isReturning: s.is_returning == 1,
                    lastReported: Date(timeIntervalSince1970: TimeInterval(s.last_reported))
                )
            }
            self.stations = merged
            self.lastUpdated = Date()
            self.lastError = nil
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    func nearestStations(to coord: CLLocationCoordinate2D, count: Int) -> [BikeStation] {
        stations
            .filter { $0.isRenting }
            .sorted { $0.distance(from: coord) < $1.distance(from: coord) }
            .prefix(count)
            .map { $0 }
    }

    func station(named name: String) -> BikeStation? {
        stations.first { $0.name.localizedCaseInsensitiveContains(name) }
    }

    private func loadInfoIfNeeded() async throws -> [String: StationInfo] {
        if let ts = infoCacheTimestamp, Date().timeIntervalSince(ts) < infoCacheTTL, !infoCache.isEmpty {
            return infoCache
        }
        let (data, _) = try await URLSession.shared.data(from: infoURL)
        let decoded = try JSONDecoder().decode(GBFSResponse<StationInfoData>.self, from: data)
        let map = Dictionary(uniqueKeysWithValues: decoded.data.stations.map { ($0.station_id, $0) })
        self.infoCache = map
        self.infoCacheTimestamp = Date()
        return map
    }

    private func fetchStatus() async throws -> [StationStatus] {
        let (data, _) = try await URLSession.shared.data(from: statusURL)
        let decoded = try JSONDecoder().decode(GBFSResponse<StationStatusData>.self, from: data)
        return decoded.data.stations
    }
}

private struct GBFSResponse<T: Decodable>: Decodable {
    let data: T
}

private struct StationInfoData: Decodable {
    let stations: [StationInfo]
}

private struct StationInfo: Decodable {
    let station_id: String
    let name: String
    let lat: Double
    let lon: Double
    let capacity: Int
}

private struct StationStatusData: Decodable {
    let stations: [StationStatus]
}

private struct StationStatus: Decodable {
    let station_id: String
    let num_bikes_available: Int
    let num_ebikes_available: Int?
    let num_docks_available: Int
    let is_renting: Int
    let is_returning: Int
    let last_reported: Int
}
