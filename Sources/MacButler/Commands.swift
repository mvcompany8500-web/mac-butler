// Turns a spoken sentence into an intent. Pure functions — covered by `MacButler --selftest`.
// Anything that isn't matched here goes to Claude.
import Foundation

enum Intent: Equatable {
    case greet, dictation, bye, hush, enter
    case type(String)
    case claude(target: String, message: String, newSession: Bool)
    case youtube(String)          // "" = YouTube home
    case youtubeNth(Int)
    case search(String)
    case web(label: String, query: String, url: String)   // shopping / site search
    case openApp(spoken: String, app: String)
    case none
}

struct Parser {
    let cfg: Config

    static let defaultApps: [String: String] = [
        "크롬": "Google Chrome", "구글 크롬": "Google Chrome", "사파리": "Safari", "메모": "Notes", "메모장": "Notes",
        "카톡": "KakaoTalk", "카카오톡": "KakaoTalk", "클로드": "Claude", "터미널": "Terminal", "파인더": "Finder",
        "캘린더": "Calendar", "달력": "Calendar", "메일": "Mail", "음악": "Music", "사진": "Photos", "설정": "System Settings",
        "텔레그램": "Telegram", "슬랙": "Slack", "텍스트 편집기": "TextEdit", "계산기": "Calculator",
        "chrome": "Google Chrome", "safari": "Safari", "notes": "Notes", "terminal": "Terminal", "finder": "Finder",
        "calendar": "Calendar", "mail": "Mail", "music": "Music", "photos": "Photos", "settings": "System Settings",
        "slack": "Slack", "telegram": "Telegram", "calculator": "Calculator", "claude": "Claude", "textedit": "TextEdit"]
    var apps: [String: String] { Parser.defaultApps.merging(cfg.apps) { _, new in new } }
    func app(_ spoken: String) -> String? {
        let k = spoken.trimmingCharacters(in: .whitespaces)
        return apps[k] ?? apps[k.lowercased()]
    }

    // MARK: helpers

