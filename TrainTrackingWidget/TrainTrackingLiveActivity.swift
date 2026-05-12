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
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.operatorCode)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(0.5)
                        Text(context.attributes.origin)
                            .font(.system(size: 11))
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 4) {
                            if let eta = context.state.destinationArrivalDate {
                                Text(eta, style: .time)
                                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                                    .monospacedDigit()
                            } else {
                                Text(context.attributes.scheduledArrival)
                                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                            }
                            if let d = context.state.destinationDelayMinutes, d != 0 {
                                WidgetDelayChip(minutes: d)
                            }
                        }
                        Text(context.attributes.destination)
                            .font(.system(size: 11))
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        progressBar(for: context.state)
                        HStack {
                            HStack(spacing: 5) {
                                Text("Next:")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                Text(context.state.nextStopName)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                Text(context.state.nextStopExpectedTime)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                if let d = context.state.nextStopDelayMinutes, d != 0 {
                                    WidgetDelayChip(minutes: d)
                                }
                            }
                            Spacer()
                            countdownLabel(for: context.state)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "tram.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(statusColor(context.state.status))
            } compactTrailing: {
                compactCountdown(for: context.state)
            } minimal: {
                Image(systemName: "tram.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(statusColor(context.state.status))
            }
        }
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<TrainTrackingAttributes>) -> some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
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
                }
                Spacer()
                statusBadge(context.state.status)
            }

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(context.attributes.scheduledDeparture)
                        .font(.system(size: 20, weight: .medium, design: .monospaced))
                    Text(context.attributes.origin)
                        .font(.system(size: 12))
                        .lineLimit(1)
                }
                Spacer()
                VStack(spacing: 2) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("\(context.attributes.totalStops) stops")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    HStack(spacing: 4) {
                        if let eta = context.state.destinationArrivalDate {
                            Text(eta, style: .time)
                                .font(.system(size: 20, weight: .medium, design: .monospaced))
                        } else {
                            Text(context.attributes.scheduledArrival)
                                .font(.system(size: 20, weight: .medium, design: .monospaced))
                        }
                        if let d = context.state.destinationDelayMinutes, d != 0 {
                            WidgetDelayChip(minutes: d)
                        }
                    }
                    Text(context.attributes.destination)
                        .font(.system(size: 12))
                        .lineLimit(1)
                }
            }

            VStack(spacing: 6) {
                progressBar(for: context.state)
                HStack(alignment: .center) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(context.state.nextStopName)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Text(context.state.nextStopExpectedTime)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        if let d = context.state.nextStopDelayMinutes, d != 0 {
                            WidgetDelayChip(minutes: d)
                        }
                        if let p = context.state.nextStopPlatform {
                            Text("Plat \(p)")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.white.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    Spacer()
                    countdownLabel(for: context.state)
                }
            }
        }
        .padding(16)
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
