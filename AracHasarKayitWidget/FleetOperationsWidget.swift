import WidgetKit
import SwiftUI

// MARK: - Must match `FleetWidgetAppGroup` in main app (AracHasarKayit/WidgetShared/FleetWidgetSnapshot.swift)
private enum WidgetGroup {
    static let suiteName = "group.com.greenmotionapp.fleetwidget"
    static let snapshotKey = "fleetWidgetSnapshot.v1"
}

/// Decodes the same JSON shape as `FleetWidgetSnapshot` in the main target.
struct SnapshotPayload: Codable {
    var updatedAt: Date
    var returnsTodayCount: Int
    var checkoutsTodayCount: Int
    var damagesTodayCount: Int
    var pendingReturnsCount: Int
    var operationsTabAvailable: Bool
}

private func loadSnapshot() -> SnapshotPayload? {
    guard let data = UserDefaults(suiteName: WidgetGroup.suiteName)?.data(forKey: WidgetGroup.snapshotKey) else {
        return nil
    }
    return try? JSONDecoder().decode(SnapshotPayload.self, from: data)
}

struct FleetOperationsEntry: TimelineEntry {
    let date: Date
    let snapshot: SnapshotPayload?
}

struct FleetOperationsProvider: TimelineProvider {
    func placeholder(in context: Context) -> FleetOperationsEntry {
        FleetOperationsEntry(
            date: Date(),
            snapshot: SnapshotPayload(
                updatedAt: Date(),
                returnsTodayCount: 4,
                checkoutsTodayCount: 2,
                damagesTodayCount: 1,
                pendingReturnsCount: 1,
                operationsTabAvailable: true
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (FleetOperationsEntry) -> Void) {
        completion(FleetOperationsEntry(date: Date(), snapshot: loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FleetOperationsEntry>) -> Void) {
        let entry = FleetOperationsEntry(date: Date(), snapshot: loadSnapshot())
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Layout

private struct TodayStatTile: View {
    let title: String
    let value: Int
    let systemImage: String
    let tint: Color
    /// Tighter layout for small widget.
    var isCompact: Bool

    var body: some View {
        let iconSize: CGFloat = isCompact ? 22 : 30
        let valueSize: CGFloat = isCompact ? 24 : 32
        let titleSize: CGFloat = isCompact ? 9 : 11

        VStack(spacing: isCompact ? 3 : 6) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)
            Text("\(value)")
                .font(.system(size: valueSize, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.45)
                .lineLimit(1)
            Text(title)
                .font(.system(size: titleSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct ScanLinkBlock: View {
    var isCompact: Bool

    var body: some View {
        let iconSize: CGFloat = isCompact ? 32 : 42
        let labelSize: CGFloat = isCompact ? 12 : 14

        Link(destination: URL(string: "erpxtm://scan")!) {
            VStack(spacing: isCompact ? 4 : 6) {
                Image(systemName: "viewfinder.rectangular")
                    .font(.system(size: iconSize, weight: .medium))
                Text("Scan")
                    .font(.system(size: labelSize, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, isCompact ? 8 : 10)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.blue, Color.blue.opacity(0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 1)
        }
        .accessibilityLabel(Text("Open plate scan"))
    }
}

struct FleetOperationsWidgetView: View {
    var entry: FleetOperationsProvider.Entry
    @Environment(\.widgetFamily) private var family

    private var snapshot: SnapshotPayload? { entry.snapshot }

    private var isAccessoryFamily: Bool {
        switch family {
        case .accessoryInline, .accessoryRectangular, .accessoryCircular:
            return true
        default:
            return false
        }
    }

    /// Sum of today’s returns + check-outs + damages (lock-screen circular summary).
    private var todayActivityTotal: Int {
        guard let s = snapshot else { return 0 }
        return s.returnsTodayCount + s.checkoutsTodayCount + s.damagesTodayCount
    }

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                mediumLayout
            case .accessoryInline:
                accessoryInlineLayout
            case .accessoryRectangular:
                accessoryRectangularLayout
            case .accessoryCircular:
                accessoryCircularLayout
            default:
                smallLayout
            }
        }
        .padding(.horizontal, isAccessoryFamily ? 0 : 12)
        .padding(.vertical, isAccessoryFamily ? 0 : 10)
        .containerBackground(for: .widget) {
            switch family {
            case .accessoryInline, .accessoryRectangular, .accessoryCircular:
                AccessoryWidgetBackground()
            default:
                ZStack {
                    Color(.secondarySystemGroupedBackground)
                    LinearGradient(
                        colors: [Color.blue.opacity(0.08), Color.clear, Color.orange.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
        }
    }

    private var accessoryInlineLayout: some View {
        let r = snapshot?.returnsTodayCount ?? 0
        let c = snapshot?.checkoutsTodayCount ?? 0
        let d = snapshot?.damagesTodayCount ?? 0
        return Text("R\(r) · C\(c) · D\(d)")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .minimumScaleFactor(0.65)
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var accessoryRectangularLayout: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .foregroundStyle(.blue)
            Text("\(snapshot?.returnsTodayCount ?? 0)")
                .fontWeight(.bold)
            Image(systemName: "car.side.arrowtriangle.up.fill")
                .foregroundStyle(.teal)
            Text("\(snapshot?.checkoutsTodayCount ?? 0)")
                .fontWeight(.bold)
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("\(snapshot?.damagesTodayCount ?? 0)")
                .fontWeight(.bold)
        }
        .font(.system(size: 14, weight: .semibold, design: .rounded))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var accessoryCircularLayout: some View {
        VStack(spacing: 0) {
            Image(systemName: "car.side.fill")
                .font(.system(size: 11, weight: .semibold))
            Text("\(todayActivityTotal)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerRow(compact: true)

            HStack(alignment: .center, spacing: 6) {
                TodayStatTile(
                    title: "Returns",
                    value: snapshot?.returnsTodayCount ?? 0,
                    systemImage: "arrow.uturn.backward.circle.fill",
                    tint: .blue,
                    isCompact: true
                )
                TodayStatTile(
                    title: "Check-outs",
                    value: snapshot?.checkoutsTodayCount ?? 0,
                    systemImage: "car.side.arrowtriangle.up.fill",
                    tint: .teal,
                    isCompact: true
                )
                TodayStatTile(
                    title: "Damages",
                    value: snapshot?.damagesTodayCount ?? 0,
                    systemImage: "exclamationmark.triangle.fill",
                    tint: .orange,
                    isCompact: true
                )
            }
            .frame(maxHeight: .infinity)

            ScanLinkBlock(isCompact: true)
                .frame(height: 64)

            footerRow(compact: true)
        }
    }

    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow(compact: false)

            HStack(alignment: .center, spacing: 10) {
                TodayStatTile(
                    title: "Returns today",
                    value: snapshot?.returnsTodayCount ?? 0,
                    systemImage: "arrow.uturn.backward.circle.fill",
                    tint: .blue,
                    isCompact: false
                )
                TodayStatTile(
                    title: "Check-outs today",
                    value: snapshot?.checkoutsTodayCount ?? 0,
                    systemImage: "car.side.arrowtriangle.up.fill",
                    tint: .teal,
                    isCompact: false
                )
                TodayStatTile(
                    title: "Damages today",
                    value: snapshot?.damagesTodayCount ?? 0,
                    systemImage: "exclamationmark.triangle.fill",
                    tint: .orange,
                    isCompact: false
                )

                ScanLinkBlock(isCompact: false)
                    .frame(width: 88)
            }
            .frame(maxHeight: .infinity)

            footerRow(compact: false)
        }
    }

    private func headerRow(compact: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Today")
                .font(.system(size: compact ? 13 : 15, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Spacer(minLength: 4)
            if let s = snapshot {
                Text(s.updatedAt, style: .time)
                    .font(.system(size: compact ? 10 : 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private func footerRow(compact: Bool) -> some View {
        let font = Font.system(size: compact ? 9 : 10, weight: .semibold, design: .rounded)
        HStack(spacing: 8) {
            if let s = snapshot, s.pendingReturnsCount > 0 {
                Label("\(s.pendingReturnsCount) open returns", systemImage: "clock.fill")
                    .font(font)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            if snapshot?.operationsTabAvailable == true {
                Link(destination: URL(string: "erpxtm://operations")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "rectangle.grid.2x2.fill")
                        Text("Ops")
                    }
                    .font(font)
                    .foregroundStyle(.blue)
                }
            }
        }
    }
}

struct FleetOperationsWidget: Widget {
    let kind: String = "FleetOperationsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FleetOperationsProvider()) { entry in
            FleetOperationsWidgetView(entry: entry)
        }
        .configurationDisplayName("Fleet today")
        .description("Today’s returns, check-outs, and damages — tap Scan to open the camera tab.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryInline,
            .accessoryRectangular,
            .accessoryCircular,
        ])
    }
}
