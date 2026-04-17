import SwiftUI
import UIKit

/// Interactive 2D vehicle condition canvas.
/// All coordinates are in the 626 × 408 reference frame; scaled to display size at runtime.
struct VehicleConditionCanvasView: View {
    /// Already-saved condition-form damage markers to render.
    let conditionDamages: [HasarKaydi]
    /// ID of the currently selected/highlighted region.
    let selectedRegionId: String?
    /// Absolute ref-space X of the draft marker (only rendered when `showDraftMarker` is true).
    let draftRefX: CGFloat
    /// Absolute ref-space Y of the draft marker.
    let draftRefY: CGFloat
    let showDraftMarker: Bool
    let nextMarkerNumber: Int
    let markerScale: CGFloat

    /// Called with absolute ref-space coordinates when the user taps empty canvas.
    let onTap: (CGPoint) -> Void
    /// Called when an existing saved marker is tapped.
    let onMarkerTap: (HasarKaydi) -> Void
    /// Called continuously while the draft marker is being dragged; provides absolute ref-space coords.
    let onDraftDrag: (CGPoint) -> Void

    var body: some View {
        GeometryReader { geo in
            let scale  = geo.size.width / VehicleRef.canvasWidth
            let dispH  = VehicleRef.canvasHeight * scale

            ZStack(alignment: .topLeading) {
                vehicleImage(dispW: geo.size.width, dispH: dispH)
                savedMarkers(scale: scale)
                if showDraftMarker {
                    draftMarkerView(scale: scale)
                }
            }
            .frame(width: geo.size.width, height: dispH)
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { v in
                        // Only treat short-distance releases as taps
                        let dx = v.translation.width, dy = v.translation.height
                        guard dx * dx + dy * dy < 100 else { return }
                        onTap(CGPoint(x: v.location.x / scale, y: v.location.y / scale))
                    }
            )
        }
        .aspectRatio(VehicleRef.aspectRatio, contentMode: .fit)
    }

    // MARK: - Sub-views

    @ViewBuilder
    private func vehicleImage(dispW: CGFloat, dispH: CGFloat) -> some View {
        if let img = UIImage(named: "condition_vehicle_2d") {
            Image(uiImage: img)
                .resizable()
                .frame(width: dispW, height: dispH)
        } else {
            Color(.secondarySystemBackground)
                .frame(width: dispW, height: dispH)
                .overlay(
                    VStack(spacing: 6) {
                        Image(systemName: "car.fill")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("condition_vehicle_2d")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                )
        }
    }

    @ViewBuilder
    private func savedMarkers(scale: CGFloat) -> some View {
        ForEach(conditionDamages) { dmg in
            if let pos = displayPosition(for: dmg, scale: scale) {
                markerBubble(number: dmg.markerNumber ?? 1, isActive: false)
                    .position(x: pos.x, y: pos.y)
                    .onTapGesture { onMarkerTap(dmg) }
            }
        }
    }

    private func draftMarkerView(scale: CGFloat) -> some View {
        markerBubble(number: nextMarkerNumber, isActive: true)
            .position(x: draftRefX * scale, y: draftRefY * scale)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        onDraftDrag(CGPoint(x: v.location.x / scale, y: v.location.y / scale))
                    }
            )
    }

    // MARK: - Helpers

    /// Compute the display-space position (.position uses center) for a saved damage marker.
    private func displayPosition(for damage: HasarKaydi, scale: CGFloat) -> CGPoint? {
        guard
            let blockId = damage.conditionViewBlockId,
            let block   = VehicleViewBlock.block(id: blockId),
            let nx = damage.conditionPointX,
            let ny = damage.conditionPointY
        else { return nil }
        let ref = block.normToRef(CGPoint(x: nx, y: ny))
        return CGPoint(x: ref.x * scale, y: ref.y * scale)
    }

    private func markerBubble(number: Int, isActive: Bool) -> some View {
        let markerSize = max(6, 26 * markerScale)
        return ZStack {
            Circle()
                .fill(isActive ? Color.orange : Color.red)
                .frame(width: markerSize, height: markerSize)
                .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
            Text("\(max(1, number))")
                .font(.system(size: max(5, 11 * markerScale), weight: .bold))
                .foregroundColor(.white)
        }
    }
}
