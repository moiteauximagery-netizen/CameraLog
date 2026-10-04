import Foundation

/// Clip numbers are positions in the card order of a roll. They are computed, never typed.
enum ClipCode {
    static func code(_ position: Int) -> String { "C" + String(format: "%03d", position) }
}

/// A computed number that a confirmed action would change, shown before confirmation.
struct ClipChange: Identifiable, Equatable {
    let id: UUID
    let title: String
    let from: String
    let to: String
    var line: String { "\(title) : \(from) → \(to)" }
}

enum ClipSequence {
    /// 1-based positions of the entries whose computed number differs between two orderings.
    /// Entries missing from `after` are ignored.
    static func renumbered(before: [UUID], after: [UUID]) -> [(id: UUID, from: Int, to: Int)] {
        var positions: [UUID: Int] = [:]
        for (index, id) in after.enumerated() { positions[id] = index + 1 }
        return before.enumerated().compactMap { index, id in
            guard let to = positions[id], to != index + 1 else { return nil }
            return (id, index + 1, to)
        }
    }

    static func summary(_ changes: [ClipChange], limit: Int = 8) -> String {
        guard !changes.isEmpty else { return "Aucun numéro de clip ne change." }
        var lines = changes.prefix(limit).map(\.line)
        if changes.count > limit { lines.append("… et \(changes.count - limit) autres.") }
        return lines.joined(separator: "\n")
    }
}

/// Take order number and free label are distinct: « T03 · PU ».
enum TakeLabel {
    static let quick = ["PU", "FC"]
    static func code(_ number: Int) -> String { String(format: "T%02d", number) }
    static func title(number: Int, label: String) -> String {
        label.isEmpty ? code(number) : "\(code(number)) · \(label)"
    }
    static func normalized(_ label: String) -> String {
        String(label.trimmingCharacters(in: .whitespacesAndNewlines).prefix(16))
    }
}

/// What touching a take does on the shot sheet.
enum TakeTapMode: Equatable { case edit, circle }
enum TakeTapAction: Equatable { case edit(UUID), toggleCircle(UUID) }
