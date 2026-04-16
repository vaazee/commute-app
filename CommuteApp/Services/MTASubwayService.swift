import Foundation

@Observable
final class MTASubwayService {
    static let shared = MTASubwayService()

    private let aceFeedURL = URL(string: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-ace")!
    private let bdfmFeedURL = URL(string: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-bdfm")!

    private(set) var trains: [SubwayTrain] = []
    private(set) var lastUpdated: Date?
    private(set) var lastError: String?

    func refresh() async {
        do {
            async let aceResp = URLSession.shared.data(from: aceFeedURL)
            async let bdfmResp = URLSession.shared.data(from: bdfmFeedURL)
            let (ace, bdfm) = try await (aceResp, bdfmResp)

            var all = GTFSRealtimeParser.parse(ace.0, keepRoutes: ["E"])
            all.append(contentsOf: GTFSRealtimeParser.parse(bdfm.0, keepRoutes: ["M"]))

            self.trains = all.sorted { $0.arrival < $1.arrival }
            self.lastUpdated = Date()
            self.lastError = nil
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    func upcoming(stopId: String, routes: Set<String>, within minutes: Int, now: Date = Date()) -> [SubwayTrain] {
        let limit = TimeInterval(minutes * 60)
        return trains.filter { train in
            train.stopId == stopId
                && routes.contains(train.routeId)
                && train.arrival.timeIntervalSince(now) >= -60
                && train.arrival.timeIntervalSince(now) <= limit
        }
    }
}

// MARK: - Minimal GTFS-realtime protobuf parser.
//
// Only decodes the fields we need from transit_realtime.FeedMessage:
//   FeedMessage.entity            (field 2, repeated)     -> FeedEntity
//   FeedEntity.trip_update        (field 3)               -> TripUpdate
//   TripUpdate.trip               (field 1)               -> TripDescriptor
//   TripUpdate.stop_time_update   (field 2, repeated)     -> StopTimeUpdate
//   TripDescriptor.trip_id        (field 1, string)
//   TripDescriptor.route_id       (field 5, string)
//   StopTimeUpdate.arrival        (field 2)               -> StopTimeEvent
//   StopTimeUpdate.departure      (field 3)               -> StopTimeEvent
//   StopTimeUpdate.stop_id        (field 4, string)
//   StopTimeEvent.time            (field 2, int64 varint) -> unix seconds
//
// Everything else is skipped via the wire-type tag, so unknown/future fields
// don't break decoding. See https://developers.google.com/protocol-buffers/docs/encoding.

private enum GTFSRealtimeParser {
    static func parse(_ data: Data, keepRoutes: Set<String>) -> [SubwayTrain] {
        var r = Reader(data: data)
        var trains: [SubwayTrain] = []
        while let tag = r.readTag() {
            if tag.field == 2 && tag.wire == 2 {
                trains.append(contentsOf: parseEntity(r.readBytes(), keepRoutes: keepRoutes))
            } else {
                r.skip(wire: tag.wire)
            }
        }
        return trains
    }

    private static func parseEntity(_ data: Data, keepRoutes: Set<String>) -> [SubwayTrain] {
        var r = Reader(data: data)
        while let tag = r.readTag() {
            if tag.field == 3 && tag.wire == 2 {
                return parseTripUpdate(r.readBytes(), keepRoutes: keepRoutes)
            }
            r.skip(wire: tag.wire)
        }
        return []
    }

    private static func parseTripUpdate(_ data: Data, keepRoutes: Set<String>) -> [SubwayTrain] {
        var r = Reader(data: data)
        var routeId = ""
        var tripId = ""
        var stops: [Data] = []
        while let tag = r.readTag() {
            switch (tag.field, tag.wire) {
            case (1, 2):
                (tripId, routeId) = parseTripDescriptor(r.readBytes())
            case (2, 2):
                stops.append(r.readBytes())
            default:
                r.skip(wire: tag.wire)
            }
        }
        guard keepRoutes.contains(routeId) else { return [] }
        return stops.compactMap { parseStopTimeUpdate($0, routeId: routeId, tripId: tripId) }
    }

    private static func parseTripDescriptor(_ data: Data) -> (tripId: String, routeId: String) {
        var r = Reader(data: data)
        var tripId = ""
        var routeId = ""
        while let tag = r.readTag() {
            switch (tag.field, tag.wire) {
            case (1, 2): tripId = r.readString()
            case (5, 2): routeId = r.readString()
            default: r.skip(wire: tag.wire)
            }
        }
        return (tripId, routeId)
    }

    private static func parseStopTimeUpdate(_ data: Data, routeId: String, tripId: String) -> SubwayTrain? {
        var r = Reader(data: data)
        var stopId = ""
        var arrival: Date?
        var departure: Date?
        while let tag = r.readTag() {
            switch (tag.field, tag.wire) {
            case (4, 2): stopId = r.readString()
            case (2, 2): arrival = parseStopTimeEvent(r.readBytes())
            case (3, 2): departure = parseStopTimeEvent(r.readBytes())
            default: r.skip(wire: tag.wire)
            }
        }
        guard !stopId.isEmpty, let time = arrival ?? departure else { return nil }
        return SubwayTrain(
            id: "\(tripId)-\(stopId)-\(Int(time.timeIntervalSince1970))",
            routeId: routeId,
            stopId: stopId,
            stationName: MTAStops.stationName[stopId] ?? stopId,
            tripId: tripId,
            arrival: time
        )
    }

    private static func parseStopTimeEvent(_ data: Data) -> Date? {
        var r = Reader(data: data)
        while let tag = r.readTag() {
            if tag.field == 2 && tag.wire == 0 {
                let unix = Int64(bitPattern: r.readVarint())
                return Date(timeIntervalSince1970: TimeInterval(unix))
            }
            r.skip(wire: tag.wire)
        }
        return nil
    }

    private struct Reader {
        let data: Data
        var cursor: Int = 0

        mutating func readTag() -> (field: Int, wire: Int)? {
            if cursor >= data.count { return nil }
            let tag = readVarint()
            return (Int(tag >> 3), Int(tag & 0x7))
        }

        mutating func readVarint() -> UInt64 {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while cursor < data.count {
                let byte = data[data.startIndex + cursor]
                cursor += 1
                result |= UInt64(byte & 0x7F) << shift
                if (byte & 0x80) == 0 { return result }
                shift += 7
                if shift >= 64 { return result }
            }
            return result
        }

        mutating func readBytes() -> Data {
            let len = Int(readVarint())
            let start = data.startIndex + cursor
            let end = min(start + len, data.endIndex)
            cursor += (end - start)
            return data.subdata(in: start..<end)
        }

        mutating func readString() -> String {
            String(data: readBytes(), encoding: .utf8) ?? ""
        }

        mutating func skip(wire: Int) {
            switch wire {
            case 0: _ = readVarint()
            case 1: cursor += 8
            case 2: _ = readBytes()
            case 5: cursor += 4
            default: cursor = data.count
            }
        }
    }
}
