import Foundation

/// Next plan proposed for a new sheet: 2 → 3, 09 → 10, A → B, 14A → 14B. Nil when unclear.
enum ShotIncrement {
    static func next(after shot: String) -> String? {
        let text = shot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let range = text.range(of: "[0-9]+$", options: .regularExpression) {
            let digits = String(text[range])
            guard let value = Int(digits), value < 100_000 else { return nil }
            var next = String(value + 1)
            if next.count < digits.count { next = String(repeating: "0", count: digits.count - next.count) + next }
            return String(text[..<range.lowerBound]) + next
        }
        guard let last = text.unicodeScalars.last, last.isASCII,
              CharacterSet.letters.contains(last), last != "z", last != "Z",
              let following = Unicode.Scalar(last.value + 1) else { return nil }
        var scalars = text.unicodeScalars
        scalars.removeLast()
        scalars.append(following)
        return String(scalars)
    }
}

/// Cameras of a day are named A, B, C… in the order they are added.
enum CameraNaming {
    static func next(used: [String]) -> String {
        let taken = Set(used.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() })
        for code in UInt8(65)...UInt8(90) {
            let letter = String(Character(UnicodeScalar(code)))
            if !taken.contains(letter) { return letter }
        }
        var index = 27
        while taken.contains("CAM \(index)") { index += 1 }
        return "CAM \(index)"
    }
}

/// Focal lengths available on the production, offered in a menu on the lens field.
enum LensKit {
    /// « 18, 25 32;50mm » → ["18 mm", "25 mm", "32 mm", "50mm"]. Bare numbers get « mm ».
    static func parse(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",;\n"))
            .flatMap { part -> [String] in
                let trimmed = part.trimmingCharacters(in: .whitespaces)
                // « 25 32 » typed with spaces only: split bare numbers.
                let words = trimmed.split(separator: " ").map(String.init)
                if words.count > 1 && words.allSatisfy({ Double($0) != nil }) { return words }
                return [trimmed]
            }
            .map(normalized)
            .filter { !$0.isEmpty }
    }

    static func normalized(_ entry: String) -> String {
        let trimmed = entry.trimmingCharacters(in: .whitespaces)
        return Double(trimmed) != nil ? "\(trimmed) mm" : trimmed
    }

    /// Adds entries without duplicates, sorted by focal length.
    static func merged(_ kit: [String], adding entries: [String]) -> [String] {
        var result = kit
        for entry in entries where !result.contains(where: { $0.caseInsensitiveCompare(entry) == .orderedSame }) {
            result.append(entry)
        }
        return result.sorted { (focal($0) ?? .greatestFiniteMagnitude, $0) < (focal($1) ?? .greatestFiniteMagnitude, $1) }
    }

    static func focal(_ entry: String) -> Double? {
        guard let range = entry.range(of: "^[0-9]+([.,][0-9]+)?", options: .regularExpression) else { return nil }
        return Double(entry[range].replacingOccurrences(of: ",", with: "."))
    }
}

/// A filter family of the production kit and its grades: ND 0.3/0.6/0.9, BPM 1/8/1/4…
struct FilterFamily: Codable, Equatable, Hashable, Identifiable {
    var name: String
    var grades: [String]
    var id: String { name }

    static let defaultKit: [FilterFamily] = [
        FilterFamily(name: "ND", grades: ["0.3", "0.6", "0.9", "1.2", "1.5", "1.8", "2.1"]),
        FilterFamily(name: "IRND", grades: ["0.3", "0.6", "0.9", "1.2", "1.5", "1.8", "2.1"]),
        FilterFamily(name: "BPM", grades: ["1/8", "1/4", "1/2", "1"]),
        FilterFamily(name: "HBM", grades: ["1/8", "1/4", "1/2", "1"]),
        FilterFamily(name: "Glimmer", grades: ["1/8", "1/4", "1/2", "1"]),
        FilterFamily(name: "POLA", grades: [])
    ]

    /// « 1/8, 1/4 ; 1/2 » → ["1/8", "1/4", "1/2"].
    static func parseGrades(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",;\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

/// The FILTRES field holds combined filters: « ND 0.6 + BPM 1/4 ».
enum FilterSelection {
    static func items(_ text: String) -> [String] {
        text.split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func value(family: String, grade: String) -> String {
        grade.isEmpty ? family : "\(family) \(grade)"
    }

    private static func belongs(_ item: String, to family: String) -> Bool {
        item.caseInsensitiveCompare(family) == .orderedSame
            || item.lowercased().hasPrefix(family.lowercased() + " ")
    }

    static func isSelected(family: String, grade: String, in text: String) -> Bool {
        let wanted = value(family: family, grade: grade)
        return items(text).contains { $0.caseInsensitiveCompare(wanted) == .orderedSame }
    }

    /// Choosing a selected value removes it; another grade of the same family replaces it;
    /// a new family is added to the combination.
    static func apply(family: String, grade: String, to text: String) -> String {
        let wanted = value(family: family, grade: grade)
        var list = items(text)
        if let index = list.firstIndex(where: { $0.caseInsensitiveCompare(wanted) == .orderedSame }) {
            list.remove(at: index)
        } else if let index = list.firstIndex(where: { belongs($0, to: family) }) {
            list[index] = wanted
        } else {
            list.append(wanted)
        }
        return list.joined(separator: " + ")
    }
}

/// T-stops offered on the DIAPH field: full stops and their thirds.
enum Aperture {
    static let fullStops = ["1", "1.4", "2", "2.8", "4", "5.6", "8", "11", "16", "22"]
    static var rows: [[String]] {
        fullStops.map { stop in stop == fullStops.last ? [stop] : [stop, "\(stop) ⅓", "\(stop) ⅔"] }
    }
}

enum KitCoding {
    static func encode<T: Encodable>(_ value: T) -> Data? { try? JSONEncoder().encode(value) }
    static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
