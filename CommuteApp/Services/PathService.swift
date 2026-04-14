import Foundation

@Observable
final class PathService {
    static let shared = PathService()

    private let feedURL = URL(string: "https://www.panynj.gov/bin/portauthority/ridepath.json")!

    private(set) var stations: [String: [PathTrain]] = [:]
    private(set) var lastUpdated: Date?
    private(set) var lastError: String?

    func refresh() async {
        do {
            let (data, _) = try await URLSession.shared.data(from: feedURL)
            let decoded = try JSONDecoder().decode(RidePathResponse.self, from: data)
            self.stations = parse(decoded)
            self.lastUpdated = Date()
            self.lastError = nil
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    func departures(from origin: String, to terminus: String, within minutes: Int) -> [PathTrain] {
        let limit = TimeInterval(minutes * 60)
        return (stations[origin] ?? [])
            .filter { $0.destinationStopId == terminus }
            .filter { $0.departure.timeIntervalSinceNow >= -60 && $0.departure.timeIntervalSinceNow <= limit }
            .sorted { $0.departure < $1.departure }
    }

    private func parse(_ resp: RidePathResponse) -> [String: [PathTrain]] {
        var byStation: [String: [PathTrain]] = [:]
        for result in resp.results {
            var trains: [PathTrain] = []
            for dest in result.destinations {
                for msg in dest.messages {
                    let secs = TimeInterval(Int(msg.secondsToArrival) ?? 0)
                    let dep = Date().addingTimeInterval(secs)
                    let id = "\(result.consideredStation)-\(msg.target)-\(msg.secondsToArrival)-\(msg.lastUpdated)"
                    trains.append(PathTrain(
                        id: id,
                        routeId: msg.lineColor,
                        originStopId: result.consideredStation,
                        destinationStopId: msg.target,
                        departure: dep
                    ))
                }
            }
            byStation[result.consideredStation] = trains
        }
        return byStation
    }
}

private struct RidePathResponse: Decodable {
    let results: [StationResult]
}

private struct StationResult: Decodable {
    let consideredStation: String
    let destinations: [Destination]
}

private struct Destination: Decodable {
    let label: String
    let messages: [TrainMessage]
}

private struct TrainMessage: Decodable {
    let target: String
    let secondsToArrival: String
    let arrivalTimeMessage: String
    let lineColor: String
    let headSign: String
    let lastUpdated: String
}
