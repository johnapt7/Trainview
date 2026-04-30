import SwiftUI

struct BoardScreen: View {
    let station: Station
    let accent: Color
    let onOpenTrain: (Train) -> Void
    let onBack: () -> Void

    @State private var mode: BoardMode = .departures
    @State private var filter: FilterMode = .all
    @State private var services: [Train] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var nrccMessages: [String] = []
    @State private var callingPoints: [String: [String]] = [:]
    @State private var predictedPlatforms: [String: PredictedPlatform] = [:]

    private var filtered: [Train] {
        switch filter {
        case .all: return services
        case .onTime: return services.filter { $0.status == .onTime }
        case .intercity: return services.filter {
            ["GR", "XC", "AW", "GW", "TP", "VT", "EM", "HT", "GC"].contains($0.operatorCode)
        }
        }
    }

    private var isArrival: Bool { mode == .arrivals }

    private var timeString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: Date())
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                headerSection
                if !nrccMessages.isEmpty {
                    nrccBanner
                }
                filterRow
                resultsRow
                trainList
            }
        }
        .background(Theme.cream)
        .refreshable {
            await loadBoard()
        }
        .task {
            await loadBoard()
        }
        .onChange(of: mode) { _, _ in
            Task { await loadBoard() }
        }
    }

    // MARK: - Data

    private func loadBoard() async {
        isLoading = true
        loadError = nil
        do {
            let response = try await APIClient.shared.getBoard(
                crs: station.code,
                type: mode == .departures ? "departures" : "arrivals"
            )
            withAnimation(.easeOut(duration: 0.3)) {
                services = response.services.map { Train(from: $0) }
                nrccMessages = response.nrccMessages ?? []
            }
        } catch {
            services = []
            nrccMessages = []
            loadError = (error as? APIError)?.errorDescription ?? "Could not load services"
        }
        isLoading = false
        loadCallingPoints()
    }

    private func loadCallingPoints() {
        callingPoints = [:]
        predictedPlatforms = [:]
        let currentMode = mode
        let currentCRS = station.code
        for train in services {
            Task {
                guard let details = try? await APIClient.shared.getServiceDetails(serviceId: train.serviceId, crs: currentCRS) else { return }
                let points: [String]
                if currentMode == .departures {
                    points = details.subsequentCallingPoints.map { $0.station }
                } else {
                    points = details.previousCallingPoints.map { $0.station }
                }
                withAnimation(.easeIn(duration: 0.25)) {
                    callingPoints[train.serviceId] = points
                    if let pred = details.predictedPlatform {
                        predictedPlatforms[train.serviceId] = pred
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 0) {
            topBar
            stationCard
        }
        .padding(.horizontal, 18)
        .padding(.top, 62)
    }

    private var topBar: some View {
        HStack {
            IconButton(systemName: "chevron.left", size: 14, action: onBack)

            Spacer()

            HStack(spacing: 2) {
                tabButton("Departures", isActive: mode == .departures) {
                    mode = .departures
                    filter = .all
                }
                tabButton("Arrivals", isActive: mode == .arrivals) {
                    mode = .arrivals
                    filter = .all
                }
            }
            .padding(4)
            .background(Theme.ink.opacity(0.08))
            .clipShape(Capsule())

            Spacer()

            IconButton(systemName: "magnifyingglass", size: 14)
        }
        .padding(.vertical, 6)
        .padding(.bottom, 10)
    }

    private func tabButton(_ title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.ui(12, weight: .medium))
                .tracking(0.1)
                .foregroundStyle(isActive ? Theme.cream : Theme.inkSoft)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(isActive ? Theme.ink : .clear)
                .clipShape(Capsule())
        }
    }

    // MARK: - Station Card

    private var stationCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "mappin")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.inkMute)
                Text(isArrival ? "ARRIVING AT" : "DEPARTING FROM")
                    .font(.mono(10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.inkMute)
                Spacer()
                Text("\(services.count) \(isArrival ? "INBOUND" : "OUTBOUND")")
                    .font(.mono(10, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(Theme.inkMute)
            }

            HStack(alignment: .bottom) {
                Text(station.name)
                    .font(.display(30))
                    .tracking(-0.3)
                    .lineLimit(1)
                Spacer()
                Button(action: onBack) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(accent)
                        .frame(width: 34, height: 34)
                        .background(Theme.ink)
                        .clipShape(Circle())
                }
            }
            .padding(.top, 6)

            PlatformStrip(accent: accent)
                .padding(.vertical, 10)

            HStack(spacing: 8) {
                CodeTag(text: station.code)
                DotSeparator()
                HStack(spacing: 4) {
                    LiveDot(size: 10)
                    Text("Live")
                        .font(.mono(11, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .shadow(color: Theme.ink.opacity(0.05), radius: 0, y: 1)
    }

    // MARK: - NRCC Messages

    private func stripHTML(_ html: String) -> String {
        var text = html
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "</p>\\s*<p[^>]*>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "\\s*\\n\\s*", with: "\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var nrccBanner: some View {
        VStack(spacing: 8) {
            ForEach(nrccMessages, id: \.self) { message in
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.delayedText)
                    Text(stripHTML(message))
                        .font(.ui(12))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.warn.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
    }

    // MARK: - Filters

    private var filterRow: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkSoft)
                Text("NOW \u{00B7} \(timeString)")
                    .font(.mono(11, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            HStack(spacing: 6) {
                filterChip("All", mode: .all)
                filterChip("On time", mode: .onTime)
                filterChip("Intercity", mode: .intercity)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    private func filterChip(_ label: String, mode: FilterMode) -> some View {
        Button {
            filter = mode
        } label: {
            Text(label)
                .font(.ui(11, weight: filter == mode ? .semibold : .medium))
                .foregroundStyle(filter == mode ? Theme.ink : Theme.inkSoft)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(filter == mode ? accent : Theme.ink.opacity(0.06))
                .clipShape(Capsule())
        }
    }

    // MARK: - Results Row

    private var resultsRow: some View {
        HStack(alignment: .bottom) {
            HStack(alignment: .bottom, spacing: 8) {
                Text("\(filtered.count)")
                    .font(.display(52))
                    .tracking(-1)
                    .lineSpacing(-8)
                VStack(alignment: .leading, spacing: 0) {
                    Text("trains")
                    Text(isArrival ? "arriving" : "departing")
                }
                .font(.mono(11))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(Theme.inkSoft)
                .padding(.bottom, 3)
            }
            Spacer()
            Button {} label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 40, height: 40)
                        .background(Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Theme.line, lineWidth: 1)
                        )
                    if filter != .all {
                        Circle()
                            .fill(Color(hex: 0xC94A2E))
                            .frame(width: 7, height: 7)
                            .offset(x: -8, y: 8)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 14)
    }

    // MARK: - Train List

    private var trainList: some View {
        VStack(spacing: 12) {
            if isLoading && services.isEmpty {
                ForEach(0..<4, id: \.self) { _ in
                    SkeletonTrainCard()
                }
            } else if let error = loadError {
                VStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.inkMute)
                    Text("Couldn't load board")
                        .font(.display(18))
                    Text(error)
                        .font(.ui(11))
                        .foregroundStyle(Theme.inkMute)
                    Button {
                        Task { await loadBoard() }
                    } label: {
                        Text("Try again")
                            .font(.ui(13, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(accent)
                            .clipShape(Capsule())
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else if services.isEmpty {
                VStack(spacing: 4) {
                    Text("No services")
                        .font(.display(18))
                    Text("No \(isArrival ? "arrivals" : "departures") currently scheduled")
                        .font(.ui(11))
                        .foregroundStyle(Theme.inkMute)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                ForEach(Array(filtered.enumerated()), id: \.element.id) { index, train in
                    TrainCard(
                        train: train,
                        mode: mode,
                        accent: accent,
                        callingPoints: callingPoints[train.serviceId] ?? [],
                        predictedPlatform: predictedPlatforms[train.serviceId]
                    ) {
                        onOpenTrain(train)
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .bottom)),
                        removal: .opacity
                    ))
                    .animation(.easeOut(duration: 0.3).delay(Double(index) * 0.04), value: filtered.count)
                }
            }
            HStack {
                Text(isArrival ? "END OF SCHEDULED ARRIVALS" : "END OF SCHEDULED DEPARTURES")
                    .font(.mono(10))
                    .tracking(1.8)
                    .foregroundStyle(Theme.inkMute)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 22)
            .padding(.bottom, 6)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 40)
    }
}

// MARK: - Train Card

struct TrainCard: View {
    let train: Train
    let mode: BoardMode
    let accent: Color
    let callingPoints: [String]
    var predictedPlatform: PredictedPlatform? = nil
    let onTap: () -> Void

    private var isArrival: Bool { mode == .arrivals }
    private var isPredicted: Bool {
        train.platform == "—" && predictedPlatform != nil
    }
    private var displayPlatform: String {
        if isPredicted { return predictedPlatform!.platform }
        return train.platform
    }
    private var ribbonColor: Color {
        if train.status == .cancelled { return Theme.bad }
        if isPredicted { return accent.opacity(0.45) }
        return accent
    }

    private var callingPreview: [String] {
        guard !callingPoints.isEmpty else { return [] }
        if isArrival {
            return Array(callingPoints.dropFirst().suffix(3))
        } else {
            return Array(callingPoints.dropLast().prefix(3))
        }
    }

    private var hasMoreStops: Bool {
        if isArrival {
            return callingPoints.dropFirst().count > 3
        } else {
            return callingPoints.dropLast().count > 3
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                ribbon
                cardBody
            }
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: Theme.ink.opacity(0.04), radius: 0, y: 1)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Ribbon

    private var ribbon: some View {
        VStack(spacing: 0) {
            Text(isPredicted ? "PREDICTED" : "PLATFORM")
                .font(.mono(isPredicted ? 9 : 10, weight: .medium))
                .tracking(isPredicted ? 1.8 : 2.4)
                .rotationEffect(.degrees(-90))
                .fixedSize()
                .frame(maxHeight: .infinity)

            Text(displayPlatform)
                .font(.display(26))
                .tracking(-0.3)
                .strikethrough(train.status == .cancelled)
                .opacity(train.status == .cancelled ? 0.7 : 1)
        }
        .foregroundStyle(isPredicted ? Theme.ink.opacity(0.7) : Theme.ink)
        .frame(width: 42)
        .padding(.vertical, 14)
        .background(ribbonColor)
        .overlay(alignment: .leading) {
            if isPredicted {
                Rectangle()
                    .fill(.clear)
                    .frame(width: 2)
                    .overlay(
                        Line()
                            .stroke(Theme.ink.opacity(0.25), style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                    )
            }
        }
    }

    // MARK: - Body

    private var cardBody: some View {
        VStack(spacing: 10) {
            topRow
            routeSection
            if let reason = train.cancelReason ?? train.delayReason {
                reasonRow(reason)
            }
            if !callingPreview.isEmpty {
                callingRow
            }
            bottomRow
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var topRow: some View {
        HStack(alignment: .top) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(train.time)
                    .font(.mono(22, weight: .medium))
                    .tracking(-0.2)
                    .foregroundStyle(train.status == .delayed ? Theme.inkMute : timeColor)
                    .strikethrough(train.status == .cancelled || train.status == .delayed)
                if train.status == .delayed {
                    Text(train.statusNote)
                        .font(.mono(18, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(Theme.delayedText)
                }
            }
            Spacer()
            StatusPill(
                status: train.status,
                label: train.status == .delayed ? "Delayed" : train.statusNote
            )
        }
    }

    private var timeColor: Color {
        switch train.status {
        case .delayed: return Theme.delayedText
        case .cancelled: return Theme.cancelledText.opacity(0.75)
        case .onTime: return Theme.ink
        }
    }

    private var routeSection: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Circle()
                    .fill(Theme.ink)
                    .frame(width: 6, height: 6)
                DashedLine()
                    .stroke(Theme.inkMute.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [2, 3]))
                    .frame(width: 2, height: 24)
            }
            .frame(width: 12)
            .padding(.top, 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(isArrival ? "FROM" : "TO")
                    .font(.mono(9, weight: .semibold))
                    .tracking(1.3)
                    .foregroundStyle(Theme.inkMute)
                Text(isArrival ? train.origin : train.destination)
                    .font(.display(21))
                    .tracking(-0.1)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                if !train.via.isEmpty {
                    Text("via \(train.via)")
                        .font(.ui(11))
                        .foregroundStyle(Theme.inkMute)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }

    private func reasonRow(_ reason: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(train.status == .cancelled ? Theme.cancelledText : Theme.delayedText)
            Text(reason)
                .font(.ui(11))
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(train.status == .cancelled ? Theme.bad.opacity(0.15) : Theme.warn.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var callingRow: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 9))
                .foregroundStyle(Theme.inkMute)
            Text(callingPreview.joined(separator: " \u{00B7} ") + (hasMoreStops ? " \u{00B7}\u{00B7}\u{00B7}" : ""))
                .font(.ui(11))
                .foregroundStyle(Theme.inkMute)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var operatorBrand: OperatorBrand {
        OperatorBrand.brand(for: train.operatorCode)
    }

    private var bottomRow: some View {
        HStack {
            HStack(spacing: 0) {
                Text(train.operatorCode)
                    .font(.mono(9, weight: .bold))
                    .tracking(0.5)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .background(operatorBrand.bg)
                    .foregroundStyle(operatorBrand.fg)
                Text(train.operator)
                    .font(.ui(11, weight: .medium))
                    .foregroundStyle(operatorBrand.bg)
                    .lineLimit(1)
                    .padding(.leading, 6)
                    .padding(.trailing, 8)
                    .padding(.vertical, 4)
            }
            .background(operatorBrand.bg.opacity(0.1))
            .clipShape(Capsule())
            Spacer(minLength: 10)
            if let carriages = train.carriages {
                HStack(spacing: 5) {
                    Image(systemName: "tram.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.inkMute)
                    Text("\(carriages)")
                        .font(.mono(10))
                        .foregroundStyle(Theme.inkMute)
                }
            }
        }
        .padding(.top, 8)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.clear)
                .frame(height: 1)
                .overlay(
                    Line()
                        .stroke(Theme.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
        }
    }
}

// MARK: - Shapes

private struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        }
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}
