import Foundation

/// Fields of a shot sheet. Identification fields are stored on the sheet and its roll;
/// setting fields are stored as text keyed by `rawValue`, so an unknown value stays empty.
enum SheetField: String, CaseIterable, Identifiable {
    case scene, shot, roll
    case lens, tStop, filters, iso, whiteBalance, fps, shutter

    var id: String { rawValue }
    static let identification: [SheetField] = [.scene, .shot, .roll]
    static let settings: [SheetField] = [.lens, .tStop, .filters, .iso, .whiteBalance, .fps, .shutter]

    var title: String {
        switch self {
        case .scene: return "SCÈNE"
        case .shot: return "PLAN"
        case .roll: return "ROLL"
        case .lens: return "OBJECTIF"
        case .tStop: return "DIAPH"
        case .filters: return "FILTRES"
        case .iso: return "ISO / EI"
        case .whiteBalance: return "TEMPÉRATURE · K"
        case .fps: return "FPS"
        case .shutter: return "SHUTTER · °"
        }
    }

    var spokenName: String {
        switch self {
        case .scene: return "Scène"
        case .shot: return "Plan"
        case .roll: return "Roll"
        case .lens: return "Objectif"
        case .tStop: return "Diaphragme"
        case .filters: return "Filtres"
        case .iso: return "ISO"
        case .whiteBalance: return "Température de couleur"
        case .fps: return "Images par seconde"
        case .shutter: return "Obturateur"
        }
    }
}

/// Editable state of one shot sheet. `values` holds only what the user typed or accepted;
/// `suggestions` are displayed greyed out and are never part of what a save writes.
struct SheetDraft: Equatable {
    var values: [SheetField: String] = [:]
    var notes = ""
    var suggestions: [SheetField: String] = [:]
    var suggestionSource = ""

    subscript(field: SheetField) -> String {
        get { values[field] ?? "" }
        set { values[field] = newValue }
    }

    func value(_ field: SheetField) -> String {
        self[field].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func suggestion(_ field: SheetField) -> String? {
        guard let text = suggestions[field]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }

    /// A suggestion is pending while its field is really empty.
    func isPending(_ field: SheetField) -> Bool { value(field).isEmpty && suggestion(field) != nil }
    var pendingFields: [SheetField] { SheetField.allCases.filter(isPending) }

    mutating func accept(_ field: SheetField) {
        guard isPending(field), let text = suggestion(field) else { return }
        values[field] = text
    }

    /// Accepts every pending suggestion; values already typed are never replaced.
    mutating func acceptAll() {
        for field in pendingFields { accept(field) }
    }

    var settingsToSave: [String: String] {
        var result: [String: String] = [:]
        for field in SheetField.settings where !value(field).isEmpty { result[field.rawValue] = value(field) }
        return result
    }

    /// Everything a save would write. Suggestions are deliberately absent.
    var savedContent: [String: String] {
        var result = settingsToSave
        for field in SheetField.identification { result[field.rawValue] = value(field) }
        result["notes"] = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }
}

enum SmartFill {
    /// Values of the previous sheet of the same camera report, offered greyed out.
    /// The plan offered is the next one: 2 → 3, A → B.
    static func suggestions(scene: String, shot: String, roll: String,
                            settings: [String: String]) -> [SheetField: String] {
        var result: [SheetField: String] = [:]
        if !scene.isEmpty { result[.scene] = scene }
        if let next = ShotIncrement.next(after: shot) { result[.shot] = next }
        if !roll.isEmpty { result[.roll] = roll }
        for field in SheetField.settings {
            if let value = settings[field.rawValue], !value.isEmpty { result[field] = value }
        }
        return result
    }
}

enum SheetValidation {
    /// Checks numeric fields and returns their normalised text. Free-text fields are kept as typed.
    static func normalizedSettings(_ settings: [String: String]) throws -> [String: String] {
        var result = settings
        if let iso = settings[SheetField.iso.rawValue] {
            result[SheetField.iso.rawValue] = try positiveInteger(iso, "L’ISO")
        }
        if let kelvin = settings[SheetField.whiteBalance.rawValue] {
            let digits = kelvin.replacingOccurrences(of: "k", with: "", options: .caseInsensitive)
            result[SheetField.whiteBalance.rawValue] = try positiveInteger(digits, "La température")
        }
        if let fps = settings[SheetField.fps.rawValue] {
            guard let value = number(fps), value > 0, value <= 2000 else {
                throw LogError.invalid("Le FPS doit être un nombre positif.")
            }
            result[SheetField.fps.rawValue] = format(value)
        }
        if let shutter = settings[SheetField.shutter.rawValue] {
            guard let value = number(shutter.replacingOccurrences(of: "°", with: "")), value > 0, value <= 360 else {
                throw LogError.invalid("Le shutter doit être un angle compris entre 0 et 360°.")
            }
            result[SheetField.shutter.rawValue] = format(value)
        }
        return result
    }

    private static func positiveInteger(_ text: String, _ label: String) throws -> String {
        guard let value = Int(text.filter { !$0.isWhitespace }), value > 0, value < 1_000_000 else {
            throw LogError.invalid("\(label) doit être un nombre entier positif.")
        }
        return String(value)
    }

    private static func number(_ text: String) -> Double? {
        Double(text.filter { !$0.isWhitespace }.replacingOccurrences(of: ",", with: "."))
    }

    static func format(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1_000_000 ? String(Int(value)) : String(value)
    }
}

/// Sheet settings are stored as JSON text to keep unknown keys and empty values explicit.
enum SettingsCoding {
    static func encode(_ values: [String: String]) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(values)
    }

    static func decode(_ data: Data?) -> [String: String]? {
        guard let data else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }
}

extension CaptureSettings {
    /// Read-only view of a take recorded before shot sheets existed. Reproduces stored values only.
    var sheetValues: [String: String] {
        var result: [String: String] = [:]
        let lens = lensName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !lens.isEmpty { result[SheetField.lens.rawValue] = lens }
        else if let focalLengthMM { result[SheetField.lens.rawValue] = "\(SheetValidation.format(focalLengthMM)) mm" }
        if let tStop { result[SheetField.tStop.rawValue] = SheetValidation.format(tStop) }
        if !filters.isEmpty { result[SheetField.filters.rawValue] = filters.joined(separator: " + ") }
        result[SheetField.iso.rawValue] = String(iso)
        result[SheetField.whiteBalance.rawValue] = String(whiteBalance)
        result[SheetField.fps.rawValue] = SheetValidation.format(fps)
        result[SheetField.shutter.rawValue] = SheetValidation.format(shutterAngle)
        return result
    }
}
