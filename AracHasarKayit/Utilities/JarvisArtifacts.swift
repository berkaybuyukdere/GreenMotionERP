import UIKit
import SwiftUI

struct JarvisDataTable: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let headers: [String]
    let rows: [[String]]
}

struct JarvisParsedReply {
    let text: String
    let tables: [JarvisDataTable]
    let requestedTableIds: [String]
}

// Export intent lives in JarvisAnalysisModels.JarvisIntentDetector

enum JarvisResponseParser {
    static func parse(_ raw: String) -> JarvisParsedReply {
        var text = raw
        var tables: [JarvisDataTable] = []
        var ids: [String] = []

        if let jsonPart = extractJarvisJSON(from: raw) {
            text = stripJarvisFence(from: raw)
            if let data = jsonPart.data(using: .utf8),
               let obj = try? JSONDecoder().decode(JarvisArtifactPayload.self, from: data) {
                tables = obj.tables ?? []
                ids = obj.use_tables ?? []
            }
        }

        if text.isEmpty { text = raw }
        return JarvisParsedReply(text: text, tables: tables, requestedTableIds: ids)
    }

    private static func extractJarvisJSON(from raw: String) -> String? {
        for marker in ["```jarvis", "```json"] {
            guard let start = raw.range(of: marker) else { continue }
            var bodyStart = start.upperBound
            if bodyStart < raw.endIndex, raw[bodyStart] == "\n" {
                bodyStart = raw.index(after: bodyStart)
            }
            if let end = raw[bodyStart...].range(of: "```") {
                let candidate = String(raw[bodyStart..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if candidate.contains("{") { return candidate }
            }
        }
        if let r = raw.range(of: "\"use_tables\""),
           let open = raw[..<r.lowerBound].lastIndex(of: "{"),
           let close = raw[open...].lastIndex(of: "}") {
            return String(raw[open...close])
        }
        return nil
    }

    private static func stripJarvisFence(from raw: String) -> String {
        for marker in ["```jarvis", "```json"] {
            if let start = raw.range(of: marker),
               let end = raw[start.upperBound...].range(of: "```") {
                var out = String(raw[..<start.lowerBound])
                if end.upperBound < raw.endIndex {
                    out += String(raw[end.upperBound...])
                }
                return out.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if let open = raw.firstIndex(of: "{"), let close = raw.lastIndex(of: "}"),
           raw[open...].contains("\"use_tables\"") {
            return String(raw[..<open]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct JarvisArtifactPayload: Codable {
    let tables: [JarvisDataTable]?
    let use_tables: [String]?
}

enum JarvisExportService {

    static func csvData(for table: JarvisDataTable) -> Data {
        var lines: [String] = []
        lines.append(table.title)
        lines.append(table.headers.map { escapeCSV($0) }.joined(separator: ","))
        for row in table.rows {
            lines.append(row.map { escapeCSV($0) }.joined(separator: ","))
        }
        let body = lines.joined(separator: "\n")
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(body.data(using: .utf8) ?? Data())
        return data
    }

    static func writeCSV(_ table: JarvisDataTable, filename: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename).appendingPathExtension("csv")
        try csvData(for: table).write(to: url)
        return url
    }

    static func writePDF(title: String, tables: [JarvisDataTable], narrative: String, filename: String) throws -> URL {
        let pageWidth: CGFloat = 595
        let pageHeight: CGFloat = 842
        let margin: CGFloat = 40
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename).appendingPathExtension("pdf")
        let data = renderer.pdfData { ctx in
            var y: CGFloat = margin
            ctx.beginPage()

            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 18),
                .foregroundColor: UIColor.black
            ]
            title.draw(at: CGPoint(x: margin, y: y), withAttributes: titleAttrs)
            y += 28

            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9),
                .foregroundColor: UIColor.gray
            ]
            "Jarvis — read-only fleet export".draw(at: CGPoint(x: margin, y: y), withAttributes: subAttrs)
            y += 20

            if !narrative.isEmpty {
                let para = narrative.prefix(1200)
                let bodyAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 11),
                    .foregroundColor: UIColor.darkGray
                ]
                let rect = CGRect(x: margin, y: y, width: pageWidth - margin * 2, height: 120)
                String(para).draw(in: rect, withAttributes: bodyAttrs)
                y += 130
            }

            for table in tables {
                if y > pageHeight - 120 {
                    ctx.beginPage()
                    y = margin
                }
                drawTable(table, context: ctx, x: margin, y: &y, pageWidth: pageWidth, margin: margin)
                y += 24
            }
        }
        try data.write(to: url)
        return url
    }

    private static func drawTable(
        _ table: JarvisDataTable,
        context: UIGraphicsPDFRendererContext,
        x: CGFloat,
        y: inout CGFloat,
        pageWidth: CGFloat,
        margin: CGFloat
    ) {
        let headFont = UIFont.boldSystemFont(ofSize: 10)
        let cellFont = UIFont.systemFont(ofSize: 9)
        let hAttrs: [NSAttributedString.Key: Any] = [.font: headFont, .foregroundColor: UIColor.black]
        let cAttrs: [NSAttributedString.Key: Any] = [.font: cellFont, .foregroundColor: UIColor.darkGray]

        table.title.draw(at: CGPoint(x: x, y: y), withAttributes: hAttrs)
        y += 16

        let colW = (pageWidth - margin * 2) / CGFloat(max(table.headers.count, 1))
        for (i, h) in table.headers.enumerated() {
            h.draw(in: CGRect(x: x + CGFloat(i) * colW, y: y, width: colW, height: 14), withAttributes: hAttrs)
        }
        y += 16
        for row in table.rows.prefix(40) {
            for (i, cell) in row.enumerated() {
                cell.draw(in: CGRect(x: x + CGFloat(i) * colW, y: y, width: colW, height: 14), withAttributes: cAttrs)
            }
            y += 14
        }
    }

    private static func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}

struct JarvisShareSheet: UIViewControllerRepresentable {
    let urls: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
