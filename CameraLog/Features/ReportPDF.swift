import UIKit

/// Printable camera report: A4 landscape, one table per roll in card order, circled takes circled.
enum ReportPDF {
    private static let page = CGRect(x: 0, y: 0, width: 842, height: 595)
    private static let margin: CGFloat = 28
    private static let rowHeight: CGFloat = 17

    private struct Column {
        let title: String
        let width: CGFloat
        let value: (TakeEntry, Int) -> String
    }

    private static func value(_ take: TakeEntry, _ field: SheetField) -> String { take.snapshot[field.rawValue] ?? "" }

    private static let columns: [Column] = [
        Column(title: "CLIP", width: 44) { _, clip in ClipCode.code(clip) },
        Column(title: "SCÈNE", width: 62) { take, _ in ReportExport.sceneLabel(scene: take.scene, shot: take.shot) },
        Column(title: "PRISE", width: 50) { take, _ in TakeLabel.title(number: take.number, label: take.labelText) },
        Column(title: "OBJECTIF", width: 70) { take, _ in ReportPDF.value(take, .lens) },
        Column(title: "DIAPH", width: 52) { take, _ in ReportPDF.value(take, .tStop) },
        Column(title: "FILTRES", width: 120) { take, _ in ReportPDF.value(take, .filters) },
        Column(title: "ISO", width: 44) { take, _ in ReportPDF.value(take, .iso) },
        Column(title: "K", width: 44) { take, _ in ReportPDF.value(take, .whiteBalance) },
        Column(title: "FPS", width: 40) { take, _ in ReportPDF.value(take, .fps) },
        Column(title: "SHUTTER", width: 52) { take, _ in ReportPDF.value(take, .shutter) },
        Column(title: "NOTES", width: 0) { take, _ in ReportPDF.notes(take) }
    ]

    /// Notes, then VFX data and image settings recorded with the take.
    static func notes(_ take: TakeEntry) -> String {
        let s = take.snapshot
        func labelled(_ field: SheetField, _ title: String) -> String? {
            guard let text = s[field.rawValue], !text.isEmpty else { return nil }
            return "\(title) \(text)"
        }
        let vfx = [labelled(.lensHeight, "H"), labelled(.focus, "Pt"), labelled(.tilt, "Tilt")].compactMap { $0 }
        let image = [labelled(.lut, "LUT"), labelled(.aspectRatio, "Ratio"), labelled(.format, "Fmt"),
                     labelled(.resolution, "Rés")].compactMap { $0 }
        var parts = [take.notes, take.sheet?.notes ?? ""].filter { !$0.isEmpty }
        if !vfx.isEmpty { parts.append("VFX " + vfx.joined(separator: " ")) }
        parts += image
        return parts.joined(separator: " · ")
    }

    /// Camera color for fills, and a darker shade readable on paper for text and lines.
    private static func cameraFill(_ hue: Double?) -> UIColor {
        hue.map { UIColor(hue: $0, saturation: 0.35, brightness: 1, alpha: 1) } ?? UIColor(white: 0.9, alpha: 1)
    }
    private static func cameraInk(_ hue: Double?) -> UIColor {
        hue.map { UIColor(hue: $0, saturation: 0.9, brightness: 0.55, alpha: 1) } ?? .black
    }

    private static func font(_ size: CGFloat, _ weight: UIFont.Weight = .regular) -> UIFont {
        .monospacedDigitSystemFont(ofSize: size, weight: weight)
    }

