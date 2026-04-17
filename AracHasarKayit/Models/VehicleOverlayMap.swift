import CoreGraphics
import Foundation

// MARK: - Reference Canvas
/// All pixel coordinates are relative to the 626 × 408 reference image.
enum VehicleRef {
    static let canvasWidth:  CGFloat = 626
    static let canvasHeight: CGFloat = 408
    static var aspectRatio:  CGFloat { canvasWidth / canvasHeight }
}

// MARK: - Region Shape
enum VehicleShapeKind {
    case rect(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat)
    case circle(cx: CGFloat, cy: CGFloat, r: CGFloat)
}

// MARK: - View Block
struct VehicleViewBlock: Identifiable, Equatable {
    let id: String
    let displayName: String
    let refX: CGFloat
    let refY: CGFloat
    let refW: CGFloat
    let refH: CGFloat

    /// Convert absolute ref-space point → normalised (0–1) within this block.
    func refToNorm(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - refX) / refW, y: (p.y - refY) / refH)
    }

    /// Convert normalised (0–1) → absolute ref-space point.
    func normToRef(_ n: CGPoint) -> CGPoint {
        CGPoint(x: refX + n.x * refW, y: refY + n.y * refH)
    }
}

// MARK: - Vehicle Region
struct VehicleRegionDef: Identifiable {
    let id: String
    let displayName: String
    let viewBlockId: String
    let shape: VehicleShapeKind
    var damageTypeHint: String?

    func contains(refX rx: CGFloat, refY ry: CGFloat) -> Bool {
        switch shape {
        case .rect(let x, let y, let w, let h):
            return rx >= x && rx <= x + w && ry >= y && ry <= y + h
        case .circle(let cx, let cy, let r):
            let d2 = (rx - cx) * (rx - cx) + (ry - cy) * (ry - cy)
            return d2 <= r * r
        }
    }

    /// Centre of the region in absolute ref-space.
    var refCenter: CGPoint {
        switch shape {
        case .rect(let x, let y, let w, let h): return CGPoint(x: x + w / 2, y: y + h / 2)
        case .circle(let cx, let cy, _):         return CGPoint(x: cx, y: cy)
        }
    }

    /// Smaller area = higher hit-test priority (inner circles win over outer ones).
    var hitArea: CGFloat {
        switch shape {
        case .rect(_, _, let w, let h): return w * h
        case .circle(_, _, let r):      return .pi * r * r
        }
    }
}

// MARK: - Static View Blocks
extension VehicleViewBlock {
    /// Entire 626×408 reference canvas — free marker placement anywhere on the diagram.
    static let fullCanvas = VehicleViewBlock(
        id: "full_canvas",
        displayName: "Full vehicle map",
        refX: 0,
        refY: 0,
        refW: VehicleRef.canvasWidth,
        refH: VehicleRef.canvasHeight
    )

    static let topSide       = VehicleViewBlock(id: "top_side",       displayName: "Side Profile (Top)",    refX: 130, refY: 18,  refW: 360, refH: 114)
    static let centerTop     = VehicleViewBlock(id: "center_top",     displayName: "Top-Down View",         refX: 130, refY: 132, refW: 365, refH: 144)
    static let bottomSide    = VehicleViewBlock(id: "bottom_side",    displayName: "Side Profile (Bottom)", refX: 131, refY: 276, refW: 359, refH: 114)
    static let leftVertical  = VehicleViewBlock(id: "left_vertical",  displayName: "Front View",            refX: 14,  refY: 130, refW: 115, refH: 149)
    static let rightVertical = VehicleViewBlock(id: "right_vertical", displayName: "Rear View",             refX: 496, refY: 129, refW: 111, refH: 150)

    static let all: [VehicleViewBlock] = [.topSide, .centerTop, .bottomSide, .leftVertical, .rightVertical]

    static func block(id: String) -> VehicleViewBlock? {
        if id == fullCanvas.id { return fullCanvas }
        return all.first(where: { $0.id == id })
    }

    static func block(forRegionId regionId: String) -> VehicleViewBlock? {
        guard let region = VehicleRegionDef.allRegions.first(where: { $0.id == regionId }) else { return nil }
        return block(id: region.viewBlockId)
    }
}

// MARK: - Static Region Definitions
extension VehicleRegionDef {

