import Foundation

@MainActor enum SampleData {
    static func load(into repository: CameraLogRepository) throws {
        let production = try repository.addProduction(name: "LES OMBRES")
        do {
            let date = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 24))!
            let day = try repository.addDay(to: production, number: 12, date: date,
                location: "Paris — Plateau 3", unit: "Unit A")
            let camera = try repository.addCamera(to: production, name: "A", manufacturer: "ARRI", model: "Alexa 35")
            let report = try repository.addReport(to: day, camera: camera)

            var draft = SheetDraft()
            draft[.scene] = "24"; draft[.shot] = "03"; draft[.roll] = "A004"
            draft[.lens] = "50mm"; draft[.filters] = "1/8 BPM"; draft[.iso] = "800"; draft[.whiteBalance] = "5600"
            let sheet = try repository.saveSheet(draft, sheet: nil, in: report)
            try repository.addNextTake(to: sheet)
            let circled = try repository.addNextTake(to: sheet)
            try repository.updateTake(circled, label: "", statuses: [TakeStatus.good.rawValue], notes: "")
            try repository.toggleCircle(circled)
            // A lens change on the sheet applies to the next take only.
            draft[.lens] = "75mm"; draft[.filters] = ""
            try repository.saveSheet(draft, sheet: sheet, in: report)
            try repository.addNextTake(to: sheet)

            var next = SheetDraft()
            next[.scene] = "24"; next[.shot] = "04"; next[.roll] = "A004"
            next[.lens] = "35mm"; next[.filters] = "ND 0.6"; next[.iso] = "800"; next[.whiteBalance] = "5600"
            try repository.addNextTake(to: repository.saveSheet(next, sheet: nil, in: report))
        } catch {
            // Do not leave an incomplete demonstration mixed with real productions.
            try? repository.deleteProduction(production)
            throw error
        }
    }
}