    private static func draw(_ text: String, at rect: CGRect, size: CGFloat = 9, weight: UIFont.Weight = .regular,
                             color: UIColor = .black, alignment: NSTextAlignment = .left) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        style.alignment = alignment
        (text as NSString).draw(in: rect, withAttributes: [.font: font(size, weight), .foregroundColor: color,
                                                          .paragraphStyle: style])
    }

    static func make(production: Production?, day: ShootDay, reports: [CameraReport]) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: page, format: UIGraphicsPDFRendererFormat())
        let dateText = day.date.formatted(date: .long, time: .omitted)
        let generated = Date().formatted(date: .abbreviated, time: .shortened)
        return renderer.pdfData { context in
            var y: CGFloat = 0
            var pageNumber = 0
            let width = page.width - 2 * margin
            let notesWidth = width - columns.reduce(0) { $0 + $1.width }

            func footer() {
                let text = "\(production?.name ?? "") · DAY \(day.number) · généré par CameraLog le \(generated) · page \(pageNumber)"
                draw(text, at: CGRect(x: margin, y: page.height - margin + 6, width: width, height: 12),
                     size: 7, color: .darkGray)
            }
            func newPage() {
                if pageNumber > 0 { footer() }
                context.beginPage()
                pageNumber += 1
                y = margin
            }
            func tableHeader() {
                var x = margin
                for column in columns {
                    let w = column.width == 0 ? notesWidth : column.width
                    draw(column.title, at: CGRect(x: x + 2, y: y + 3, width: w - 4, height: 11), size: 7, weight: .semibold,
                         color: .darkGray)
                    x += w
                }
                y += 14
                UIColor.black.setFill()
                UIRectFill(CGRect(x: margin, y: y, width: width, height: 0.5))
            }
            func ensure(_ height: CGFloat, repeatHeader: Bool) {
                guard y + height > page.height - margin - 8 else { return }
                newPage()
                if repeatHeader { tableHeader() }
            }

            newPage()
            draw(production?.name ?? "Rapport caméra", at: CGRect(x: margin, y: y, width: width * 0.6, height: 24),
                 size: 18, weight: .bold)
            draw("RAPPORT CAMÉRA", at: CGRect(x: margin + width * 0.6, y: y + 4, width: width * 0.4, height: 16),
                 size: 11, weight: .semibold, alignment: .right)
            y += 26
            let place = [day.location, day.unit].filter { !$0.isEmpty }.joined(separator: " · ")
            draw(["DAY \(day.number)", dateText, place].filter { !$0.isEmpty }.joined(separator: "   ·   "),
                 at: CGRect(x: margin, y: y, width: width, height: 14), size: 11, weight: .medium)
            y += 16
            var team: [String] = []
            if let director = production?.director, !director.isEmpty { team.append("Réal. \(director)") }
            if let dop = production?.cinematographer, !dop.isEmpty { team.append("Image \(dop)") }
            if !team.isEmpty {
                draw(team.joined(separator: "   ·   "), at: CGRect(x: margin, y: y, width: width, height: 12),
                     size: 9, color: .darkGray)
                y += 14
            }
            if !day.notes.isEmpty {
                draw(day.notes, at: CGRect(x: margin, y: y, width: width, height: 12), size: 9, color: .darkGray)
                y += 14
            }

            for report in reports {
                let rolls = ReportExport.rolls(of: report)
                guard !rolls.isEmpty else { continue }
                ensure(60, repeatHeader: false)
                y += 8
                let camera = report.camera
                let body = [camera?.manufacturer ?? "", camera?.model ?? "",
                            (camera?.serialNumber ?? "").isEmpty ? "" : "S/N \(camera?.serialNumber ?? "")"]
                    .filter { !$0.isEmpty }.joined(separator: " ")
                if let hue = camera?.colorHue {
                    UIColor(hue: hue, saturation: 0.72, brightness: 0.95, alpha: 1).setFill()
                    UIBezierPath(roundedRect: CGRect(x: margin, y: y + 1, width: 12, height: 14), cornerRadius: 3).fill()
                }
                let ink = cameraInk(camera?.colorHue)
                let fill = cameraFill(camera?.colorHue)
                draw("CAM \(camera?.name ?? "—")" + (body.isEmpty ? "" : "  ·  \(body)"),
                     at: CGRect(x: margin + (camera?.colorHue == nil ? 0 : 18), y: y, width: width, height: 16),
                     size: 13, weight: .bold, color: ink)
                y += 20

                for roll in rolls {
                    let sequence = roll.clipSequence
                    ensure(rowHeight * 3 + 20, repeatHeader: false)
                    fill.setFill()
                    UIRectFill(CGRect(x: margin, y: y, width: width, height: 18))
                    let details = ["\(sequence.count) clip(s) · C001 → \(ClipCode.code(sequence.count))",
                                   roll.card.isEmpty ? "" : "Mag # \(roll.card)",
                                   roll.reel.isEmpty ? "" : "Reel \(roll.reel)"].filter { !$0.isEmpty }
                    draw("ROLL \(roll.name)   ·   " + details.joined(separator: "   ·   "),
                         at: CGRect(x: margin + 6, y: y + 3, width: width - 12, height: 13), size: 10, weight: .semibold,
                         color: ink)
                    y += 20
                    tableHeader()
                    for (index, take) in sequence.enumerated() {
                        ensure(rowHeight, repeatHeader: true)
                        let unusable = take.number == 0 || take.labelText.uppercased() == TakeLabel.falseClip
                        var x = margin
                        for (columnIndex, column) in columns.enumerated() {
                            let w = column.width == 0 ? notesWidth : column.width
                            let text = column.value(take, index + 1)
                            let rect = CGRect(x: x + 2, y: y + 3, width: w - 4, height: 12)
                            draw(text, at: rect, size: columnIndex == 2 ? 10 : 9,
                                 weight: columnIndex <= 2 ? .semibold : .regular,
                                 color: unusable ? .gray : .black)
                            if columnIndex == 2 && take.isCircle {
                                let textWidth = (text as NSString).size(withAttributes: [.font: font(10, .semibold)]).width
                                let circle = CGRect(x: x - 1, y: y + 0.5, width: max(textWidth + 8, 16), height: 16)
                                ink.setStroke()
                                let path = UIBezierPath(ovalIn: circle)
                                path.lineWidth = 1.2
                                path.stroke()
                            }
                            x += w
                        }
                        y += rowHeight
                        UIColor(white: 0.85, alpha: 1).setFill()
                        UIRectFill(CGRect(x: margin, y: y, width: width, height: 0.5))
                    }
                    y += 6
                }

                let circled = rolls.flatMap(\.clipSequence).filter(\.isCircle)
                let byScene = Dictionary(grouping: circled) { ReportExport.sceneLabel(scene: $0.scene, shot: $0.shot) }
                    .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
                    .map { "\($0.key) : \($0.value.map { TakeLabel.title(number: $0.number, label: $0.labelText) }.joined(separator: ", "))" }
                ensure(16, repeatHeader: false)
                draw("Cerclées — " + (byScene.isEmpty ? "aucune" : byScene.joined(separator: "   ·   ")),
                     at: CGRect(x: margin, y: y, width: width, height: 13), size: 9, weight: .medium)
                y += 16
            }
            footer()
        }
    }
}
