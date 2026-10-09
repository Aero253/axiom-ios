import AppIntents
import Foundation

// MARK: - Siri and Shortcuts: ask Axiom without opening it
// "When's my next report in Axiom?", "Where am I flying tomorrow in Axiom?", "What's my next alarm in Axiom?",
// "Add a glass of water in Axiom". The answers come from what the dashboard last saved, so they work offline.

/// Spoken wording for duties: Bangkok times (like the rest of Axiom), airport names instead of codes.
enum Speak {
    static let bkk = TimeZone(identifier: "Asia/Bangkok")!

    /// Names Siri can say. Places in the saved data come first, then Thai Lion Air's usual airports.
    static let airports: [String: String] = [
        "DMK": "Don Mueang", "BKK": "Suvarnabhumi", "CNX": "Chiang Mai", "CEI": "Chiang Rai", "HKT": "Phuket", "KBV": "Krabi",
        "HDY": "Hat Yai", "URT": "Surat Thani", "USM": "Samui", "UTH": "Udon Thani", "KKC": "Khon Kaen", "UBP": "Ubon Ratchathani",
        "NST": "Nakhon Si Thammarat", "NAW": "Narathiwat", "TST": "Trang", "PHS": "Phitsanulok", "KOP": "Nakhon Phanom",
        "LOE": "Loei", "ROI": "Roi Et", "SNO": "Sakon Nakhon", "NNT": "Nan", "MAQ": "Mae Sot", "BFV": "Buriram", "HHQ": "Hua Hin",
        "UTP": "U-Tapao", "SIN": "Singapore", "KUL": "Kuala Lumpur", "PEN": "Penang", "SGN": "Ho Chi Minh City", "HAN": "Hanoi",
        "DAD": "Da Nang", "RGN": "Yangon", "PNH": "Phnom Penh", "REP": "Siem Reap", "VTE": "Vientiane", "LPQ": "Luang Prabang",
        "CGK": "Jakarta", "DPS": "Bali", "MNL": "Manila", "HKG": "Hong Kong", "MFM": "Macau", "TPE": "Taipei", "NRT": "Tokyo Narita",
        "HND": "Tokyo Haneda", "KIX": "Osaka", "ICN": "Seoul", "CAN": "Guangzhou", "SZX": "Shenzhen", "PVG": "Shanghai",
        "CTU": "Chengdu", "KMG": "Kunming", "CKG": "Chongqing", "XIY": "Xi'an", "CSX": "Changsha", "WUH": "Wuhan",
        "DEL": "Delhi", "BOM": "Mumbai", "BLR": "Bengaluru", "MAA": "Chennai", "CCU": "Kolkata", "GAY": "Gaya", "VNS": "Varanasi",
        "KTM": "Kathmandu", "DAC": "Dhaka", "CMB": "Colombo", "MLE": "Malé"]

    static func place(_ code: String, in p: Payload?) -> String {
        if let n = p?.lays?.first(where: { $0.to == code })?.name, !n.isEmpty { return n }
        if let n = p?.world?.first(where: { $0.code == code })?.name, !n.isEmpty, n != code { return n }
        if let n = p?.sun?.first(where: { $0.code == code })?.name, !n.isEmpty, n != code { return n }
        if let n = airports[code] { return n }
        return code.map(String.init).joined(separator: " ")   // say unknown codes letter by letter
    }

