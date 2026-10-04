import SwiftUI

/// Horizontal row of filter chips: Jour · Caméra · Roll · Séquence · Statut.
struct FilterChipsRow: View {
    @Binding var filters: SearchFilters
    let open: (SearchFacet) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SearchFacet.allCases) { facet in
                    let summary = filters.summary(facet)
                    Button { open(facet) } label: {
                        HStack(spacing: 4) {
                            Text(summary ?? facet.title).lineLimit(1)
                            Image(systemName: "chevron.down").font(.caption2)
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 36)
                        .foregroundStyle(summary == nil ? Color.primary : Color.black)
                        .background(summary == nil ? Color.gray.opacity(0.2) : Color.orange, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Filtre \(facet.title)")
                    .accessibilityValue(summary ?? "aucun")
                    .accessibilityIdentifier("facet-\(facet.rawValue)")
                }
                if filters.isActive {
                    Button { filters.clearAll() } label: {
                        Label("Tout effacer", systemImage: "xmark.circle.fill")
                            .font(.subheadline)
                            .frame(minHeight: 36)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("clear-filters")
                }
            }
            .padding(.vertical, 2)
        }
    }
}

/// Multi-selection of the values that exist in the project for one facet.
struct FacetPicker: View {
    let facet: SearchFacet
    let options: [String]
    @Binding var filters: SearchFilters
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if options.isEmpty {
                    Text("Aucune valeur dans ce projet.").foregroundStyle(.secondary)
                }
                ForEach(options, id: \.self) { value in
                    let selected = filters.values(facet).contains(value)
                    Button { filters.toggle(value, in: facet) } label: {
                        HStack {
                            Text(facet.display(value))
                            Spacer()
                            if selected { Image(systemName: "checkmark").foregroundStyle(.orange) }
                        }
                        .contentShape(Rectangle())
                    }
                    .foregroundStyle(.primary)
                    .frame(minHeight: 44)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("option-\(value)")
                }
            }
            .navigationTitle(facet.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Effacer") { filters.clear(facet) }
                        .disabled(filters.values(facet).isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }.bold().accessibilityIdentifier("facet-done")
                }
            }
        }
    }
}

/// Results grouped by day, camera and roll, as sheets or as a take-by-take list.
struct SearchResultsSections: View {
    let result: SearchResult
    let showTakes: Bool
    let repository: CameraLogRepository

    private struct ResultGroup: Identifiable {
        let id: String
        let title: String
        var hits: [SearchHit]
    }

    private var groups: [ResultGroup] {
        var list: [ResultGroup] = []
        for hit in result.hits {
            let key = "\(hit.day.id)|\(hit.report.id)|\(hit.roll.id)"
            if let index = list.firstIndex(where: { $0.id == key }) {
                list[index].hits.append(hit)
            } else {
                list.append(ResultGroup(id: key, title: "DAY \(hit.day.number) · CAM \(hit.report.camera?.name ?? "—") · ROLL \(hit.roll.name)",
                                  hits: [hit]))
            }
        }
        return list
    }

    var body: some View {
        if result.hits.isEmpty {
            ContentUnavailableView("Aucun résultat", systemImage: "magnifyingglass",
                                   description: Text("Retire un filtre ou modifie la recherche."))
        }
        ForEach(groups) { group in
            Section(group.title) {
                ForEach(group.hits) { hit in
                    if showTakes {
                        ForEach(hit.takes) { take in
                            NavigationLink {
                                SheetView(report: hit.report, repository: repository, sheet: hit.sheet)
                            } label: {
                                TakeResultRow(hit: hit, take: take)
                            }
                            .accessibilityIdentifier("result-take-\(hit.roll.name)-\(hit.roll.clipNumbers[take.id].map(ClipCode.code) ?? "")")
                        }
                    } else {
                        NavigationLink {
                            SheetView(report: hit.report, repository: repository, sheet: hit.sheet)
                        } label: {
                            SheetResultRow(hit: hit)
                        }
                        .accessibilityIdentifier("result-sheet-\(hit.sheet.scene)-\(hit.sheet.shot)")
                    }
                }
            }
        }
    }
}

private struct SheetResultRow: View {
    let hit: SearchHit
    var body: some View {
        let all = hit.sheet.orderedTakes.count
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.sheet.scene).font(.title3.bold())
                Text("PLAN \(hit.sheet.shot)").font(.caption).foregroundStyle(.secondary)
            }
            .frame(minWidth: 54, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    ForEach(hit.takes.prefix(6)) { take in
                        Text(TakeLabel.title(number: take.number, label: take.labelText))
                            .font(.caption.bold()).monospacedDigit()
                            .padding(.horizontal, 6).frame(minWidth: 26, minHeight: 26)
                            .foregroundStyle(take.isCircle ? Color.black : Color.primary)
                            .background(take.isCircle ? Color.orange : Color.clear, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.orange, lineWidth: 1))
                    }
                    if hit.takes.count > 6 { Text("+\(hit.takes.count - 6)").font(.caption) }
                }
                Text(hit.takes.count == all ? "\(all) prise(s)" : "\(hit.takes.count) / \(all) prises")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text(hit.sheet.settings[SheetField.lens.rawValue] ?? "—").font(.caption.bold()).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct TakeResultRow: View {
    let hit: SearchHit
    let take: TakeEntry
    var body: some View {
        let clip = hit.roll.clipNumbers[take.id].map(ClipCode.code) ?? "—"
        let lens = take.snapshot[SheetField.lens.rawValue] ?? ""
        HStack(spacing: 10) {
            Text(TakeLabel.title(number: take.number, label: take.labelText))
                .font(.headline).monospacedDigit()
                .padding(.horizontal, 8).frame(minWidth: 40, minHeight: 36)
                .foregroundStyle(take.isCircle ? Color.black : Color.primary)
                .background(take.isCircle ? Color.orange : Color.gray.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(hit.sheet.title) · \(clip)").font(.subheadline.bold()).monospacedDigit()
                Text([hit.roll.name, lens, take.notes].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(take.isCircle ? "cerclée" : "non cerclée")
    }
}
