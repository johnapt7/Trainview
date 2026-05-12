import SwiftUI

struct StationSearchSheet: View {
    let currentStation: String
    let onSelect: (Station) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [StationResponse] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            handle
            header
            searchField
            resultsList
            Spacer()
        }
        .background(Theme.cream)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    private var handle: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Theme.ink.opacity(0.2))
            .frame(width: 36, height: 4)
            .padding(.top, 10)
            .padding(.bottom, 20)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("FILTER BY DESTINATION")
                .font(.mono(10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Theme.inkMute)
            Text("Calling at...")
                .font(.display(26, weight: .medium))
                .tracking(-0.3)
        }
        .padding(.bottom, 20)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(Theme.inkMute)
            TextField("Search station", text: $query)
                .font(.ui(15))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
            if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.inkMute)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.line, lineWidth: 1)
        )
        .padding(.horizontal, 22)
        .onChange(of: query) { _, newValue in
            searchTask?.cancel()
            guard newValue.count >= 2 else {
                results = []
                return
            }
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                isSearching = true
                let found = (try? await APIClient.shared.searchStations(query: newValue)) ?? []
                guard !Task.isCancelled else { return }
                results = found.filter { $0.crs != currentStation }
                isSearching = false
            }
        }
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(results) { station in
                    Button {
                        onSelect(Station(from: station))
                        dismiss()
                    } label: {
                        stationRow(station)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 8)
        }
        .padding(.top, 8)
    }

    private func stationRow(_ station: StationResponse) -> some View {
        HStack(spacing: 12) {
            Image(systemName: station.isInterchange ? "arrow.triangle.branch" : "tram.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkMute)
                .frame(width: 28, height: 28)
                .background(Theme.ink.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text(station.name)
                    .font(.ui(14, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Text(station.crs)
                    .font(.mono(10, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(Theme.inkMute)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.inkMute)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }
}
