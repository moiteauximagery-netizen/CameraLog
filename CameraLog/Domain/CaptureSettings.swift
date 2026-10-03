import Foundation

/// Value snapshots keep historic takes independent from subsequent camera edits.
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

struct TakeDraft {
    var scene = "1"
    var shot = "01"
    var number = 1
    var settings = CaptureSettings()
    var statuses: [TakeStatus] = []
    var clipName = ""
    var fileName = ""
    var tcIn = ""
    var tcOut = ""
    var notes = ""
    var technicalNotes = ""
    var cameraNotes = ""
}

enum SmartFill {
    /// Caller scopes history to one report. Personal take data never carries over.
    static func next(after previous: TakeDraft?, defaults: CaptureSettings) -> TakeDraft {
        var draft = TakeDraft()
        draft.settings = previous?.settings ?? defaults
        if let previous {
            draft.scene = previous.scene
            draft.shot = previous.shot
            draft.number = previous.number + 1
        }
        return draft
    }
}

enum LogError: LocalizedError {
    case invalid(String)
    case duplicateTake
    var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        case .duplicateTake: return "Cette scène / plan / prise existe déjà sur ce roll."
        }
    }
}
