import Foundation

/// Fields of a shot sheet. Identification fields are stored on the sheet and its roll;
/// setting fields are stored as text keyed by `rawValue`, so an unknown value stays empty.
enum SheetField: String, CaseIterable, Identifiable {
    case scene, shot, roll, magazine
    case lens, tStop, filters, iso, whiteBalance, fps, shutter
    case lut, aspectRatio, format, resolution
    case lensHeight, focus, tilt

    var id: String { rawValue }
    /// Required to save a sheet.
    static let identification: [SheetField] = [.scene, .shot, .roll]
    /// Saved in the sheet settings and copied into each take snapshot.
    static let settings: [SheetField] = [.lens, .tStop, .filters, .iso, .whiteBalance, .fps, .shutter,
                                         .lut, .aspectRatio, .format, .resolution, .lensHeight, .focus, .tilt]
    /// Shown only while the VFX switch of the sheet is on.
    static let vfx: [SheetField] = [.lensHeight, .focus, .tilt]
    /// Offered from a project list (production settings).
    static let catalogLists: [SheetField] = [.lut, .aspectRatio, .format, .resolution]
    /// Boxes the production settings may hide. Scene, plan and roll always stay.
    static let hideable: [SheetField] = [.magazine, .lens, .tStop, .filters, .iso, .whiteBalance, .fps, .shutter,
                                         .lut, .aspectRatio, .format, .resolution]

    var title: String {
        switch self {
        case .scene: return "SCÈNE"
        case .shot: return "PLAN"
        case .roll: return "ROLL"
        case .magazine: return "MAG #"
        case .lens: return "OBJECTIF"
        case .tStop: return "DIAPH"
        case .filters: return "FILTRES"
        case .iso: return "ISO / EI"
        case .whiteBalance: return "TEMPÉRATURE · K"
        case .fps: return "FPS"
        case .shutter: return "SHUTTER · °"
        case .lut: return "LUT"
        case .aspectRatio: return "RATIO"
        case .format: return "FORMAT"
        case .resolution: return "RÉSOLUTION"
        case .lensHeight: return "HAUTEUR CAM"
        case .focus: return "POINT"
        case .tilt: return "TILT"
        }
    }

    var spokenName: String {
        switch self {
        case .scene: return "Scène"
        case .shot: return "Plan"
        case .roll: return "Roll"
        case .magazine: return "Magasin"
        case .lens: return "Objectif"
        case .tStop: return "Diaphragme"
        case .filters: return "Filtres"
        case .iso: return "ISO"
        case .whiteBalance: return "Température de couleur"
        case .fps: return "Images par seconde"
        case .shutter: return "Obturateur"
        case .lut: return "LUT"
        case .aspectRatio: return "Aspect ratio"
        case .format: return "Format"
        case .resolution: return "Résolution"
        case .lensHeight: return "Hauteur caméra"
        case .focus: return "Distance de mise au point"
        case .tilt: return "Inclinaison"
        }
    }
}

/// Editable state of one shot sheet. `values` holds only what the user typed or accepted;
/// `suggestions` are displayed greyed out and are never part of what a save writes.
struct SheetDraft: Equatable {
    var values: [SheetField: String] = [:]
    var notes = ""
    /// VFX switch: shows camera height, focus distance and tilt, and marks new takes VFX.
    var vfx = false
    static let vfxKey = "vfx"
    /// Boxes hidden by the production settings: never suggested nor accepted.
    var hiddenFields: Set<SheetField> = []
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
    func isShown(_ field: SheetField) -> Bool {
        !hiddenFields.contains(field) && (vfx || !SheetField.vfx.contains(field))
    }
    var pendingFields: [SheetField] { SheetField.allCases.filter { isPending($0) && isShown($0) } }

    mutating func accept(_ field: SheetField) {
        guard isPending(field), let text = suggestion(field) else { return }
        values[field] = text
    }

    /// Accepts every pending suggestion; values already typed are never replaced.
    mutating func acceptAll() {
        for field in pendingFields { accept(field) }
    }

    /// VFX values are saved only while the VFX switch is on.
    var settingsToSave: [String: String] {
        var result: [String: String] = [:]
        for field in SheetField.settings where !value(field).isEmpty {
            if SheetField.vfx.contains(field) && !vfx { continue }
            result[field.rawValue] = value(field)
        }
        if vfx { result[Self.vfxKey] = "1" }
        return result
    }

    /// Everything a save would write. Suggestions are deliberately absent.
    var savedContent: [String: String] {
        var result = settingsToSave
        for field in SheetField.identification + [.magazine] { result[field.rawValue] = value(field) }
        result["notes"] = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }
}

enum SmartFill {
    /// Values of the previous sheet of the same camera report, offered greyed out.
    /// The plan offered is the next one: 2 → 3, A → B.
    static func suggestions(scene: String, shot: String, roll: String, magazine: String = "",
                            settings: [String: String]) -> [SheetField: String] {
        var result: [SheetField: String] = [:]
        if !scene.isEmpty { result[.scene] = scene }
        if !magazine.isEmpty { result[.magazine] = magazine }
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

/// Lists offered on the sheet (LUT, ratio, format, resolution) and boxes hidden on sheets.
struct ProjectCatalog: Codable, Equatable {
    var lists: [String: [String]] = [:]
    var hidden: [String] = []
    /// VFX switch hidden on sheets.
    static let vfxBlock = "vfx"

    func list(_ field: SheetField) -> [String] { lists[field.rawValue] ?? [] }
    mutating func setList(_ values: [String], for field: SheetField) { lists[field.rawValue] = values }
    func isHidden(_ key: String) -> Bool { hidden.contains(key) }
    mutating func setHidden(_ key: String, _ isHidden: Bool) {
        hidden.removeAll { $0 == key }
        if isHidden { hidden.append(key) }
    }
}
