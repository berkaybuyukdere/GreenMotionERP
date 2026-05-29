import SwiftUI

struct JarvisChatRow: Identifiable {
    let id = UUID()
    let isUser: Bool
    let text: String
    let tables: [JarvisDataTable]
}

enum JarvisSheetPhase {
    case hub
    case conversation
}

struct CHPanelJarvisSheet: View {
    let fleetContext: JarvisFleetDataContext
    let languageCode: String
    let jarvisEnabled: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var phase: JarvisSheetPhase = .hub
    @State private var rows: [JarvisChatRow] = []
    @State private var input = ""
    @State private var isSending = false
    @State private var errorText: String?
    @State private var shareURLs: [URL] = []
    @State private var showShare = false
    @State private var lastRequest: JarvisAnalysisRequest?

    var body: some View {
        NavigationStack {
            ZStack {
                PalantirTheme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    statusBar
                    if phase == .hub {
                        hubScroll
                    } else {
                        chatScroll
                        chatInputBar
                    }
                }
            }
            .navigationTitle("JARVIS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(PalantirTheme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close".localized) { dismiss() }
                        .foregroundStyle(PalantirTheme.accent)
                }
                if phase == .conversation {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            phase = .hub
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .foregroundStyle(PalantirTheme.accent)
                    }
                }
            }
            .sheet(isPresented: $showShare) {
                JarvisShareSheet(urls: shareURLs)
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle().fill(PalantirTheme.success).frame(width: 6, height: 6)
            Text("ch_panel.jarvis_readonly_notice".localized)
                .font(PalantirTheme.labelFont(10))
                .foregroundStyle(PalantirTheme.textMuted)
            Spacer()
            Text(fleetContext.franchiseId.uppercased())
                .font(PalantirTheme.dataFont(10))
                .foregroundStyle(PalantirTheme.textMuted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(PalantirTheme.surfaceHigh)
    }

    private var hubScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("jarvis.hub.subtitle".localized)
                    .font(PalantirTheme.bodyFont(13))
                    .foregroundStyle(PalantirTheme.textMuted)

                if !jarvisEnabled {
                    Text("jarvis.hub.ch_only".localized)
                        .font(PalantirTheme.bodyFont(13))
                        .foregroundStyle(PalantirTheme.warning)
                        .palantirCard()
                } else if !GroqInsightsService.shared.hasAPIKey {
                    Text("jarvis.hub.no_key".localized)
                        .font(PalantirTheme.bodyFont(13))
                        .foregroundStyle(PalantirTheme.critical)
                        .palantirCard()
                }

                sectionHeader("jarvis.section.period".localized)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(JarvisPeriod.allCases) { period in
                        quickTile(
                            title: period.titleKey.localized,
                            subtitle: "jarvis.quick.executive".localized,
                            icon: "chart.bar.doc.horizontal"
                        ) {
                            runQuickAction(JarvisQuickAction(
                                id: "exec_\(period.rawValue)",
                                period: period,
                                domain: .overview,
                                promptKey: "jarvis.prompt.executive"
                            ))
                        }
                    }
                }

                sectionHeader("jarvis.section.domains".localized)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(domainActions) { action in
                        quickTile(
                            title: action.domain.titleKey.localized,
                            subtitle: JarvisPeriod.monthly.titleKey.localized,
                            icon: action.domain.icon
                        ) {
                            runQuickAction(action)
                        }
                    }
                }

                sectionHeader("jarvis.section.system".localized)
                quickTile(
                    title: JarvisDomain.systemHealth.titleKey.localized,
                    subtitle: "jarvis.quick.health_sub".localized,
                    icon: JarvisDomain.systemHealth.icon,
                    fullWidth: true
                ) {
                    runHealthScan(exportAfter: false)
                }

                quickTile(
                    title: "jarvis.quick.health_export".localized,
                    subtitle: "jarvis.quick.health_export_sub".localized,
                    icon: "doc.richtext",
                    fullWidth: true
                ) {
                    runHealthScan(exportAfter: true)
                }
            }
            .padding(16)
        }
    }

    private var domainActions: [JarvisQuickAction] {
        JarvisQuickAction.gridActions().filter { $0.id.hasPrefix("domain_") }
    }

    private var chatScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(rows) { row in
                        jarvisBubble(row).id(row.id)
                    }
                    if isSending { thinkingRow.id("thinking") }
                }
                .padding(16)
            }
            .onChange(of: rows.count) { _, _ in
                if let last = rows.last?.id {
                    withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
    }

    private var chatInputBar: some View {
        VStack(spacing: 8) {
            if let errorText {
                Text(errorText)
                    .font(PalantirTheme.labelFont(11))
                    .foregroundStyle(PalantirTheme.critical)
            }
                HStack(spacing: 10) {
                    TextField("ch_panel.jarvis_placeholder".localized, text: $input, axis: .vertical)
                        .lineLimit(1...4)
                        .font(PalantirTheme.bodyFont())
                        .foregroundStyle(PalantirTheme.textPrimary)
                        .padding(10)
                        .background(PalantirTheme.surfaceHigh)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(PalantirTheme.border))
                Button { sendFreeform() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(PalantirTheme.accent)
                }
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending || !jarvisEnabled)
            }
            .padding(12)
            .background(PalantirTheme.surface)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(PalantirTheme.labelFont(10))
            .foregroundStyle(PalantirTheme.textMuted)
            .tracking(0.8)
    }

    private func quickTile(
        title: String,
        subtitle: String,
        icon: String,
        fullWidth: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(PalantirTheme.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(PalantirTheme.heroFont(13))
                        .foregroundStyle(PalantirTheme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(PalantirTheme.labelFont(10))
                        .foregroundStyle(PalantirTheme.textMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(PalantirTheme.textMuted)
            }
            .frame(maxWidth: fullWidth ? .infinity : nil, alignment: .leading)
            .palantirCard()
        }
        .buttonStyle(.plain)
        .disabled(isSending || !jarvisEnabled || !GroqInsightsService.shared.hasAPIKey)
    }

    @ViewBuilder
    private func jarvisBubble(_ row: JarvisChatRow) -> some View {
        VStack(alignment: row.isUser ? .trailing : .leading, spacing: 8) {
            Text(row.text)
                .font(PalantirTheme.bodyFont())
                .foregroundStyle(row.isUser ? PalantirTheme.textPrimary : PalantirTheme.textPrimary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: row.isUser ? .trailing : .leading)
                .background(row.isUser ? PalantirTheme.surfaceHigh : PalantirTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(PalantirTheme.border, lineWidth: 1)
                )

            if !row.isUser {
                ForEach(row.tables) { table in
                    palantirTable(table)
                    HStack(spacing: 16) {
                        Button { exportPDF(tables: [table], narrative: row.text) } label: {
                            Label("ch_panel.jarvis_export_pdf".localized, systemImage: "doc.fill")
                                .font(PalantirTheme.labelFont(11))
                                .foregroundStyle(PalantirTheme.accent)
                        }
                        Button { exportExcel(table: table) } label: {
                            Label("ch_panel.jarvis_export_excel".localized, systemImage: "tablecells")
                                .font(PalantirTheme.labelFont(11))
                                .foregroundStyle(PalantirTheme.accent)
                        }
                    }
                }
            }
        }
    }

    private func palantirTable(_ table: JarvisDataTable) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(table.title.uppercased())
                .font(PalantirTheme.labelFont(10))
                .foregroundStyle(PalantirTheme.textMuted)
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        ForEach(table.headers, id: \.self) { h in
                            Text(h.uppercased())
                                .font(PalantirTheme.labelFont(9))
                                .foregroundStyle(PalantirTheme.accent)
                                .frame(minWidth: 80, alignment: .leading)
                        }
                    }
                    ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                Text(cell)
                                    .font(PalantirTheme.dataFont(11))
                                    .foregroundStyle(PalantirTheme.textPrimary)
                                    .frame(minWidth: 80, alignment: .leading)
                            }
                        }
                    }
                }
            }
        }
        .palantirCard()
    }

    private var thinkingRow: some View {
        HStack(spacing: 8) {
            ProgressView().tint(PalantirTheme.accent)
            Text("ch_panel.jarvis_thinking".localized)
                .font(PalantirTheme.dataFont(12))
                .foregroundStyle(PalantirTheme.textMuted)
        }
        .palantirCard()
    }

    private func runQuickAction(_ action: JarvisQuickAction) {
        let request = JarvisAnalysisRequest(
            period: action.period,
            domain: action.domain,
            languageCode: languageCode,
            customQuestion: nil
        )
        runAnalysis(request: request, userLabel: "\(action.period.titleKey.localized) · \(action.domain.titleKey.localized)")
    }

    private func runHealthScan(exportAfter: Bool) {
        let request = JarvisAnalysisRequest(
            period: .monthly,
            domain: .systemHealth,
            languageCode: languageCode,
            customQuestion: nil
        )
        runAnalysis(request: request, userLabel: JarvisDomain.systemHealth.titleKey.localized, forceTables: [fleetContext.healthReport.table], exportPDFAfter: exportAfter)
    }

    private func runAnalysis(
        request: JarvisAnalysisRequest,
        userLabel: String,
        forceTables: [JarvisDataTable]? = nil,
        exportPDFAfter: Bool = false
    ) {
        guard jarvisEnabled, GroqInsightsService.shared.hasAPIKey else { return }
        phase = .conversation
        errorText = nil
        rows.append(JarvisChatRow(isUser: true, text: userLabel, tables: []))
        isSending = true
        lastRequest = request

        Task {
            do {
                let tables = forceTables ?? fleetContext.tables(for: request)
                let json = fleetContext.compactJSON(for: request)
                let hint = tables.map(\.id)
                let raw = try await GroqInsightsService.shared.jarvisAnalyze(
                    request: request,
                    contextJSON: json,
                    tablesHint: hint
                )
                let parsed = JarvisResponseParser.parse(raw)
                let displayTables = tables.isEmpty ? resolveTables(ids: parsed.requestedTableIds, parsed: parsed.tables) : tables

                await MainActor.run {
                    rows.append(JarvisChatRow(isUser: false, text: parsed.text, tables: displayTables))
                    isSending = false
                }

                if exportPDFAfter, !displayTables.isEmpty {
                    await presentExportPDF(tables: displayTables, narrative: parsed.text, title: "Jarvis System Health")
                }
            } catch {
                await MainActor.run {
                    errorText = error.localizedDescription
                    isSending = false
                }
            }
        }
    }

    private func sendFreeform() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, jarvisEnabled else { return }
        phase = .conversation
        input = ""
        errorText = nil
        rows.append(JarvisChatRow(isUser: true, text: text, tables: []))
        isSending = true

        let export = JarvisIntentDetector.exportIntent(text)
        let history = rows.dropLast().map { GroqChatMessage(role: $0.isUser ? "user" : "assistant", content: $0.text) }

        Task {
            do {
                let raw = try await GroqInsightsService.shared.jarvisFreeChat(
                    userMessage: text,
                    overviewJSON: fleetContext.overviewJSON(),
                    history: Array(history),
                    languageCode: languageCode
                )
                let parsed = JarvisResponseParser.parse(raw)
                let merged = resolveTables(ids: parsed.requestedTableIds, parsed: parsed.tables)

                await MainActor.run {
                    rows.append(JarvisChatRow(isUser: false, text: parsed.text, tables: merged))
                    isSending = false
                }

                if export == .pdf, !merged.isEmpty {
                    await presentExportPDF(tables: merged, narrative: parsed.text, title: "Jarvis Report")
                } else if export == .excel, let first = merged.first {
                    await presentExportExcel(table: first)
                }
            } catch {
                await MainActor.run {
                    errorText = error.localizedDescription
                    isSending = false
                }
            }
        }
    }

    private func resolveTables(ids: [String], parsed: [JarvisDataTable]) -> [JarvisDataTable] {
        var out: [JarvisDataTable] = []
        var seen = Set<String>()
        let all = fleetContext.tables
        for id in ids {
            if let t = all[id], !seen.contains(id) {
                out.append(t)
                seen.insert(id)
            }
        }
        for t in parsed where !seen.contains(t.id) {
            out.append(t)
            seen.insert(t.id)
        }
        return out
    }

    @MainActor
    private func presentExportPDF(tables: [JarvisDataTable], narrative: String, title: String) {
        do {
            let name = "Jarvis_\(fleetContext.franchiseId)_\(Int(Date().timeIntervalSince1970))"
            let url = try JarvisExportService.writePDF(title: title, tables: tables, narrative: narrative, filename: name)
            shareURLs = [url]
            showShare = true
        } catch {
            errorText = error.localizedDescription
        }
    }

    @MainActor
    private func presentExportExcel(table: JarvisDataTable) {
        do {
            let name = "Jarvis_\(table.id)_\(Int(Date().timeIntervalSince1970))"
            let url = try JarvisExportService.writeCSV(table, filename: name)
            shareURLs = [url]
            showShare = true
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func exportPDF(tables: [JarvisDataTable], narrative: String) {
        Task { await presentExportPDF(tables: tables, narrative: narrative, title: "Jarvis Report") }
    }

    private func exportExcel(table: JarvisDataTable) {
        Task { await presentExportExcel(table: table) }
    }
}
