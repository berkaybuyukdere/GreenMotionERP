import SwiftUI

struct TurkeyDocumentationToolbarButton: View {
    let topic: TurkeyDocumentationTopic
    @State private var showDocumentation = false

    var body: some View {
        Button {
            HapticManager.shared.light()
            showDocumentation = true
        } label: {
            Image(systemName: "book.closed")
                .font(.body.weight(.semibold))
        }
        .accessibilityLabel("tr_docs.title".localized)
        .sheet(isPresented: $showDocumentation) {
            NavigationStack {
                TurkeyDocumentationDetailView(topic: topic)
            }
        }
    }
}

struct TurkeyDocumentationListView: View {
    var body: some View {
        List {
            Section {
                ForEach(TurkeyDocumentationTopic.allCases) { topic in
                    NavigationLink {
                        TurkeyDocumentationDetailView(topic: topic)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(topic.titleKey.localized)
                                    .font(.headline)
                                Text(topic.subtitleKey.localized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        } icon: {
                            Image(systemName: topic.iconSystemName)
                                .foregroundStyle(.blue)
                        }
                    }
                }
            } header: {
                Text("tr_docs.list.header".localized)
            } footer: {
                Text("tr_docs.list.footer".localized)
            }
        }
        .navigationTitle("tr_docs.title".localized)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TurkeyDocumentationDetailView: View {
    let topic: TurkeyDocumentationTopic
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(topic.titleKey.localized, systemImage: topic.iconSystemName)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(PalantirTheme.textPrimary)
                    Text(topic.subtitleKey.localized)
                        .font(.subheadline)
                        .foregroundStyle(PalantirTheme.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(PalantirTheme.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(PalantirTheme.border, lineWidth: 1)
                        )
                )

                ForEach(topic.sections) { section in
                    TurkeyDocumentationSectionCard(section: section)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("tr_docs.title".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done".localized) { dismiss() }
            }
        }
    }
}

private struct TurkeyDocumentationSectionCard: View {
    let section: TurkeyDocumentationTopic.Section

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.titleKey.localized)
                .font(PalantirTheme.heroFont(15))
                .foregroundStyle(PalantirTheme.textPrimary)
            Text(section.bodyKey.localized)
                .font(PalantirTheme.bodyFont(14))
                .foregroundStyle(PalantirTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            if !section.bulletKeys.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(section.bulletKeys, id: \.self) { key in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .foregroundStyle(PalantirTheme.accent)
                            Text(key.localized)
                                .font(PalantirTheme.bodyFont(13))
                                .foregroundStyle(PalantirTheme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(PalantirTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(PalantirTheme.border, lineWidth: 1)
                )
        )
    }
}
