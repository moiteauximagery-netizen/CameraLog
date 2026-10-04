import Foundation

/// Camera report exports. CSV and JSON follow the ZoeLog files read by Pomfort Silverstack
/// (columns, value units, true/false, roll-wide clip integers, CRLF without final newline);
/// rows follow the card order of each roll and use the settings snapshot of each take.
enum ReportExport {
    static let csvColumns = ["Scene", "Date", "Camera", "Roll", "Take", "Clip", "Circled", "Lens", "Filters", "Stop",
                             "Focus", "Lens Height", "Color Temp", "FPS", "Shutter", "ISO", "Time Code", "Tilt",
                             "Lut", "Aspect Ratio", "Format", "Resolution", "Description", "Notes", "Origin Date",
                             "Take Origin"]

    /// One take of the export, already formatted.
    struct Row: Equatable {
        var values: [String: String]
        subscript(column: String) -> String { values[column] ?? "" }
    }

    /// Reports of one day, in camera order, keeping only those with sheets.
    static func reports(of day: ShootDay, camera: Camera? = nil) -> [CameraReport] {
        day.reports.filter { $0.day?.id == day.id && (camera == nil || $0.camera?.id == camera?.id) }
            .sorted { ($0.camera?.name ?? "") < ($1.camera?.name ?? "") }
    }

    static func rolls(of report: CameraReport) -> [Roll] {
        report.orderedRolls.filter { !$0.clipSequence.isEmpty }
    }

    // MARK: Value formats

    /// « 14 » + « A » → « 14A » ; « 24 » + « 3 » → « 24/3 ».
    static func sceneLabel(scene: String, shot: String) -> String {
        let shot = shot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = shot.first else { return scene }
        return first.isLetter ? scene + shot : "\(scene)/\(shot)"
    }

    private static func isNumber(_ text: String) -> Bool {
        Double(text.replacingOccurrences(of: ",", with: ".")) != nil
    }

    static func lens(_ value: String) -> String {
        let text = value.trimmingCharacters(in: .whitespaces)
        if isNumber(text) { return text + "mm" }
        if text.lowercased().hasSuffix(" mm"), isNumber(String(text.dropLast(3))) { return String(text.dropLast(3)) + "mm" }
        return text
    }

    static func stop(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "⅓", with: "1/3").replacingOccurrences(of: "⅔", with: "2/3")
        guard !text.isEmpty else { return "" }
        if text.first == "t" || text.first == "T" { text.removeFirst() }
        return "T" + text.trimmingCharacters(in: .whitespaces)
    }

    private static func suffixed(_ value: String, _ unit: String) -> String {
        let text = value.trimmingCharacters(in: .whitespaces)
        return isNumber(text) ? text + unit : text
    }

    static func settings(_ values: [String: String], degree: String = " degrees") -> [String: String] {
        func value(_ field: SheetField) -> String { values[field.rawValue] ?? "" }
        return ["Lens": lens(value(.lens)), "Filters": value(.filters), "Stop": stop(value(.tStop)),
                "Color Temp": suffixed(value(.whiteBalance), "K"), "FPS": suffixed(value(.fps), "fps"),
                "Shutter": suffixed(value(.shutter), degree), "ISO": suffixed(value(.iso), "EI"),
                "Lut": value(.lut), "Aspect Ratio": value(.aspectRatio), "Format": value(.format),
                "Resolution": value(.resolution), "Focus": value(.focus), "Lens Height": value(.lensHeight),
                "Tilt": value(.tilt)]
    }

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    // MARK: Rows

    static func rows(day: ShootDay, reports: [CameraReport]) -> [Row] {
        var result: [Row] = []
        for report in reports {
            let camera = report.camera?.name ?? ""
            for roll in rolls(of: report) {
                for (index, take) in roll.clipSequence.enumerated() {
                    let sheet = take.sheet
                    var values = settings(take.snapshot)
                    values["Scene"] = sceneLabel(scene: take.scene, shot: take.shot)
                    values["Date"] = dayFormatter.string(from: day.date)
                    values["Camera"] = camera
                    values["Roll"] = roll.name
                    values["Take"] = take.number > 0 || !take.labelText.isEmpty
                        ? TakeLabel.title(number: take.number, label: take.labelText) : ""
                    values["Clip"] = String(index + 1)
                    values["Circled"] = take.isCircle ? "true" : "false"
                    values["Description"] = sheet?.notes ?? ""
                    values["Notes"] = take.notes
                    values["Origin Date"] = timestamp(sheet?.createdAt ?? take.createdAt)
                    values["Take Origin"] = timestamp(take.createdAt)
                    result.append(Row(values: values))
                }
            }
        }
        return result
    }

    // MARK: CSV

    static func csvField(_ value: String) -> String {
        value.isEmpty ? "" : "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func csv(day: ShootDay, reports: [CameraReport]) -> String {
        let header = csvColumns.map(csvField).joined(separator: ",")
        let lines = rows(day: day, reports: reports).map { row in
            csvColumns.map { csvField(row[$0]) }.joined(separator: ",")
        }
        return ([header] + lines).joined(separator: "\r\n")
    }

    // MARK: JSON

    static func json(production: Production?, day: ShootDay, reports: [CameraReport]) throws -> Data {
        var rollReports: [[String: Any]] = []
        for report in reports {
            let camera = report.camera?.name ?? ""
            for roll in rolls(of: report) {
                let numbers = roll.clipNumbers
                var entries: [[String: Any]] = []
                var seen = Set<UUID>()
                for take in roll.clipSequence {
                    guard let sheet = take.sheet, !seen.contains(sheet.id) else { continue }
                    seen.insert(sheet.id)
                    let logData = settings(sheet.settings, degree: "∢").filter { !$0.value.isEmpty }
                    let takes: [[String: Any]] = sheet.orderedTakes.filter { $0.roll?.id == roll.id }.map { take in
                        ["name": take.number > 0 || !take.labelText.isEmpty
                            ? TakeLabel.title(number: take.number, label: take.labelText) : "",
                         "circled": take.isCircle,
                         "clip": numbers[take.id] ?? 0,
                         "origin": timestamp(take.createdAt)]
                    }
                    entries.append(["slate": NSNull(), "scene": sceneLabel(scene: sheet.scene, shot: sheet.shot),
                                    "episode": NSNull(), "timecode": NSNull(),
                                    "origin_date": timestamp(sheet.createdAt),
                                    "report_metadata": [String: String](), "log_data": logData, "takes": takes])
                }
                rollReports.append(["roll": roll.name, "camera": camera,
                                    "report_metadata": roll.card.isEmpty ? [String: String]() : ["magazine": roll.card],
                                    "shooting_date": dayFormatter.string(from: day.date), "entries": entries])
            }
        }
        let document: [String: Any] = ["production_title": production?.name ?? "",
                                       "production_metadata": [String: String](), "reports": rollReports]
        return try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    // MARK: Files

    /// « LES OMBRES-DAY12-2026-09-24-CAM-A » without characters that file systems reject.
    static func baseName(production: Production?, day: ShootDay, camera: Camera?) -> String {
        var parts = [production?.name ?? "CameraLog", "DAY\(day.number)", dayFormatter.string(from: day.date)]
        if let camera { parts.append("CAM-\(camera.name)") }
        let raw = parts.joined(separator: "-")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        return String(raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }
}
