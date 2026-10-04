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

/// Take number and free label are distinct; they are shown together: « 4PU ».
/// Number 0 means « no take number »: a false clip typed « FC » frees its number for the next take.
enum TakeLabel {
    static let quick = ["PU", "FC"]
    static let falseClip = "FC"
    static func code(_ number: Int) -> String { String(number) }
    static func title(number: Int, label: String) -> String {
        if number > 0 { return code(number) + label }
        return label.isEmpty ? "—" : label
    }
    /// Full text typed in a take box: « 4PU » → (4, PU), « FC » → (0, FC), « 12 » → (12, ""). Empty: nil.
    static func parse(_ text: String) -> (number: Int, label: String)? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let digits = String(value.prefix { $0.isASCII && $0.isNumber })
        if let number = Int(digits), number > 0, number < 1000 {
            return (number, normalized(String(value.dropFirst(digits.count))))
        }
        return (0, normalized(value))
    }
    static func normalized(_ label: String) -> String {
        String(label.trimmingCharacters(in: .whitespacesAndNewlines).prefix(16))
    }
    /// Text typed in a take box. « 4PU » typed on take 4 keeps the label « PU »; the number never changes.
    static func label(fromTyped text: String, number: Int) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = code(number)
        if value.hasPrefix(prefix) { value = String(value.dropFirst(prefix.count)) }
        return normalized(value)
    }
}

/// What touching a take does on the shot sheet.
enum TakeTapMode: Equatable { case edit, circle }
enum TakeTapAction: Equatable { case edit(UUID), toggleCircle(UUID) }
