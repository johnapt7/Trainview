import ActivityKit
import WidgetKit
import SwiftUI

struct TrainTrackingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrainTrackingAttributes.self) { context in
            lockScreenView(context: context)
                .widgetURL(URL(string: "liverail://journey/\(context.attributes.serviceId)")!)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.operatorCode)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    statusDot(context.state.status)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    let atTerminus = context.state.progressFraction >= 1.0
                    VStack(spacing: 8) {
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(context.state.hasDeparted ? "FROM" : "DEPARTING")
                                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                    .tracking(0.8)
                                    .foregroundStyle(.secondary)
                                Text(context.state.currentStopName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(atTerminus ? "ARRIVED" : "NEXT")
                                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                    .tracking(0.8)
                                    .foregroundStyle(.secondary)
                                Text(context.state.nextStopName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .lineLimit(1)
                            }
                        }

                        progressBar(for: context.state)

                        HStack {
                            if atTerminus {
                                Text("Arrived")
                                    .font(.system(size: 11, weight: .semibold))
                            } else if !context.state.hasDeparted {
                                Text(context.state.isBoarding
                                    ? "Boarding · \(context.attributes.scheduledDeparture)"
                                    : "Departs \(context.attributes.scheduledDeparture)")
                                    .font(.system(size: 11, weight: .semibold))
                            } else {
                                countdownLabel(for: context.state)
                            }
                            Spacer(minLength: 8)
                            HStack(spacing: 3) {
                                if let d = context.state.destinationDelayMinutes, d != 0 {
                                    WidgetDelayChip(minutes: d)
                                }
                                if let eta = context.state.destinationArrivalDate {
                                    Text(eta, style: .time)
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .monospacedDigit()
                                } else {
                                    Text(context.attributes.scheduledArrival)
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                }
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "tram.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(statusColor(context.state.status))
            } compactTrailing: {
                if context.state.hasDeparted {
                    compactCountdown(for: context.state)
                } else {
                    Text(context.attributes.scheduledDeparture)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                }
            } minimal: {
                Image(systemName: "tram.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(statusColor(context.state.status))
            }
        }
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<TrainTrackingAttributes>) -> some View {
        let atTerminus = context.state.progressFraction >= 1.0
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Text(context.attributes.operatorCode)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    Text(context.attributes.operatorName)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                statusBadge(context.state.status)
            }

            HStack(alignment: .top, spacing: 12) {
                stopColumn(
                    label: context.state.hasDeparted ? "DEPARTED FROM" : "DEPARTING FROM",
                    name: context.state.currentStopName,
                    time: nil,
                    platform: context.state.hasDeparted ? nil : context.state.platform,
                    delayMinutes: nil,
                    trailing: false
                )
                stopColumn(
                    label: atTerminus ? "ARRIVED AT" : "NEXT STOP",
                    name: context.state.nextStopName,
                    time: context.state.nextStopExpectedTime,
                    platform: context.state.nextStopPlatform,
                    delayMinutes: context.state.nextStopDelayMinutes,
                    trailing: true
                )
            }

            progressBar(for: context.state)

            sentenceFooter(context: context, atTerminus: atTerminus)
        }
        .padding(16)
    }

    @ViewBuilder
    private func stopColumn(label: String, name: String, time: String?, platform: String?, delayMinutes: Int?, trailing: Bool) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(.secondary)
            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            HStack(spacing: 4) {
                if let time, !time.isEmpty {
                    Text(time)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                if let d = delayMinutes, d != 0 {
                    WidgetDelayChip(minutes: d)
                }
                if let p = platform, !p.isEmpty, p != "—" {
                    Text("Plat \(p)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
    }

    @ViewBuilder
    private func sentenceFooter(context: ActivityViewContext<TrainTrackingAttributes>, atTerminus: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if atTerminus {
                Text("Arrived at \(context.state.nextStopName)")
                    .font(.system(size: 14, weight: .semibold))
            } else if !context.state.hasDeparted {
                Text(context.state.isBoarding
                    ? "Boarding · departs \(context.attributes.scheduledDeparture)"
                    : "Departs \(context.attributes.scheduledDeparture)")
                    .font(.system(size: 14, weight: .semibold))
            } else if let arrival = context.state.nextStopArrivalDate {
                let remaining = arrival.timeIntervalSinceNow
                if remaining < 30 && remaining > -120 {
                    Text("Approaching \(context.state.nextStopName)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(statusColor(context.state.status))
                } else if remaining > 0 {
                    Text("Arrives at \(context.state.nextStopName) in \(formatRemaining(remaining))")
                        .font(.system(size: 14, weight: .semibold))
                } else {
                    Text("Due now at \(context.state.nextStopName)")
                        .font(.system(size: 14, weight: .semibold))
                }
            }

            if !atTerminus {
                HStack(spacing: 4) {
                    if let d = context.state.destinationDelayMinutes, d > 0 {
                        Text("+\(d) min late")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                    Text("Due \(context.attributes.destination)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    if let eta = context.state.destinationArrivalDate {
                        Text(eta, style: .time)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(context.attributes.scheduledArrival)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func progressBar(for state: TrainTrackingAttributes.ContentState) -> some View {
        let tint = statusColor(state.status)
        if let prev = state.previousStopDepartureDate,
           let next = state.nextStopArrivalDate,
           prev < next {
            ProgressView(timerInterval: prev...next, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(tint)
            .progressViewStyle(.linear)
        } else {
            ProgressView(value: max(0, min(state.progressFraction, 1)))
                .tint(tint)
        }
    }

    @ViewBuilder
    private func countdownLabel(for state: TrainTrackingAttributes.ContentState) -> some View {
        if let arrival = state.nextStopArrivalDate {
            let secondsUntil = arrival.timeIntervalSinceNow
            if secondsUntil < 30 && secondsUntil > -120 {
                Text("Approaching")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(statusColor(state.status))
            } else if secondsUntil > 0 {
                Text(formatRemaining(secondsUntil))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
            } else {
                Text("Now")
                    .font(.system(size: 11, weight: .semibold))
            }
        } else {
            Text(state.nextStopExpectedTime)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
    }

    @ViewBuilder
    private func compactCountdown(for state: TrainTrackingAttributes.ContentState) -> some View {
        if let arrival = state.nextStopArrivalDate {
            let secondsUntil = arrival.timeIntervalSinceNow
            if secondsUntil > 0 && secondsUntil < 60 {
                // Last minute: tight MM:SS countdown
                Text(timerInterval: Date()...arrival, countsDown: true, showsHours: false)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .monospacedDigit()
            } else if secondsUntil > 0 {
                // Otherwise: just minute count, no live tick (saves width)
                let totalMinutes = Int((secondsUntil + 30) / 60)
                let hours = totalMinutes / 60
                let mins = totalMinutes % 60
                if hours > 0 {
                    Text("\(hours)h\(mins > 0 ? "\(mins)" : "")")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                } else {
                    Text("\(mins)m")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                }
            } else {
                Text("now")
                    .font(.system(size: 11, weight: .semibold))
            }
        } else {
            Text(state.nextStopExpectedTime)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
        }
    }

    private func formatRemaining(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int((seconds + 30) / 60)
        if totalMinutes < 1 { return "<1 min" }
        let hours = totalMinutes / 60
        let mins = totalMinutes % 60
        if hours == 0 { return "\(mins) min" }
        if mins == 0 { return "\(hours)h" }
        return "\(hours)h \(mins)m"
    }

    @ViewBuilder
    private func statusBadge(_ status: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor(status))
                .frame(width: 6, height: 6)
            Text(status == "on-time" ? "On time" : status == "delayed" ? "Delayed" : "Cancelled")
                .font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func statusDot(_ status: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor(status))
                .frame(width: 6, height: 6)
            Text(status == "on-time" ? "On time" : status == "delayed" ? "Delayed" : "Cancelled")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "delayed": return .orange
        case "cancelled": return .red
        default: return .green
        }
    }
}

private struct WidgetDelayChip: View {
    let minutes: Int

    private var color: Color {
        minutes > 0 ? .orange : .green
    }

    var body: some View {
        Text(minutes > 0 ? "+\(minutes)" : "\(minutes)")
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
