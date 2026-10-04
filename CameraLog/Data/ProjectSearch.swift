import Foundation

/// Filters offered on the production page. Values are taken from what exists in the project.
enum SearchFacet: String, CaseIterable, Identifiable {
    case day, camera, roll, scene, status
    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return "Jour"
        case .camera: return "Caméra"
        case .roll: return "Roll"
        case .scene: return "Séquence"
        case .status: return "Statut"
        }
    }

    func display(_ value: String) -> String {
        switch self {
        case .day: return "DAY \(value)"
        case .camera: return "CAM \(value)"
        case .roll: return value
        case .scene: return "Séq. \(value)"
        case .status: return value == TakeStatus.circle.rawValue ? "Cerclée" : value
        }
    }
}

/// Free text plus multi-selection per facet. Values of one facet are alternatives (DAY 12 or DAY 13);
/// different facets are combined (DAY 12 and CAM A).
struct SearchFilters: Equatable {
    var text = ""
    var selection: [SearchFacet: Set<String>] = [:]

    var term: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    var hasFacets: Bool { selection.values.contains { !$0.isEmpty } }
    var isActive: Bool { !term.isEmpty || hasFacets }

    func values(_ facet: SearchFacet) -> Set<String> { selection[facet] ?? [] }

    mutating func toggle(_ value: String, in facet: SearchFacet) {
        var current = values(facet)
        if current.contains(value) { current.remove(value) } else { current.insert(value) }
        selection[facet] = current
    }

    mutating func clear(_ facet: SearchFacet) { selection[facet] = [] }

    mutating func clearAll() {
        selection = [:]
        text = ""
    }

    /// Chip text: « Jour : 12, 13 ». Nil when the facet is not used.
    func summary(_ facet: SearchFacet) -> String? {
        let chosen = values(facet).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        guard !chosen.isEmpty else { return nil }
        let shown = facet == .status ? chosen.map { facet.display($0) } : chosen
        return "\(facet.title) : \(shown.joined(separator: ", "))"
    }
}

/// One sheet found, with the takes that match (all of them when no take-level criterion applies).
struct SearchHit: Identifiable {
    let sheet: ShotSheet
    let takes: [TakeEntry]
    let day: ShootDay
    let report: CameraReport
    let roll: Roll
    var id: UUID { sheet.id }
}

struct SearchResult {
    var hits: [SearchHit] = []
    var options: [SearchFacet: [String]] = [:]
    var takeCount: Int { hits.reduce(0) { $0 + $1.takes.count } }
    var circleCount: Int { hits.reduce(0) { $0 + $1.takes.filter(\.isCircle).count } }
}

enum ProjectSearch {
    /// Statuses a take can be filtered on: Circle and other statuses, plus its label (PU, FC…).
    static func statuses(of take: TakeEntry) -> Set<String> {
        var result = Set(take.statusValues)
        let label = take.labelText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !label.isEmpty { result.insert(label) }
        return result
    }

    static func run(_ production: Production, filters: SearchFilters) -> SearchResult {
        var options: [SearchFacet: Set<String>] = [:]
        var hits: [SearchHit] = []
        let term = filters.term
        let wanted = filters.values(.status)
        let days = production.days.filter { $0.production?.id == production.id }.sorted { $0.number < $1.number }
        for day in days {
            let reports = day.reports.filter { $0.day?.id == day.id }
                .sorted { ($0.camera?.name ?? "") < ($1.camera?.name ?? "") }
            for report in reports {
                let camera = report.camera?.name ?? ""
                for roll in report.orderedRolls {
                    for sheet in roll.currentSheets.sorted(by: { $0.createdAt < $1.createdAt }) {
                        let keys: [SearchFacet: String] = [.day: String(day.number), .camera: camera,
                                                           .roll: roll.name, .scene: sheet.scene]
                        for (facet, value) in keys where !value.isEmpty { options[facet, default: []].insert(value) }
                        let takes = sheet.orderedTakes
                        for take in takes { options[.status, default: []].formUnion(statuses(of: take)) }

                        let facetsMatch = keys.allSatisfy { entry in
                            let selected = filters.values(entry.key)
                            return selected.isEmpty || selected.contains(entry.value)
                        }
                        guard facetsMatch else { continue }
                        let sheetFields = [sheet.scene, sheet.shot, sheet.scene + sheet.shot, sheet.title, roll.name,
                                           "CAM \(camera)", "DAY \(day.number)", day.location, sheet.notes]
                            + Array(sheet.settings.values)
                        let sheetText = term.isEmpty || matches(term, sheetFields)
                        let matching = takes.filter { take in
                            (wanted.isEmpty || !wanted.isDisjoint(with: statuses(of: take)))
                                && (sheetText || matches(term, [take.labelText, take.notes,
                                                                TakeLabel.title(number: take.number, label: take.labelText)]
                                                         + Array(take.snapshot.values)))
                        }
                        let wholeSheet = wanted.isEmpty && sheetText
                        if wholeSheet || !matching.isEmpty {
                            hits.append(SearchHit(sheet: sheet, takes: wholeSheet ? takes : matching,
                                                  day: day, report: report, roll: roll))
                        }
                    }
                }
            }
        }
        var result = SearchResult()
        result.hits = hits
        for (facet, values) in options {
            result.options[facet] = values.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }
        return result
    }

    private static func matches(_ term: String, _ fields: [String]) -> Bool {
        fields.contains { $0.localizedStandardContains(term) }
    }
}
