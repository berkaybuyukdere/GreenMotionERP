import Foundation

struct SMTPConfiguration: Codable {
    var host: String = ""
    var port: Int = 587
    var username: String = ""
    var password: String = ""
    var senderName: String = ""
    var senderEmail: String = ""
    var useTLS: Bool = true
    var franchiseId: String = "CH"
    var updatedAt: Date = Date()
}