    static func match(_ s: String, _ pat: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pat, options: [.caseInsensitive]),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (0..<m.numberOfRanges).map { i in Range(m.range(at: i), in: s).map { String(s[$0]) } ?? "" }
    }
    static func squash(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
    static func clean(_ s: String) -> String {
        var x = s.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        for p in ["야 ", "야,", "님 "] where x.hasPrefix(p) { x = String(x.dropFirst(p.count)) }
        return x.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    // MARK: wake word / greeting

    func wakeRange(_ t: String) -> Range<String.Index>? {
        for w in cfg.wakes {
            let pat = w.replacingOccurrences(of: " ", with: "").map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "\\s*")
            if let r = t.range(of: pat, options: [.regularExpression, .caseInsensitive]) { return r }
        }
        return nil
    }
    /// Removes a leading wake word ("자비스, …", "hey jarvis …").
    func stripWake(_ t: String) -> String {
        if let r = wakeRange(t), t.distance(from: t.startIndex, to: r.lowerBound) < 8 {
            var rest = String(t[r.upperBound...])
            if rest.hasPrefix("야") { rest.removeFirst() }
            return Parser.clean(rest)
        }
        return Parser.clean(t)
    }
    func isGreeting(_ t: String) -> Bool {
        let s = Parser.squash(t)
        return cfg.greets.contains { s.contains(Parser.squash($0)) }
    }

    // MARK: short commands that don't need Whisper

    private var byeWords: Set<String> {
        ["됐어", "그만", "고마워", "끝", "됐다", "잘자", "쉬어", "수고했어", "꺼져",
         "thatsall", "thanks", "thankyou", "goodnight", "nevermind", "gotosleep", "stoplistening"]
    }
    private var hushWords: Set<String> {
        ["시끄러", "시끄러워", "조용", "조용히", "조용히해", "멈춰", "스톱", "그만해", "잠깐", "잠깐만", "쉿",
         "stop", "quiet", "shutup", "wait", "holdon", "hush"]
    }
    private var enterWords: Set<String> { ["엔터", "엔터쳐", "보내", "전송", "enter", "pressenter", "send"] }

    func isBye(_ c: String) -> Bool {
        let s = Parser.squash(c)
        if byeWords.contains(s) { return true }
        if s.count <= 6, ["됐어", "그만", "됐다"].contains(where: s.hasPrefix) { return true }
        // "너 꺼", "자비스 꺼" — but not "크롬 꺼"
        if s.count <= 8, s.hasSuffix("꺼") || s.hasSuffix("꺼져"), !apps.keys.contains(where: { s.contains(Parser.squash($0)) }) { return true }
        return false
    }
    func isHush(_ c: String) -> Bool {
        let s = Parser.squash(c)
        if hushWords.contains(s) { return true }
        // only with a short lead-in: "알았어 조용히 해", "야 멈춰", "okay stop" — but "영상 멈춰" is an action, not hush
        let leads = ["", "알았어", "알겠어", "야", "아니", "됐고", "그래", "오케이", "자비스", "ok", "okay", "hey"]
        for h in ["조용히해", "조용", "멈춰", "그만해", "시끄러워", "쉿", "stop", "quiet"] where s.hasSuffix(h) {
            if leads.contains(String(s.dropLast(h.count))) { return true }
        }
        return false
    }

    /// True when Apple's live text is good enough to act on right away.
    func instant(_ c: String) -> Bool {
        if isBye(c) || isHush(c) || enterWords.contains(Parser.squash(c)) { return true }
        if case .openApp = parse(c, hasYouTubeList: false) { return true }
        return false
    }

    // MARK: the grammar

    func parse(_ raw: String, hasYouTubeList: Bool) -> Intent {
        let s = Parser.clean(raw)
        let sq = Parser.squash(s)
        if s.isEmpty { return .none }
        if Parser.cancelledAtEnd(s) { return .hush }     // “…, 아니 취소” / “…, never mind” — the speaker took it back
        if isGreeting(s) { return .greet }
        if ["받아써", "받아적어", "받아쓰기", "타이핑모드", "말하는대로써", "takedictation", "dictationmode", "startdictation"].contains(where: sq.contains) { return .dictation }
        if enterWords.contains(sq) { return .enter }
        if isHush(s) { return .hush }
        if isBye(s) { return .bye }

        let tail = "\\s*(해 줘|해줘|해 주세요|해|줘|좀|봐|봐 줘|봐줘|주세요)?$"
        // Korean: 「안녕하세요 라고 써 줘」
        if let m = Parser.match(s, "^(.+?)\\s*(이?라고)\\s*(써|쳐|입력해|타이핑해|적어)\\s*(줘|주세요)?$") { return .type(m[1]) }
        // English: "type hello world"
        if let m = Parser.match(s, "^(type|write)\\s+(.+)$") { return .type(m[2]) }

        // Claude: 「(세션) 클로드한테 ○○ 라고 전달해」 → relay just that; 「클로드코드한테 ○○ 해서 보내」 → whole task.
        if let m = Parser.match(s, "^(.*?)\\s*(클로드\\s*코드|클로드)\\s*(한테|에게|창에다가|창에다|창에|에다가|에다|에|님|보고)\\s*[,，]?\\s*(.+)$") {
            var target = m[1]
            let here = ["지금", "현재", "여기", "이 창", "열린", "켜진", "켜져 있는", "보고 있는"].contains { target.contains($0) } || (m[3].hasPrefix("창에") && target.isEmpty)
            for w in ["프로젝트", "세션", "창", "에 있는", "있는", "지금", "켜져 있는", "켜진", "열린", "현재", "여기", "보고"] { target = target.replacingOccurrences(of: w, with: "") }
            target = target.trimmingCharacters(in: .whitespaces)
            var rest = m[4]
            for p in ["다가 ", "다 "] where rest.hasPrefix(p) { rest = String(rest.dropFirst(p.count)) }
            // "클로드한테 얘기해. <내용>" — the verb came first, the content after it
            for p in ["얘기해서", "말해서", "시켜서", "얘기해", "말해", "전해", "전달해", "시켜", "물어봐"] where rest.hasPrefix(p) {
                let after = String(rest.dropFirst(p.count)).trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
                if after.count >= 2 { rest = after }
            }
            for p in ["시켜서 ", "시켜 ", "얘기해서 ", "말해서 "] where rest.hasPrefix(p) { rest = String(rest.dropFirst(p.count)) }
            if let q = Parser.match(rest, "^(.+?)\\s*(이?라고)\\s*(전달|보내|말|입력|써|적어|넣어|해|얘기)" + tail) {
                // 「테스트라고 전달해」 quotes a word; 「버그 고치라고 해」 is an order — keep the whole order.
                let verbStem = "하치기리지가보내주우추르꾸들켜꺼써봐줘라".contains(q[1].last ?? " ")
                return .claude(target: target, message: verbStem ? rest : q[1], newSession: target.isEmpty && !here)
            }
            return .claude(target: target, message: rest, newSession: target.isEmpty && !here)
        }
        if let m = Parser.match(s, "^(ask|tell|have)\\s+claude(\\s+code)?\\s+(to\\s+)?(.+)$") {
            return .claude(target: "", message: m[4], newSession: m[1].lowercased() != "tell")
        }

        // YouTube: play the first result right away
        if let m = Parser.match(s, "^(유튜브|youtube)\\s*(에서|로|에)?\\s*(.*?)\\s*(틀어|켜|보여|찾아|검색|재생|열어)" + tail) {
            let filler: Set<String> = ["아무거나", "영상", "하나", "동영상", "거", "좀", "한", "개", "아무"]
            return .youtube(m[3].split(separator: " ").map(String.init).filter { !filler.contains($0) }.joined(separator: " "))
        }
        if let m = Parser.match(s, "^play\\s+(.+?)\\s+on\\s+youtube$") ?? Parser.match(s, "^youtube\\s+(.+)$") { return .youtube(m[1]) }
        if hasYouTubeList {
            if let m = Parser.match(s, "^(.+?)\\s*(번째|번)\\s*(거|것|영상|꺼)?\\s*(틀어|켜|재생|열어|보여)" + tail), let n = Parser.ordinal(m[1]) { return .youtubeNth(n) }
            if let m = Parser.match(s, "^play\\s+(the\\s+)?(number\\s+)?(\\w+)(\\s+one)?$"), let n = Parser.ordinal(m[3]) { return .youtubeNth(n) }
        }

        // Two things in one breath ("영상 멈추고 쿠팡에서 …", "X 하고 Y") → Claude does them in order.
        if Parser.isCompound(s) { return .none }

        // Shopping & site search — the site can be named anywhere: "쿠팡 홈페이지에 들어가서 맥미니 가격",
        // "쿠팡 들어가서 이어폰 찾아 줘", "네이버 쇼핑에서 …", "쿠팡 열어" (home page).
        let sites: [(String, String, String, String)] = [
            ("쿠팡", "쿠팡", "https://www.coupang.com/np/search?q=", "https://www.coupang.com/"),
            ("네이버\\s*쇼핑", "네이버 쇼핑", "https://search.shopping.naver.com/search/all?query=", "https://shopping.naver.com/"),
            ("네이버", "네이버", "https://search.naver.com/search.naver?query=", "https://www.naver.com/"),
            ("구글", "Google", "https://www.google.com/search?q=", "https://www.google.com/"),
            ("아마존|amazon", "Amazon", "https://www.amazon.com/s?k=", "https://www.amazon.com/")]
        for (pat, label, url, home) in sites {
            guard let m = Parser.match(s, "^(" + pat + ")\\s*(.*)$") else { continue }
            var q = m[2]
            // drop "홈페이지에 들어가서", "사이트에서", "에서", "가서", "접속해서" …
            for lead in ["홈페이지에 들어가서", "홈페이지 들어가서", "홈페이지에서", "홈페이지에", "사이트에 들어가서", "사이트에서", "앱에서",
                         "에 들어가서", "들어가서", "에 가서", "가서", "접속해서", "에서", "에", "으로", "로"] {
                if q.hasPrefix(lead) { q = String(q.dropFirst(lead.count)).trimmingCharacters(in: .whitespaces) }
            }
            q = Parser.stripAsk(q)
            if q.isEmpty || ["열어", "켜", "들어가", "가", "접속해", "띄워"].contains(where: { q == $0 }) { return .web(label: label, query: "", url: home) }
            return .web(label: label, query: q, url: url)
        }
        if let m = Parser.match(s, "^(.+?)\\s*(최저가|가격 비교)\\s*(찾아|검색|보여|알아봐)?" + tail) { return .web(label: "네이버 쇼핑", query: m[1], url: "https://search.shopping.naver.com/search/all?query=") }
        if let m = Parser.match(s, "^(shop for|buy|find)\\s+(.+?)\\s+on\\s+amazon$") { return .web(label: "Amazon", query: m[2], url: "https://www.amazon.com/s?k=") }

        // Web search
        if let m = Parser.match(s, "^(.+?)\\s*(검색|찾아 ?봐|찾아)" + tail), !m[1].contains("클로드"), m[1].split(separator: " ").count <= 6 { return .search(m[1]) }
        if let m = Parser.match(s, "^(search( for)?|google|look up)\\s+(.+)$") { return .search(m[3]) }

        // Open an app
        if let m = Parser.match(s, "^(.+?)\\s*(좀\\s*)?(열어|켜|띄워|실행)" + tail), let a = app(m[1]) { return .openApp(spoken: m[1], app: a) }
        if let m = Parser.match(s, "^(open|launch|start)\\s+(.+)$"), let a = app(m[2]) { return .openApp(spoken: m[2], app: a) }
        return .none
    }

    /// "X 멈추고 Y", "X 하고 Y", "X 그리고 Y", "X 한 다음 Y" — more than one action.
    static func isCompound(_ s: String) -> Bool {
        if [" 그리고 ", "한 다음", "하고 나서", "고 나서", "한 뒤에", "다음에 "].contains(where: { s.contains($0) }) { return true }
        return match(s, "(멈추|끄|켜|열|닫|틀|누르|찾|가|보|치|하)고\\s+\\S+.*(해|줘|봐|켜|열어|틀어|찾아|검색|보여)") != nil
    }
    /// Removes a trailing ask: "찾아 줘", "검색해", "보여 줘", "알아봐", "좀".
    static func stripAsk(_ q: String) -> String {
        var t = q.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let asks = ["검색해 줘", "검색해줘", "검색해", "검색", "찾아 줘", "찾아줘", "찾아 봐", "찾아봐", "찾아", "보여 줘", "보여줘", "보여", "알아봐 줘", "알아봐", "열어 줘", "열어줘", "열어", "좀"]
        var changed = true
        while changed {
            changed = false
            for a in asks where t.hasSuffix(a) { t = String(t.dropLast(a.count)).trimmingCharacters(in: .whitespaces); changed = true; break }
        }
        return t
    }
    static let cancelWords = ["아니 취소", "아니취소", "취소", "하지 마", "하지마", "아니야 됐어", "아니 됐어", "never mind", "nevermind", "cancel that", "scratch that"]
    static func cancelledAtEnd(_ s: String) -> Bool {
        let t = s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return t.count > 4 && cancelWords.contains { t.hasSuffix($0) }
    }
    static func ordinal(_ w: String) -> Int? {
        let t = w.replacingOccurrences(of: " ", with: "").lowercased()
        if let n = Int(t.filter { $0.isNumber }), n > 0 { return n }
        let en = ["first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5]
        if let n = en[t] { return n }
        let ko: [(String, Int)] = [("다섯", 5), ("여섯", 6), ("일곱", 7), ("여덟", 8), ("아홉", 9), ("하나", 1), ("첫", 1), ("한", 1), ("두", 2), ("둘", 2), ("세", 3), ("셋", 3), ("네", 4), ("넷", 4), ("열", 10)]
        return ko.first { t.hasSuffix($0.0) }?.1
    }
}
