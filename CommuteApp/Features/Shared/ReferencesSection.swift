import SwiftUI

struct ReferencesSection: View {
    var body: some View {
        SectionCard(title: "References", systemImage: "link") {
            Link(destination: URL(string: "https://content.njtransit.com/pdf/schedules/bus/126")!) {
                ReferenceRow(
                    icon: "bus.fill",
                    title: "NJ Transit 126 schedule (PDF)",
                    subtitle: "content.njtransit.com"
                )
            }
            Divider()
            Link(destination: URL(string: "https://mybusnow.njtransit.com/bustime/wireless/html/selectdirection.jsp?route=126")!) {
                ReferenceRow(
                    icon: "dot.radiowaves.left.and.right",
                    title: "126 live (MyBusNow)",
                    subtitle: "mybusnow.njtransit.com"
                )
            }
            Divider()
            Link(destination: URL(string: "https://www.panynj.gov/path/en/schedules-maps.html")!) {
                ReferenceRow(
                    icon: "tram.fill",
                    title: "PATH schedules & maps",
                    subtitle: "panynj.gov/path"
                )
            }
            Divider()
            Link(destination: URL(string: "https://account.citibikenyc.com/map")!) {
                ReferenceRow(
                    icon: "bicycle",
                    title: "Citi Bike station map",
                    subtitle: "account.citibikenyc.com/map"
                )
            }
        }
    }
}

private struct ReferenceRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "arrow.up.right.square")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}
