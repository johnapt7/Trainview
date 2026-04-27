import SwiftUI

struct JourneyScreen: View {
    let train: Train
    let accent: Color
    let onBack: () -> Void

    @State private var details: ServiceDetailsResponse?
    @State private var stops: [Stop] = []
    @State private var duration: String = ""
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var reliability: ReliabilityStats?

    private var originName: String { details?.origin?.name ?? train.origin }
    private var destName: String { details?.destination?.name ?? train.destination }
    private var originCrs: String { details?.origin?.crs ?? "" }
    private var destCrs: String { details?.destination?.crs ?? "" }
    private var departPlatform: String { details?.platform ?? train.platform }

    private var heroBg: Color {
        switch train.status {
        case .cancelled: return Theme.bad
        case .delayed: return Theme.warn
        case .onTime: return accent
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                heroSection
                if isLoading {
                    loadingSection
                } else if let error = loadError {
                    errorSection(error)
                } else {
                    factsRow
                    if let reason = train.cancelReason ?? train.delayReason {
                        reasonBanner(reason)
                    }
                    performanceCard
                    stopsSection
                }
            }
        }
        .background(Theme.cream)
        .task {
            await loadDetails()
        }
    }

    // MARK: - Data

    private func loadDetails() async {
        do {
            let response = try await APIClient.shared.getServiceDetails(serviceId: train.serviceId)
            details = response

            var allStops: [Stop] = []

            let isArrival = !response.previousCallingPoints.isEmpty
                && response.subsequentCallingPoints.isEmpty

            if isArrival {
                for (i, cp) in response.previousCallingPoints.enumerated() {
                    let type: StopType = i == 0 ? .origin : Stop(from: cp).type
                    allStops.append(Stop(
                        station: cp.station, time: cp.scheduledTime,
                        platform: cp.platform ?? "—", type: type
                    ))
                }
                allStops.append(Stop(
                    station: train.destination,
                    time: response.scheduledArrival ?? train.time,
                    platform: response.platform ?? train.platform,
                    type: .destination
                ))
            } else {
                allStops.append(Stop(
                    station: train.origin,
                    time: response.scheduledDeparture ?? train.time,
                    platform: response.platform ?? train.platform,
                    type: .origin
                ))
                for cp in response.subsequentCallingPoints {
                    allStops.append(Stop(from: cp))
                }
                if allStops.count > 1 {
                    let last = allStops[allStops.count - 1]
                    allStops[allStops.count - 1] = Stop(
                        station: last.station, time: last.time,
                        platform: last.platform, type: .destination
                    )
                }
            }

            stops = allStops
            let firstTime = allStops.first?.time ?? ""
            let lastTime = allStops.last?.time ?? ""
            duration = computeDuration(from: firstTime, to: lastTime)
        } catch {
            stops = []
            loadError = (error as? APIError)?.errorDescription ?? "Could not load service details"
        }

        if loadError == nil,
           let dCrs = details?.destination?.crs, !dCrs.isEmpty,
           let oCrs = details?.origin?.crs, !oCrs.isEmpty {
            reliability = try? await APIClient.shared.getReliability(origin: oCrs, destination: dCrs, days: 5)
        }

        isLoading = false
    }

    private func computeDuration(from start: String, to end: String) -> String {
        let parts1 = start.split(separator: ":")
        let parts2 = end.split(separator: ":")
        guard parts1.count == 2, parts2.count == 2,
              let h1 = Int(parts1[0]), let m1 = Int(parts1[1]),
              let h2 = Int(parts2[0]), let m2 = Int(parts2[1]) else { return "" }
        var diff = (h2 * 60 + m2) - (h1 * 60 + m1)
        if diff < 0 { diff += 24 * 60 }
        let hours = diff / 60
        let mins = diff % 60
        if hours == 0 { return "\(mins)m" }
        return "\(hours)h \(String(format: "%02d", mins))m"
    }

    // MARK: - Loading

    private var loadingSection: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(Theme.ink)
            Text("Loading journey details...")
                .font(.ui(13))
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 18)
        .padding(.top, 18)
    }

    // MARK: - Error

    private func errorSection(_ error: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 22))
                .foregroundStyle(Theme.inkMute)
            Text("Couldn't load details")
                .font(.display(18))
            Text(error)
                .font(.ui(11))
                .foregroundStyle(Theme.inkMute)
            Button {
                isLoading = true
                loadError = nil
                Task { await loadDetails() }
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
        .padding(.horizontal, 18)
        .padding(.top, 18)
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 0) {
            heroTopBar
            heroBody
            heroOperator
        }
        .padding(.horizontal, 18)
        .padding(.top, 62)
        .padding(.bottom, 22)
        .background(heroBg)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0, bottomLeadingRadius: 26,
                bottomTrailingRadius: 26, topTrailingRadius: 0
            )
        )
        .foregroundStyle(Theme.ink)
    }

    private var heroTopBar: some View {
        HStack {
            IconButton(systemName: "chevron.left", size: 14, heroStyle: true, action: onBack)

            Spacer()

            trackPill

            Spacer()

            HStack(spacing: 8) {
                IconButton(systemName: "square.and.arrow.up", size: 13, heroStyle: true)
                IconButton(systemName: "star", size: 13, heroStyle: true)
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var trackPill: some View {
        switch train.status {
        case .cancelled:
            HStack(spacing: 8) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.trackPillCancelledFg)
                    .frame(width: 20, height: 20)
                    .background(Theme.trackPillCancelledFg.opacity(0.18))
                    .clipShape(Circle())
                Text("Cancelled")
                    .font(.ui(11, weight: .semibold))
                    .tracking(0.2)
            }
            .padding(.horizontal, 12)
            .padding(.leading, -4)
            .padding(.vertical, 6)
            .foregroundStyle(Theme.trackPillCancelledFg)
            .background(Theme.trackPillCancelledBg)
            .clipShape(Capsule())

        case .delayed:
            HStack(spacing: 8) {
                LiveDotColored(color: Theme.trackPillDelayedFg)
                Text("Delayed")
                    .font(.ui(11, weight: .semibold))
                Text(train.statusNote)
                    .font(.mono(10, weight: .medium))
                    .tracking(0.4)
                    .foregroundStyle(Theme.trackPillDelayedFg.opacity(0.7))
                    .padding(.leading, 4)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Theme.trackPillDelayedFg.opacity(0.25))
                            .frame(width: 1)
                    }
            }
            .padding(.horizontal, 12)
            .padding(.leading, -4)
            .padding(.vertical, 6)
            .foregroundStyle(Theme.trackPillDelayedFg)
            .background(Theme.trackPillDelayedBg)
            .clipShape(Capsule())

        case .onTime:
            HStack(spacing: 8) {
                LiveDotColored(color: accent)
                Text("Track live")
                    .font(.ui(11, weight: .semibold))
                Text(train.statusNote)
                    .font(.mono(10, weight: .medium))
                    .tracking(0.4)
                    .foregroundStyle(accent.opacity(0.7))
                    .padding(.leading, 4)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(accent.opacity(0.25))
                            .frame(width: 1)
                    }
            }
            .padding(.horizontal, 12)
            .padding(.leading, -4)
            .padding(.vertical, 6)
            .foregroundStyle(accent)
            .background(Theme.ink)
            .clipShape(Capsule())
        }
    }

    private var heroBody: some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(train.time)
                    .font(.mono(14, weight: .medium))
                    .tracking(0.3)
                    .foregroundStyle(Theme.inkSoft)
                Text(train.origin)
                    .font(.display(22))
                    .tracking(-0.2)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Platform \(departPlatform)")
                    .font(.mono(10, weight: .medium))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.inkSoft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 2) {
                if !duration.isEmpty {
                    Text(duration)
                        .font(.mono(11, weight: .semibold))
                        .tracking(0.4)
                }
                connectorLine
                if stops.count > 1 {
                    Text("\(stops.count - 1) STOPS")
                        .font(.mono(9))
                        .tracking(1.3)
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            .frame(minWidth: 110)

            VStack(alignment: .trailing, spacing: 2) {
                if let lastTime = stops.last?.time, !lastTime.isEmpty {
                    Text(lastTime)
                        .font(.mono(14, weight: .medium))
                        .tracking(0.3)
                        .foregroundStyle(Theme.inkSoft)
                }
                Text(train.destination)
                    .font(.display(22))
                    .tracking(-0.2)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                if let lastPlat = stops.last?.platform, lastPlat != "—" {
                    Text("Platform \(lastPlat)")
                        .font(.mono(10, weight: .medium))
                        .tracking(0.5)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.top, 14)
    }

    private var connectorLine: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(Theme.ink)
                .frame(width: 6, height: 6)
            StrokeLine()
                .stroke(Theme.ink, style: StrokeStyle(lineWidth: 1.2, dash: [2, 3]))
                .frame(height: 1.2)
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Theme.ink)
        }
        .frame(height: 14)
        .padding(.vertical, 2)
    }

    private var heroOperator: some View {
        HStack(spacing: 10) {
            Text(train.operatorCode)
                .font(.mono(11, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Theme.ink)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(train.operator)
                    .font(.ui(13, weight: .semibold))
                Text("Service \(train.serviceId.prefix(8).uppercased())")
                    .font(.mono(10, weight: .medium))
                    .tracking(0.3)
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.ink.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.top, 18)
    }

    // MARK: - Facts

    private var factsRow: some View {
        HStack(spacing: 8) {
            FactTile(icon: "train.side.front.car", value: train.carriages.map { "\($0)" } ?? "—", label: "Carriages")
            FactTile(icon: "clock", value: duration.isEmpty ? "—" : duration, label: "Journey")
            FactTile(icon: "mappin.and.ellipse", value: stops.isEmpty ? "—" : "\(stops.count - 1)", label: "Stops")
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
    }

    // MARK: - Reason Banner

    private func reasonBanner(_ reason: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(train.status == .cancelled ? Theme.cancelledText : Theme.delayedText)
            Text(reason)
                .font(.ui(12))
                .foregroundStyle(Theme.ink)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(train.status == .cancelled ? Theme.bad.opacity(0.3) : Theme.warn.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }

    // MARK: - Performance

    private var performanceCard: some View {
        Group {
            if let stats = reliability {
                let onTimePct = Int(stats.onTimePercent)
                let tone: String = onTimePct >= 80 ? "good" : onTimePct >= 60 ? "ok" : "bad"

                VStack(alignment: .leading, spacing: 10) {
                    Text("ON-TIME PERFORMANCE")
                        .font(.mono(9, weight: .semibold))
                        .tracking(1.3)
                        .foregroundStyle(Theme.inkMute)

                    Text("On time \(Text("\(onTimePct)% of services").font(.ui(17, weight: .semibold)).foregroundColor(tone == "good" ? Theme.perfGood : tone == "bad" ? Theme.perfBad : Theme.ink)) \(Text("over \(stats.period)").font(.mono(14, weight: .medium)).foregroundColor(Theme.inkSoft))")
                        .font(.ui(17))

                    HStack(spacing: 16) {
                        StatBadge(value: "\(stats.onTimeServices)", label: "On time", color: Theme.perfGood)
                        StatBadge(value: "\(stats.delayedServices)", label: "Delayed", color: Theme.delayedText)
                        StatBadge(value: "\(stats.cancelledServices)", label: "Cancelled", color: Theme.cancelledText)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 18)
                .padding(.top, 14)
            }
        }
    }

    // MARK: - Stops

    private var stopsSection: some View {
        Group {
            if !stops.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Calling at")
                            .font(.display(26, weight: .medium))
                            .tracking(-0.9)
                        Spacer()
                        Text("\(stops.count - 1) stops")
                            .font(.mono(11, weight: .medium))
                            .foregroundStyle(Theme.inkMute)
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                            StopRow(
                                stop: stop,
                                isFirst: index == 0,
                                isLast: index == stops.count - 1,
                                accent: accent
                            )
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                }
                .padding(.horizontal, 18)
                .padding(.top, 22)
                .padding(.bottom, 48)
            }
        }
    }
}

// MARK: - Sub-components

private struct FactTile: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(Theme.ink)
            Text(value)
                .font(.display(15))
                .lineLimit(1)
            Text(label.uppercased())
                .font(.mono(9))
                .tracking(0.7)
                .foregroundStyle(Theme.inkMute)
        }
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .padding(.bottom, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct StatBadge: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.mono(16, weight: .semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.mono(9))
                .tracking(0.5)
                .foregroundStyle(Theme.inkMute)
        }
    }
}

