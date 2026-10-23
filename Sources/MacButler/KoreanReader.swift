// Text → how a Korean speaker reads it aloud, before it goes to TTS.
// TTS engines misread Korean numbers (native vs Sino-Korean), money with commas, months, and Latin model names.
//   "오후 3시 16분" → "오후 세 시 십육 분" · "1,399,900원" → "백삼십구만 구천구백 원" · "2개" → "두 개"
//   "10월" → "시월" · "M4" → "엠포" · "24GB" → "이십사 기가" · "30%" → "삼십 퍼센트"
import Foundation

enum KoreanReader {
    static let sinoDigits = ["", "일", "이", "삼", "사", "오", "육", "칠", "팔", "구"]

    /// Sino-Korean reading of a whole number: 1399900 → 백삼십구만 구천구백
    static func sino(_ n: Int) -> String {
        if n == 0 { return "영" }
        let groups = [(1_000_000_000_000, "조"), (100_000_000, "억"), (10_000, "만"), (1, "")]
        var n = n, parts: [String] = []
        for (unit, name) in groups where n >= unit {
            let chunk = n / unit; n %= unit
            var s = under10000(chunk)
            if name == "만" && chunk == 1 { s = "" }           // 만, not 일만
            parts.append(s + name)
        }
        return parts.joined(separator: " ")
    }
    private static func under10000(_ n: Int) -> String {
        var s = ""
        for (v, name) in [(1000, "천"), (100, "백"), (10, "십"), (1, "")] {
            let d = (n / v) % 10
            if d == 0 { continue }
            s += (d == 1 && v > 1 ? "" : sinoDigits[d]) + name
        }
        return s
    }
    /// Native Korean before a counter (1–99): 1 → 한, 2 → 두, 20 → 스무, 21 → 스물한
    static func native(_ n: Int) -> String? {
        guard (1...99).contains(n) else { return nil }
        let tens = ["", "열", "스물", "서른", "마흔", "쉰", "예순", "일흔", "여든", "아흔"]
        let ones = ["", "한", "두", "세", "네", "다섯", "여섯", "일곱", "여덟", "아홉"]
        if n == 20 { return "스무" }
        return tens[n / 10] + ones[n % 10]
    }
    static let nativeCounters: Set<String> = ["개", "명", "번째", "시간", "살", "마리", "잔", "권", "배", "가지", "군데", "통", "장", "곡", "대"]
    static let monthNames = [6: "유월", 10: "시월"]
    static let unitWords = ["%": "퍼센트", "GB": "기가", "MB": "메가", "TB": "테라", "KB": "킬로바이트", "km": "킬로미터", "kg": "킬로그램", "cm": "센티미터", "mm": "밀리미터", "ms": "밀리초"]

    static func read(_ text: String) -> String {
        var s = latinModels(text)
        let pat = #"(\d[\d,]*)(?:\.(\d+))?\s*(번째|시간|개|명|번|시|살|마리|잔|권|배|가지|군데|통|장|곡|대|분|초|원|년|월|일|층|회|쪽|위|등|도|퍼센트|%|GB|MB|TB|KB|km|kg|cm|mm|ms)?"#
        guard let re = try? NSRegularExpression(pattern: pat) else { return s }
        let ns = s as NSString
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed() {
            let digits = ns.substring(with: m.range(at: 1)).replacingOccurrences(of: ",", with: "")
            guard let n = Int(digits) else { continue }
            let frac = m.range(at: 2).location != NSNotFound ? ns.substring(with: m.range(at: 2)) : nil
            let unit = m.range(at: 3).location != NSNotFound ? ns.substring(with: m.range(at: 3)) : ""
            var word: String
            if frac == nil, nativeCounters.contains(unit), let nat = native(n) { word = nat + " " + unit }
            else if frac == nil, unit == "시", (1...12).contains(n), let nat = native(n) { word = nat + " 시" }
            else if frac == nil, unit == "번", n <= 10, let nat = native(n) { word = nat + " 번" }
            else if frac == nil, unit == "월", let special = monthNames[n] { word = special }
            else {
                word = sino(n)
                if let f = frac { word += " 점 " + f.compactMap { Int(String($0)) }.map { $0 == 0 ? "영" : sinoDigits[$0] }.joined() }
                if !unit.isEmpty { word += " " + (unitWords[unit] ?? unit) }
            }
            s = (s as NSString).replacingCharacters(in: m.range, with: word)
        }
        return s.replacingOccurrences(of: "  ", with: " ")
    }

    /// "M4" → "엠포", "M6 Pro" → "엠식스 Pro" — letter+digit product names, read the English way.
    static func latinModels(_ text: String) -> String {
        let letters: [Character: String] = ["A": "에이", "B": "비", "C": "씨", "D": "디", "E": "이", "F": "에프", "G": "지", "H": "에이치", "I": "아이", "J": "제이",
            "K": "케이", "L": "엘", "M": "엠", "N": "엔", "O": "오", "P": "피", "Q": "큐", "R": "알", "S": "에스", "T": "티", "U": "유", "V": "브이", "W": "더블유", "X": "엑스", "Y": "와이", "Z": "지"]
        let en = ["0": "제로", "1": "원", "2": "투", "3": "쓰리", "4": "포", "5": "파이브", "6": "식스", "7": "세븐", "8": "에잇", "9": "나인"]
        guard let re = try? NSRegularExpression(pattern: #"\b([A-Z])(\d)\b"#) else { return text }
        var s = text
        let ns = text as NSString
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            let l = Character(ns.substring(with: m.range(at: 1))), d = ns.substring(with: m.range(at: 2))
            s = (s as NSString).replacingCharacters(in: m.range, with: (letters[l] ?? String(l)) + (en[d] ?? d))
        }
        return s
    }
}
