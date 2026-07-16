import SwiftUI

/// Modal explainer presented from the BoardScreen info button. Each topic is
/// a collapsible row so users can scan headings and expand only what they
/// care about.
struct FAQSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var expanded: Set<String> = []

    private struct Entry: Identifiable {
        let id: String
        let icon: String
        let title: String
        let body: String
    }

    private let entries: [Entry] = [
        Entry(
            id: "track",
            icon: "dot.radiowaves.up.forward",
            title: "Tracking a train",
            body: "Tap any service on the board to open its full journey. On the journey screen, hit Track live, choose where you're getting off, and updates follow the train between stops — including an alert when your stop is next. If you've allowed Live Activities, the tracking ribbon also appears on the Lock Screen and Dynamic Island, so you can check progress without opening the app."
        ),
        Entry(
            id: "fav",
            icon: "star",
            title: "Favourite stations",
            body: "Tap the star next to any station in search results, the Recent list, or the Nearby list to save it. Favourites get their own section on the home screen, and they power the Fastest from card on every departure board."
        ),
        Entry(
            id: "fastest",
            icon: "bolt.horizontal",
            title: "Fastest to your favourites",
            body: "On any departure board, the Fastest from {station} strip shows the next service arriving soonest at each of your favourite destinations. The journey duration printed on each tile is the reason that train was picked — it's the quickest route to that destination within the next two hours. Tap a tile to jump straight into the journey."
        ),
        Entry(
            id: "platform",
            icon: "tram",
            title: "Predicted platforms",
            body: "Network Rail doesn't always confirm a platform until shortly before departure. When that's the case, we predict the most likely platform based on historical patterns for the same service. Predictions are marked with a dashed border and a PREDICTED label on the platform ribbon. Once the official platform is announced, the prediction is replaced automatically."
        ),
        Entry(
            id: "earlier",
            icon: "clock.arrow.circlepath",
            title: "Trains that have already left",
            body: "The board shows services from the current time onwards by default. Tap Show earlier trains at the top of the list to step back 30 minutes at a time — useful if you've just missed a connection and want to see what departed recently. The active offset is shown next to the clock at the top of the filters row."
        ),
        Entry(
            id: "tally",
            icon: "checkmark.circle",
            title: "Service status tally",
            body: "Underneath the station name, you'll see a tally of how many of the listed services are on time, delayed or cancelled. It reflects every service currently on the board, regardless of the active filter, so it gives a quick read on how the station is performing right now."
        ),
        Entry(
            id: "disruption",
            icon: "exclamationmark.triangle",
            title: "Disruption notices",
            body: "When National Rail publishes an alert affecting services at the station you're viewing, it appears as an amber banner inside the station card. We strip the HTML and inline links so it's readable at a glance — you'll see all active notices listed there."
        ),
        Entry(
            id: "filter",
            icon: "line.3.horizontal.decrease",
            title: "Filter by destination",
            body: "Tap the filter button to narrow the board to services calling at a specific station. A small dot on the icon indicates the filter is active. To clear it, tap the destination chip that appears under the station card. Filtering also saves the route to Your journeys on the home screen."
        ),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    header
                    ForEach(entries) { entry in
                        row(entry)
                    }
                    footer
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
            .background(Theme.cream)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 32, height: 32)
                            .background(Theme.ink.opacity(0.08))
                            .clipShape(Circle())
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("HOW TO USE")
                        .font(.mono(11, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(Theme.ink)
                }
            }
            .toolbarBackground(Theme.cream, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Trainview")
                .font(.display(28))
                .tracking(-0.4)
                .foregroundStyle(Theme.ink)
            Text("A quick tour of features you might miss.")
                .font(.ui(13))
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }

    private func row(_ entry: Entry) -> some View {
        let isOpen = expanded.contains(entry.id)
        return Button {
            withAnimation(.easeOut(duration: 0.22)) {
                if isOpen { expanded.remove(entry.id) }
                else { expanded.insert(entry.id) }
            }
        } label: {
            VStack(alignment: .leading, spacing: isOpen ? 12 : 0) {
                HStack(spacing: 12) {
                    Image(systemName: entry.icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 32, height: 32)
                        .background(Theme.ink.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Text(entry.title)
                        .font(.display(16))
                        .tracking(-0.1)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.inkMute)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                if isOpen {
                    preview(for: entry.id)
                    Text(entry.body)
                        .font(.ui(13))
                        .foregroundStyle(Theme.inkSoft)
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 4)
                }
            }
            .padding(14)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Visual previews of the controls referenced in each topic

    @ViewBuilder
    private func preview(for id: String) -> some View {
        switch id {
        case "track":      trackPreview
        case "fav":        favouritePreview
        case "fastest":    fastestPreview
        case "platform":   platformPreview
        case "earlier":    earlierPreview
        case "tally":      tallyPreview
        case "disruption": disruptionPreview
        case "filter":     filterPreview
        default:           EmptyView()
        }
    }

    private var trackPreview: some View {
        HStack(spacing: 6) {
            Image(systemName: "dot.radiowaves.up.forward")
                .font(.system(size: 11, weight: .semibold))
            Text("Track live")
                .font(.ui(12, weight: .semibold))
                .tracking(0.2)
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.accent)
        .clipShape(Capsule())
        .faqPreviewContainer()
    }

    private var favouritePreview: some View {
        HStack(spacing: 22) {
            VStack(spacing: 5) {
                Image(systemName: "star")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.inkMute)
                    .frame(width: 34, height: 34)
                    .background(Theme.ink.opacity(0.04))
                    .clipShape(Circle())
                Text("not saved")
                    .font(.mono(9, weight: .medium))
                    .tracking(0.7)
                    .foregroundStyle(Theme.inkMute)
            }
            Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.inkMute)
            VStack(spacing: 5) {
                Image(systemName: "star.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 34, height: 34)
                    .background(Theme.ink.opacity(0.04))
                    .clipShape(Circle())
                Text("saved")
                    .font(.mono(9, weight: .medium))
                    .tracking(0.7)
                    .foregroundStyle(Theme.inkMute)
            }
        }
        .faqPreviewContainer()
    }

    private var fastestPreview: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Edinburgh")
                .font(.display(15))
                .tracking(-0.1)
                .foregroundStyle(Theme.ink)
            HStack(spacing: 5) {
                Text("19:30")
                    .font(.mono(15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.inkMute)
                Text("22:30")
                    .font(.mono(15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
            HStack(spacing: 4) {
                Image(systemName: "clock").font(.system(size: 9))
                Text("3h 0m journey")
                    .font(.mono(10, weight: .medium))
            }
            .foregroundStyle(Theme.inkMute)
        }
        .padding(12)
        .frame(width: 170, alignment: .topLeading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.accent.opacity(0.45), lineWidth: 1)
        )
        .faqPreviewContainer()
    }

    private var platformPreview: some View {
        HStack(spacing: 18) {
            ribbonChip(label: "PLATFORM", number: "3", predicted: false)
            ribbonChip(label: "PREDICTED", number: "7", predicted: true)
        }
        .faqPreviewContainer()
    }

    private func ribbonChip(label: String, number: String, predicted: Bool) -> some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.mono(predicted ? 8 : 9, weight: .medium))
                .tracking(predicted ? 1.4 : 1.8)
                .rotationEffect(.degrees(-90))
                .fixedSize()
                .frame(maxHeight: .infinity)
            Text(number)
                .font(.display(20))
                .tracking(-0.3)
        }
        .foregroundStyle(predicted ? Theme.ink.opacity(0.7) : Theme.ink)
        .frame(width: 36, height: 78)
        .padding(.vertical, 6)
        .background(predicted ? Theme.accent.opacity(0.45) : Theme.accent)
        .overlay(alignment: .leading) {
            if predicted {
                Rectangle()
                    .fill(.clear)
                    .frame(width: 2)
                    .overlay(
                        Line()
                            .stroke(Theme.ink.opacity(0.25),
                                    style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                    )
            }
        }
    }

    private var earlierPreview: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up")
                .font(.system(size: 11, weight: .semibold))
            Text("Show earlier trains")
                .font(.ui(12, weight: .semibold))
                .tracking(0.2)
            Spacer()
            Image(systemName: "chevron.up")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.inkMute)
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 260)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.line, lineWidth: 1)
        )
        .faqPreviewContainer()
    }

    private var tallyPreview: some View {
        HStack(spacing: 12) {
            tallyChip(count: 12, label: "on time", color: Theme.perfGood)
            tallyChip(count: 3, label: "delayed", color: Theme.delayedText)
            tallyChip(count: 1, label: "cancelled", color: Theme.cancelledText)
        }
        .faqPreviewContainer()
    }

    private func tallyChip(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(count)")
                .font(.mono(12, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text(label)
                .font(.ui(11))
                .foregroundStyle(Theme.inkSoft)
        }
    }

    private var disruptionPreview: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.delayedText)
                .padding(.top, 1)
            Text("Trains may be delayed by up to 25 minutes…")
                .font(.ui(12))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
        }
        .padding(10)
        .frame(maxWidth: 280, alignment: .leading)
        .background(Theme.warn.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .faqPreviewContainer()
    }

    private var filterPreview: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.ink)
                .frame(width: 38, height: 38)
                .background(Theme.ink.opacity(0.08))
                .clipShape(Circle())
            Circle()
                .fill(Color(hex: 0xC94A2E))
                .frame(width: 7, height: 7)
                .offset(x: -4, y: 4)
        }
        .faqPreviewContainer()
    }

    private var footer: some View {
        Text("Live departure data via OpenLDBWS")
            .font(.mono(10, weight: .medium))
            .tracking(0.5)
            .foregroundStyle(Theme.inkMute)
            .frame(maxWidth: .infinity)
            .padding(.top, 18)
    }
}

// MARK: - Helpers

private extension View {
    /// Subtle inset card used to host an inline UI sample in the FAQ.
    func faqPreviewContainer() -> some View {
        self
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 12)
            .background(Theme.cream)
            .clipShape(RoundedRectangle(cornerRadius: 10))
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
