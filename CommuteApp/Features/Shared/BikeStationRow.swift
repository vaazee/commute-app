import SwiftUI
import CoreLocation

struct BikeStationRow: View {
    let station: BikeStation
    let here: CLLocationCoordinate2D?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(station.name).font(.subheadline).lineLimit(1)
                if let here {
                    let meters = station.distance(from: here)
                    Text(formatDistance(meters))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 12) {
                stat("\(station.bikesAvailable)", "bicycle", .green)
                stat("\(station.docksAvailable)", "p.square.fill", .blue)
            }
        }
    }

    @ViewBuilder
    private func stat(_ value: String, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).foregroundStyle(color)
            Text(value).font(.subheadline.monospacedDigit())
        }
    }

    private func formatDistance(_ m: CLLocationDistance) -> String {
        if m < 1000 { return "\(Int(m)) m" }
        return String(format: "%.1f km", m / 1000)
    }
}

struct DepartureRow: View {
    let primary: String
    let secondary: String?
    let minutes: Int
    let date: Date

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(primary).font(.subheadline)
                if let secondary {
                    Text(secondary).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(minutes) min").font(.subheadline.monospacedDigit().bold())
                Text(date.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