private struct LiveDotColored: View {
    let color: Color
    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.18))
                .frame(width: 20, height: 20)
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
        }
    }
}

private struct StopRow: View {
    let stop: Stop
    let isFirst: Bool
    let isLast: Bool
    let accent: Color

    private var isEndpoint: Bool {
        stop.type == .origin || stop.type == .destination
    }

    var body: some View {
        HStack(spacing: 12) {
            timeline
            content
            Spacer()
            timeColumn
        }
        .padding(.vertical, 10)
    }

    private var timeline: some View {
        ZStack {
            if !isFirst {
                VStack {
                    Rectangle()
                        .fill(Theme.lineStrong)
                        .frame(width: 2)
                    Spacer()
                }
                .frame(height: 20)
                .offset(y: -15)
            }

            if !isLast {
                VStack {
                    Spacer()
                    Rectangle()
                        .fill(Theme.lineStrong)
                        .frame(width: 2)
                }
                .frame(height: 20)
                .offset(y: 15)
            }

            if isEndpoint {
                ZStack {
                    Circle()
                        .fill(accent)
                        .stroke(Theme.ink, lineWidth: 2)
                        .frame(width: 14, height: 14)
                    Circle()
                        .fill(Theme.ink)
                        .frame(width: 5, height: 5)
                }
            } else {
                Circle()
                    .fill(Theme.cream)
                    .stroke(Theme.inkMute, lineWidth: 1.5)
                    .frame(width: 10, height: 10)
            }
        }
        .frame(width: 22, height: 30)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(stop.station)
                .font(isEndpoint ? .display(17) : .ui(14, weight: .medium))
                .tracking(isEndpoint ? -0.1 : -0.05)
                .foregroundStyle(Theme.ink)

            HStack(spacing: 6) {
                if stop.type == .origin {
                    CodeTag(text: "DEPART")
                }
                if stop.type == .destination {
                    CodeTag(text: "ARRIVE", bg: accent, fg: Theme.ink)
                }
                if stop.platform != "—" {
                    Text("Plat. \(Text(stop.platform).bold())")
                }
            }
            .font(.mono(10, weight: .medium))
            .tracking(0.4)
            .foregroundStyle(Theme.inkMute)
        }
    }

    private var timeColumn: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(stop.time)
                .font(.mono(14, weight: .medium))
                .tracking(-0.1)
                .foregroundStyle(Theme.ink)
            if !isEndpoint {
                Text(stopStatusLabel)
                    .font(.mono(9, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(stopStatusColor)
            }
        }
    }

    private var stopStatusLabel: String {
        switch stop.type {
        case .origin, .destination: return ""
        case .major: return "DELAYED"
        case .stop: return "ON TIME"
        }
    }

    private var stopStatusColor: Color {
        stop.type == .major ? Theme.delayedText : Theme.onTimeSub
    }
}

private struct StrokeLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}
