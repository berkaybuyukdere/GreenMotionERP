import Foundation

/// NVIDIA NIM / Cosmos cloud API key — embedded (obfuscated), with optional Secrets.plist override.
enum NvidiaSecureKeyProvider {
    private static let plistKey = "NVIDIA_API_KEY"
    private static let seed = Array("com.greenmotion.AracHasarKayit.nvidia.v1.ch".utf8)
    private static let obfuscated: [UInt8] = [
        0x0D, 0x19, 0x0C, 0x5E, 0x0E, 0x5F, 0x28, 0x0E, 0x1C, 0x28, 0x06, 0x32, 0x0C, 0x38, 0x3F, 0x6F,
        0x39, 0x4B, 0x55, 0x29, 0x2A, 0x03, 0x0B, 0x0D, 0x21, 0x21, 0x24, 0x4F, 0x05, 0x04, 0x1F, 0x0A,
        0x25, 0x27, 0x2B, 0x5E, 0x07, 0x7B, 0x06, 0x4B, 0x5B, 0x31, 0x2A, 0x32, 0x5A, 0x0B, 0x6A, 0x17,
        0x05, 0x2B, 0x53, 0x5F, 0x35, 0x35, 0x45, 0x03, 0x5D, 0x00, 0x17, 0x06, 0x2A, 0x1B, 0x30, 0x7B,
        0x4C, 0x2C, 0x38, 0x05, 0x1B, 0x56
    ]

    static func apiKey() -> String? {
        if let fromPlist = readPlistKey(), isValid(fromPlist) { return fromPlist }
        if let env = ProcessInfo.processInfo.environment["NVIDIA_API_KEY"],
           isValid(env) { return env.trimmingCharacters(in: .whitespacesAndNewlines) }
        return embeddedKey()
    }

    private static func embeddedKey() -> String? {
        guard !obfuscated.isEmpty else { return nil }
        let decoded = obfuscated.enumerated().map { i, byte in
            byte ^ seed[i % seed.count]
        }
        let s = String(bytes: decoded, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let s, isValid(s) else { return nil }
        return s
    }

    private static func readPlistKey() -> String? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url),
              let raw = dict[plistKey] as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("YOUR_") else { return nil }
        return trimmed
    }

    private static func isValid(_ key: String) -> Bool {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return k.hasPrefix("nvapi-") && k.count > 24
    }
}
