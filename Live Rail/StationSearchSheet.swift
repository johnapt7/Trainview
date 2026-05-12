import SwiftUI

struct StationSearchSheet: View {
    let currentStation: String
    let onSelect: (Station) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [StationResponse] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var resultCache: [String: [StationResponse]] = [:]

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
            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                withAnimation(.easeOut(duration: 0.15)) { results = [] }
                isSearching = false
                return
            }

            let key = trimmed.lowercased()
            if let cached = cachedResults(for: key) {
                withAnimation(.easeOut(duration: 0.15)) {
                    results = cached.filter { $0.crs != currentStation }
                }
                return
            }

            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                isSearching = true
                let found = (try? await APIClient.shared.searchStations(query: trimmed)) ?? []
                guard !Task.isCancelled else { return }
                resultCache[key] = found
                withAnimation(.easeOut(duration: 0.15)) {
                    results = found.filter { $0.crs != currentStation }
                }
                isSearching = false
            }
        }
    }

    private func cachedResults(for query: String) -> [StationResponse]? {
        if let cached = resultCache[query] { return cached }
        var prefix = String(query.dropLast())
        while !prefix.isEmpty {
            if let cached = resultCache[prefix], cached.count < 10 {
                return cached.filter {
                    $0.name.lowercased().contains(query) ||
                    $0.crs.lowercased().contains(query)
                }
            }
            prefix = String(prefix.dropLast())
        }
        return nil
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if isSearching && results.isEmpty {
                    ProgressView()
                        .tint(Theme.inkMute)
                        .padding(.top, 28)
                } else if !query.isEmpty && results.isEmpty && !isSearching {
                    VStack(spacing: 6) {
                        Text("No stations found")
                            .font(.ui(14, weight: .medium))
                            .foregroundStyle(Theme.inkMute)
                        Text("Try a different name or CRS code")
                            .font(.ui(12))
                            .foregroundStyle(Theme.inkMute.opacity(0.7))
                    }
                    .padding(.top, 28)
                } else {
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
