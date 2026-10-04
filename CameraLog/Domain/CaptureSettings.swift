import Foundation

/// Schema 1 settings snapshot. Frozen: SchemaV1 stores this exact type, so changing it would
/// prevent stores created by version 1 from being recognised. New takes use `ShotSheet.settings`.
struct CaptureSettings: Codable, Equatable {
    var lensName = ""
    var focalLengthMM: Double?
    var lensSerialNumber = ""
    var filters: [String] = []
    var iso = 800
    var exposureIndex: Int?
    var fps = 24.0
    var shutterAngle = 180.0
    var shutterSpeed = ""
    var whiteBalance = 5600
    var tint = 0
    var tStop: Double?
    var focusDistanceMeters: Double?
    var nd = ""
    var codec = ""
    var resolution = ""
    var aspectRatio = ""
    var recordingFormat = ""
    var lut = ""
    var gamma = ""
    var colorSpace = ""
    // Future hardware adapters may populate these without changing the UI contract.
    var metadataSource = "manual"
    var opticalMetadata: [String: String] = [:]
}

enum TakeStatus: String, Codable, CaseIterable, Identifiable {
    case good = "Good", circle = "Circle", ng = "NG", mos = "MOS"
    case vfx = "VFX", pickup = "Pick-up", wild = "Wild", test = "Test"
    var id: String { rawValue }
}

enum LogError: LocalizedError {
    case invalid(String)
    case duplicateTake
    case duplicateSheet(String, String)
    var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        case .duplicateTake: return "Ce numéro de prise existe déjà dans cette fiche."
        case .duplicateSheet(let sheet, let roll): return "La fiche \(sheet) existe déjà sur le roll \(roll)."
        }
    }
}
