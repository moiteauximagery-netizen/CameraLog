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
            let roll = try repository.addRoll(to: report, name: "A004")
            for index in 1...4 {
                var draft = TakeDraft()
                draft.scene = "24"; draft.shot = index == 4 ? "04" : "03"
                draft.number = index == 4 ? 1 : index
                draft.settings.lensName = index == 4 ? "35mm" : (index == 3 ? "75mm" : "50mm")
                draft.settings.filters = index == 4 ? ["ND 0.6"] : (index == 3 ? [] : ["1/8 BPM"])
                draft.statuses = index == 2 ? [.good, .circle] : []
                try repository.addTake(to: roll, draft: draft)
            }
        } catch {
            // Do not leave an incomplete demonstration mixed with real productions.
            try? repository.deleteProduction(production)
            throw error
        }
    }
}