    // MARK: Center Top-Down View
    private static let _centerTop: [VehicleRegionDef] = [
        .init(id: "ct_front_bumper",        displayName: "Front Bumper",        viewBlockId: "center_top",   shape: .rect(x: 131, y: 171, w: 34,  h: 67)),
        .init(id: "ct_hood",                displayName: "Hood",                viewBlockId: "center_top",   shape: .rect(x: 165, y: 156, w: 64,  h: 97)),
        .init(id: "ct_windshield_front",    displayName: "Front Windshield",    viewBlockId: "center_top",   shape: .rect(x: 229, y: 148, w: 33,  h: 110)),
        .init(id: "ct_roof",                displayName: "Roof",                viewBlockId: "center_top",   shape: .rect(x: 262, y: 138, w: 99,  h: 130)),
        .init(id: "ct_rear_windshield",     displayName: "Rear Windshield",     viewBlockId: "center_top",   shape: .rect(x: 361, y: 148, w: 35,  h: 110)),
        .init(id: "ct_trunk",               displayName: "Trunk",               viewBlockId: "center_top",   shape: .rect(x: 396, y: 156, w: 62,  h: 97)),
        .init(id: "ct_rear_bumper",         displayName: "Rear Bumper",         viewBlockId: "center_top",   shape: .rect(x: 458, y: 171, w: 36,  h: 67)),
        .init(id: "ct_upper_left_side",     displayName: "Left Side Strip",     viewBlockId: "center_top",   shape: .rect(x: 150, y: 132, w: 325, h: 22)),
        .init(id: "ct_lower_right_side",    displayName: "Right Side Strip",    viewBlockId: "center_top",   shape: .rect(x: 150, y: 254, w: 325, h: 22)),
        .init(id: "ct_front_left_quarter",  displayName: "Front Left Quarter",  viewBlockId: "center_top",   shape: .rect(x: 132, y: 145, w: 68,  h: 42)),
        .init(id: "ct_front_right_quarter", displayName: "Front Right Quarter", viewBlockId: "center_top",   shape: .rect(x: 132, y: 221, w: 68,  h: 42)),
        .init(id: "ct_rear_left_quarter",   displayName: "Rear Left Quarter",   viewBlockId: "center_top",   shape: .rect(x: 426, y: 145, w: 68,  h: 42)),
        .init(id: "ct_rear_right_quarter",  displayName: "Rear Right Quarter",  viewBlockId: "center_top",   shape: .rect(x: 426, y: 221, w: 68,  h: 42)),
    ]

    // MARK: Top Side Profile (tires outer → inner for priority)
    private static let _topSide: [VehicleRegionDef] = [
        .init(id: "ts_front_bumper",  displayName: "Front Bumper",  viewBlockId: "top_side", shape: .rect(x: 131, y: 71, w: 34,  h: 24)),
        .init(id: "ts_front_fender",  displayName: "Front Fender",  viewBlockId: "top_side", shape: .rect(x: 165, y: 61, w: 45,  h: 34)),
        .init(id: "ts_front_door",    displayName: "Front Door",    viewBlockId: "top_side", shape: .rect(x: 210, y: 48, w: 75,  h: 46)),
        .init(id: "ts_rear_door",     displayName: "Rear Door",     viewBlockId: "top_side", shape: .rect(x: 285, y: 48, w: 76,  h: 46)),
        .init(id: "ts_rear_fender",   displayName: "Rear Fender",   viewBlockId: "top_side", shape: .rect(x: 361, y: 56, w: 55,  h: 39)),
        .init(id: "ts_rear_bumper",   displayName: "Rear Bumper",   viewBlockId: "top_side", shape: .rect(x: 416, y: 64, w: 74,  h: 31)),
        .init(id: "ts_roof_line",     displayName: "Roof Line",     viewBlockId: "top_side", shape: .rect(x: 214, y: 24, w: 161, h: 24)),
        // Tire (outer radius = 22) — resolved AFTER rim in hit-test due to larger area
        .init(id: "ts_front_tire",    displayName: "Front Tire",    viewBlockId: "top_side", shape: .circle(cx: 203, cy: 90, r: 22), damageTypeHint: "tire_damage"),
        .init(id: "ts_rear_tire",     displayName: "Rear Tire",     viewBlockId: "top_side", shape: .circle(cx: 408, cy: 90, r: 22), damageTypeHint: "tire_damage"),
        // Rim (inner radius = 12) — wins over tire because hitArea is smaller
        .init(id: "ts_front_rim",     displayName: "Front Rim",     viewBlockId: "top_side", shape: .circle(cx: 203, cy: 90, r: 12), damageTypeHint: "rim_damage"),
        .init(id: "ts_rear_rim",      displayName: "Rear Rim",      viewBlockId: "top_side", shape: .circle(cx: 408, cy: 90, r: 12), damageTypeHint: "rim_damage"),
    ]

