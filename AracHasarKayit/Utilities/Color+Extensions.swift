import SwiftUI

extension Color {
    // Hasar türü renkleri
    static let hasarRed = Color.red
    static let hasarOrange = Color.orange
    static let hasarBlue = Color.blue
    static let hasarPurple = Color.purple
    static let hasarYellow = Color.yellow
    static let hasarCyan = Color.cyan
    static let hasarGray = Color.gray
    static let hasarBrown = Color.brown
    static let hasarGreen = Color.green
    
    // Activity renkleri
    static let activityGreen = Color.green
    static let activityRed = Color.red
    static let activityOrange = Color.orange
    static let activityBlue = Color.blue
    static let activityPurple = Color.purple
    
    // String'den Color'a dönüşüm
    init(fromString string: String) {
        switch string.lowercased() {
        case "red": self = .red
        case "orange": self = .orange
        case "blue": self = .blue
        case "purple": self = .purple
        case "yellow": self = .yellow
        case "cyan": self = .cyan
        case "gray": self = .gray
        case "brown": self = .brown
        case "green": self = .green
        default: self = .gray
        }
    }
}