    static func time(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.timeZone = bkk; f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    /// "today", "tomorrow", "on Saturday", "on Monday 19 October"
    static func day(_ d: Date, now: Date) -> String {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = bkk
        let n = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: d)).day ?? 0
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.timeZone = bkk
        if n == 0 { return "today" }
        if n == 1 { return "tomorrow" }
        f.dateFormat = n < 7 ? "EEEE" : "EEEE d MMMM"
        return "on " + f.string(from: d)
    }

    /// "9 hours 20 minutes"
    static func span(_ seconds: TimeInterval) -> String {
        let m = max(0, Int((seconds / 60).rounded(.up)))
        let d = m / 1440, h = (m % 1440) / 60, mm = m % 60
        var parts: [String] = []
        if d > 0 { parts.append("\(d) day\(d == 1 ? "" : "s")") }
        if h > 0 { parts.append("\(h) hour\(h == 1 ? "" : "s")") }
        if mm > 0 && d == 0 { parts.append("\(mm) minute\(mm == 1 ? "" : "s")") }
        return parts.isEmpty ? "less than a minute" : parts.joined(separator: " ")
    }

    /// "SL770 to Chiang Mai, then SL771 back to Don Mueang"
    static func flights(_ duty: Duty, in p: Payload?) -> String {
        let legs = duty.legs ?? []
        guard !legs.isEmpty else { return "" }
        let base = p?.base ?? "DMK"
        return legs.enumerated().map { i, l in
            let to = (l.to == base && i > 0) ? "back to \(place(l.to, in: p))" : "to \(place(l.to, in: p))"
            return [l.flt, to].compactMap { $0 }.joined(separator: " ")
        }.joined(separator: legs.count > 2 ? ", " : ", then ")
    }

    static func dutyName(_ duty: Duty) -> String {
        switch duty.type {
        case "HSBY": return "home standby"
        case "ASBY": return "airport standby"
        case "RES": return "reserve"
        default: return duty.what.lowercased()
        }
    }

    static let noRoster = "Your roster isn't in Axiom yet. Open Axiom and import your eCrew PDF."

    static func nextReport(_ p: Payload?, now: Date = Date()) -> String {
        guard let p = p else { return "Open Axiom once so I can read your roster." }
        if p.demo { return noRoster }
        guard let st = p.status(at: now) else { return "There's no duty ahead on your roster." }
        let d = st.duty
        if st.onDuty {
            var s = "You're on duty now, off at \(time(d.offDate))."
            if let next = p.duties.filter({ $0.rep > d.off }).min(by: { $0.rep < $1.rep }) {
                s += " After that, " + sentence(for: next, in: p, now: now, lead: "you report")
            }
            return s
        }
        return sentence(for: d, in: p, now: now, lead: "Your next report is") + " That's in \(span(st.target.timeIntervalSince(now)))."
    }

    private static func sentence(for d: Duty, in p: Payload, now: Date, lead: String) -> String {
        let when = "\(day(d.repDate, now: now)) at \(time(d.repDate))"
        if d.type == "FDP" {
            let f = flights(d, in: p)
            return "\(lead) \(when)\(f.isEmpty ? "" : ", \(f)")."
        }
        return lead == "Your next report is" ? "Your next duty is \(dutyName(d)) \(when)." : "\(dutyName(d)) \(when)."
    }

    static func tomorrow(_ p: Payload?, now: Date = Date()) -> String {
        guard let p = p else { return "Open Axiom once so I can read your roster." }
        if p.demo { return noRoster }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = bkk
        guard let t = cal.date(byAdding: .day, value: 1, to: now) else { return "" }
        let iso = Shared.todayISO(t)
        let today = p.duties.filter { $0.date == iso }.sorted { $0.rep < $1.rep }
        if let d = today.first {
            if d.type == "FDP" {
                let f = flights(d, in: p)
                var s = "Tomorrow you report at \(time(d.repDate))" + (f.isEmpty ? "." : " for \(f).")
                s += " Off duty at \(time(d.offDate))."
                if d.away == true, let last = d.legs?.last?.to { s += " You stay the night in \(place(last, in: p))." }
                return s
            }
            return "Tomorrow you're on \(dutyName(d)) from \(time(d.repDate)) to \(time(d.offDate))."
        }
        if let day = p.days?.first(where: { $0.date == iso }) {
            switch day.type {
            case "OFF": return "Tomorrow is a day off."
            case "AL": return "Tomorrow you're on annual leave."
            case "RST": return "Tomorrow is a rest day."
            case "": return "Nothing on your roster tomorrow."
            default: return "Tomorrow: \(day.txt)."
            }
        }
        return "Nothing on your roster tomorrow."
    }

    static func nextAlarm(_ p: Payload?, now: Date = Date()) -> String {
        guard let set = p?.alarms, let n = set.next(after: now) else { return "You have no alarms on." }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "HH:mm"   // alarms follow the phone's own clock
        var cal = Calendar.current; cal.timeZone = .current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: n.at)).day ?? 0
        let df = DateFormatter(); df.locale = Locale(identifier: "en_GB"); df.dateFormat = "EEEE"
        let when = days == 0 ? "today" : days == 1 ? "tomorrow" : "on " + df.string(from: n.at)
        return "Your next alarm is \(when) at \(f.string(from: n.at)). That's in \(span(n.at.timeIntervalSince(now)))."
    }

    static func water(_ w: Water) -> String {
        if w.n >= w.goal { return "Added. That's \(w.n) glasses today, goal reached." }
        let left = w.goal - w.n
        return "Added. \(w.n) of \(w.goal) glasses today, \(left) to go."
    }
}

struct NextReportIntent: AppIntent {
    static var title: LocalizedStringResource = "Next report"
    static var description = IntentDescription("Says when your next duty is, the flights and how long until you report.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: Speak.nextReport(Shared.load())))
    }
}

struct TomorrowIntent: AppIntent {
    static var title: LocalizedStringResource = "Tomorrow's duty"
    static var description = IntentDescription("Says what's on your roster tomorrow: flights, report and off-duty times, or a day off.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: Speak.tomorrow(Shared.load())))
    }
}

struct NextAlarmIntent: AppIntent {
    static var title: LocalizedStringResource = "Next alarm"
    static var description = IntentDescription("Says when Axiom's next alarm rings.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: Speak.nextAlarm(Shared.load())))
    }
}
