import SwiftUI
import CoreLocation

struct ContentView: View {
    @State private var location = LocationService.shared
    @State private var mode = ModeManager.shared
    @State private var bikes = CitiBikeService.shared
    @State private var path = PathService.shared
    @State private var bus = NJTransitScheduleService.shared
    @State private var subway = MTASubwayService.shared

    @State private var refreshTimer: Timer?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                modeBar
                ScrollView {
                    Group {
                        if mode.current == .home {
                            HomeModeView(bikes: bikes, path: path, bus: bus, subway: subway, here: location.current)
                        } else {
                            OfficeModeView(bikes: bikes, path: path, bus: bus, subway: subway, here: location.current)
                        }
                    }
                    .padding()
                }
                .refreshable { await refreshAll() }
            }
            .navigationTitle("Commute")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            location.start()
            await refreshAll()
            startTimer()
        }
        .onChange(of: location.current?.latitude) { _, _ in
            mode.update(from: location.current)
        }
        .onDisappear { stopTimer() }
    }

    private var modeBar: some View {
        HStack {
            Image(systemName: mode.current == .home ? "house.fill" : "building.2.fill")
            Text(mode.current.label).font(.headline)
            Spacer()
            Picker("Mode", selection: Binding(
                get: { mode.override ?? mode.detected },
                set: { mode.setOverride($0 == mode.detected ? nil : $0) }
            )) {
                Text("Home").tag(CommuteMode.home)
                Text("Office").tag(CommuteMode.office)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.thinMaterial)
    }

    private func refreshAll() async {
        async let b: () = bikes.refresh()
        async let p: () = path.refresh()
        async let s: () = subway.refresh()
        _ = await (b, p, s)
    }

    private func startTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { await refreshAll() }
        }
    }

    private func stopTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}

#Preview {
    ContentView()
}
