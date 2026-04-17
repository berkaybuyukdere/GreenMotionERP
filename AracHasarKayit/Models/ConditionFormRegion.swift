import CoreGraphics
import Foundation

struct ConditionFormRegion: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    var centerPoint: CGPoint {
        CGPoint(x: x + (width / 2.0), y: y + (height / 2.0))
    }

    func contains(normalized point: CGPoint) -> Bool {
        point.x >= x &&
        point.x <= (x + width) &&
        point.y >= y &&
        point.y <= (y + height)
    }
}

extension ConditionFormRegion {
    static let defaultRegions: [ConditionFormRegion] = [
        // Regions aligned to the central top-view car in condition_vehicle_2d image
        ConditionFormRegion(id: "front_bumper", title: "Front Bumper", x: 0.40, y: 0.31, width: 0.20, height: 0.07),
        ConditionFormRegion(id: "hood", title: "Hood", x: 0.34, y: 0.38, width: 0.32, height: 0.09),
        ConditionFormRegion(id: "windshield", title: "Windshield", x: 0.36, y: 0.47, width: 0.28, height: 0.06),
        ConditionFormRegion(id: "roof", title: "Roof", x: 0.33, y: 0.53, width: 0.34, height: 0.14),
        ConditionFormRegion(id: "rear_window", title: "Rear Window", x: 0.36, y: 0.67, width: 0.28, height: 0.06),
        ConditionFormRegion(id: "trunk", title: "Trunk", x: 0.34, y: 0.73, width: 0.32, height: 0.09),
        ConditionFormRegion(id: "rear_bumper", title: "Rear Bumper", x: 0.40, y: 0.82, width: 0.20, height: 0.07),
        ConditionFormRegion(id: "left_front", title: "Left Front Side", x: 0.21, y: 0.41, width: 0.13, height: 0.13),
        ConditionFormRegion(id: "left_rear", title: "Left Rear Side", x: 0.21, y: 0.63, width: 0.13, height: 0.13),
        ConditionFormRegion(id: "right_front", title: "Right Front Side", x: 0.66, y: 0.41, width: 0.13, height: 0.13),
        ConditionFormRegion(id: "right_rear", title: "Right Rear Side", x: 0.66, y: 0.63, width: 0.13, height: 0.13)
    ]
}