    // MARK: Bottom Side Profile
    private static let _bottomSide: [VehicleRegionDef] = [
        .init(id: "bs_front_bumper",  displayName: "Front Bumper",  viewBlockId: "bottom_side", shape: .rect(x: 131, y: 302, w: 42,  h: 23)),
        .init(id: "bs_front_fender",  displayName: "Front Fender",  viewBlockId: "bottom_side", shape: .rect(x: 173, y: 293, w: 48,  h: 33)),
        .init(id: "bs_front_door",    displayName: "Front Door",    viewBlockId: "bottom_side", shape: .rect(x: 221, y: 286, w: 73,  h: 42)),
        .init(id: "bs_rear_door",     displayName: "Rear Door",     viewBlockId: "bottom_side", shape: .rect(x: 294, y: 286, w: 75,  h: 42)),
        .init(id: "bs_rear_fender",   displayName: "Rear Fender",   viewBlockId: "bottom_side", shape: .rect(x: 369, y: 292, w: 54,  h: 34)),
        .init(id: "bs_rear_bumper",   displayName: "Rear Bumper",   viewBlockId: "bottom_side", shape: .rect(x: 423, y: 300, w: 67,  h: 27)),
        .init(id: "bs_roof_upper",    displayName: "Upper Body",    viewBlockId: "bottom_side", shape: .rect(x: 214, y: 327, w: 160, h: 27)),
        .init(id: "bs_front_tire",    displayName: "Front Tire",    viewBlockId: "bottom_side", shape: .circle(cx: 203, cy: 294, r: 22), damageTypeHint: "tire_damage"),
        .init(id: "bs_rear_tire",     displayName: "Rear Tire",     viewBlockId: "bottom_side", shape: .circle(cx: 409, cy: 294, r: 22), damageTypeHint: "tire_damage"),
        .init(id: "bs_front_rim",     displayName: "Front Rim",     viewBlockId: "bottom_side", shape: .circle(cx: 203, cy: 294, r: 12), damageTypeHint: "rim_damage"),
        .init(id: "bs_rear_rim",      displayName: "Rear Rim",      viewBlockId: "bottom_side", shape: .circle(cx: 409, cy: 294, r: 12), damageTypeHint: "rim_damage"),
    ]

    // MARK: Left Vertical (Front Face)
    private static let _leftVertical: [VehicleRegionDef] = [
        .init(id: "lv_main_body",    displayName: "Front Face",   viewBlockId: "left_vertical", shape: .rect(x: 27, y: 142, w: 86, h: 124)),
        .init(id: "lv_hood_front",   displayName: "Hood Front",   viewBlockId: "left_vertical", shape: .rect(x: 14, y: 170, w: 26, h: 53)),
        .init(id: "lv_roof",         displayName: "Roof Front",   viewBlockId: "left_vertical", shape: .rect(x: 41, y: 133, w: 51, h: 24)),
        .init(id: "lv_lower_bumper", displayName: "Front Bumper", viewBlockId: "left_vertical", shape: .rect(x: 17, y: 225, w: 96, h: 31)),
    ]

    // MARK: Right Vertical (Rear Face)
    private static let _rightVertical: [VehicleRegionDef] = [
        .init(id: "rv_main_body",    displayName: "Rear Face",    viewBlockId: "right_vertical", shape: .rect(x: 510, y: 141, w: 82, h: 125)),
        .init(id: "rv_trunk_rear",   displayName: "Trunk Rear",   viewBlockId: "right_vertical", shape: .rect(x: 580, y: 171, w: 27, h: 53)),
        .init(id: "rv_roof",         displayName: "Roof Rear",    viewBlockId: "right_vertical", shape: .rect(x: 522, y: 133, w: 50, h: 23)),
        .init(id: "rv_lower_bumper", displayName: "Rear Bumper",  viewBlockId: "right_vertical", shape: .rect(x: 510, y: 224, w: 96, h: 31)),
    ]

    static let allRegions: [VehicleRegionDef] = _centerTop + _topSide + _bottomSide + _leftVertical + _rightVertical

    /// Hit-test at absolute ref-space coordinates. Returns the smallest matching region (rims beat tires, etc.).
    static func hitTest(refX: CGFloat, refY: CGFloat) -> VehicleRegionDef? {
        let candidates = allRegions.filter { $0.contains(refX: refX, refY: refY) }
        return candidates.min(by: { $0.hitArea < $1.hitArea })
    }

    static func region(id: String) -> VehicleRegionDef? {
        allRegions.first(where: { $0.id == id })
    }
}
