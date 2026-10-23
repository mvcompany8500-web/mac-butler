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
    case remember(String)                                   // 「기억해: …」 — a long-term note
    case media(play: Bool)                                  // pause / resume whatever video or music is playing
    case closeTabs(label: String, host: String)             // 「유튜브 창 꺼」 — close those browser tabs
    case mediaNext                                          // 「다음 영상」 — skip to the next video / track
    case displayOff                                         // 「화면 꺼」 — turn the display off (sleep)
    case closeOpened                                        // 「창 다 꺼」 — close what it opened for you (pages, apps)
    case browser(String)                                    // 「뒤로 가」「앞으로」「새로고침」 in the browser in front: back / forward / reload
    case volume(set: Int?, delta: Int, mute: Bool)          // 「소리 키워」「볼륨 30」「음소거」
    case clock(date: Bool)                                  // 「몇 시야」「오늘 며칠이야」 — answered on the Mac, no Claude
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

    /// How Whisper / Apple often mishear the wake word: "재비스", "하이 자비스".
    var wakeVariants: [String] {
        var out = cfg.wakes
        for w in cfg.wakes {
            if w.contains("자비스") { out.append(w.replacingOccurrences(of: "자비스", with: "재비스")) }
            if w.hasPrefix("헤이 ") { out.append("하이 " + w.dropFirst(3)) }
        }
        out += cfg.wakes.filter { $0.hasPrefix("헤이 ") && $0.contains("자비스") }.map { "하이 " + $0.dropFirst(3).replacingOccurrences(of: "자비스", with: "재비스") }
        return out.sorted { $0.count > $1.count }          // longest first: "헤이 자비스" before "자비스"
    }
    func wakeRange(_ t: String) -> Range<String.Index>? {
        for w in wakeVariants {
            let pat = w.replacingOccurrences(of: " ", with: "").map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "\\s*")
            if let r = t.range(of: pat, options: [.regularExpression, .caseInsensitive]) { return r }
        }
        return nil
    }
    /// Removes a leading wake word ("자비스, …", "hey jarvis …", "자비스, 자비스, …").
    func stripWake(_ t: String) -> String {
        var t = t
        for _ in 0..<3 {
            guard let r = wakeRange(t), t.distance(from: t.startIndex, to: r.lowerBound) < 8 else { break }
            var rest = String(t[r.upperBound...])
            if rest.hasPrefix("야") { rest.removeFirst() }
            t = Parser.clean(rest)
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
        if s.count <= 6, ["됐어", "됐다"].contains(where: s.hasPrefix) { return true }
        // only "너 꺼", "자비스 꺼", "너 이제 꺼" — "다 꺼", "그래 꺼", "크롬 꺼" are actions for Claude
        if ["너꺼", "자비스꺼", "너이제꺼", "이제꺼져", "너꺼져", "자비스꺼져", "그만꺼"].contains(s) { return true }
        return false
    }
    func isHush(_ c: String) -> Bool {
        let s = Parser.squash(c)
        if hushWords.contains(s) { return true }
        // only with a short lead-in: "알았어 조용히 해", "야 멈춰", "okay stop" — but "영상 멈춰" is an action, not hush
        let leads = ["", "알았어", "알겠어", "야", "아니", "됐고", "그래", "오케이", "자비스", "ok", "okay", "hey"]
        for h in ["조용히해", "조용", "멈춰", "그만해", "시끄러워", "시끄러", "쉿", "stop", "quiet"] where s.hasSuffix(h) {
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
        var s = Parser.clean(raw)
        let sq = Parser.squash(s)
        if s.isEmpty { return .none }
        if Parser.cancelledAtEnd(s) { return .hush }     // “…, 아니 취소” / “…, never mind” — the speaker took it back
        if isGreeting(s) { return .greet }
        if ["받아써", "받아적어", "받아쓰기", "타이핑모드", "말하는대로써", "takedictation", "dictationmode", "startdictation"].contains(where: sq.contains) { return .dictation }
        if enterWords.contains(sq) { return .enter }
        if isHush(s) { return .hush }
        if isBye(s) { return .bye }
        s = Parser.dropLeadIn(s)
        // "쿠팡 말고 유튜브 터틀메이커 검색해봐" — the part after 말고 is what you want
        if let r = s.range(of: #"\s말고[,\s]+"#, options: .regularExpression), s[r.upperBound...].count >= 2 { s = String(s[r.upperBound...]) }
        if let c = Parser.closeTabs(s) { return .closeTabs(label: c.0, host: c.1) }
        if Parser.isCloseOpened(s) { return .closeOpened }
        if let b = Parser.browserNav(s) { return .browser(b) }
        if let v = Parser.volume(s) { return .volume(set: v.0, delta: v.1, mute: v.2) }
        if let d = Parser.clock(s) { return .clock(date: d) }
        if Parser.isDisplayOff(s) { return .displayOff }
        if Parser.isNext(s) { return .mediaNext }
        if let play = Parser.mediaControl(s) { return .media(play: play) }

        let tail = "\\s*(해 봐 줘|해봐줘|해 봐|해봐|해 줘|해줘|해 주세요|해|줘|좀|봐|봐 줘|봐줘|주세요)?$"
        // Korean: 「안녕하세요 라고 써 줘」
        if let m = Parser.match(s, "^(.+?)\\s*(이?라고)\\s*(써|쳐|입력해|타이핑해|적어)\\s*(줘|주세요)?$") { return .type(m[1]) }
        // English: "type hello world"
        if let m = Parser.match(s, "^(type|write)\\s+(.+)$") { return .type(m[2]) }

        // Claude: 「(세션) 클로드한테 ○○ 라고 전달해」 → relay just that; 「클로드코드한테 ○○ 해서 보내」 → whole task.
        if let m = Parser.match(s, "^(.*?)\\s*(클로드\\s*코드|클로드)\\s*(한테|에게|창에다가|창에다|창에|에다가|에다|에|님|보고)\\s*[,，]?\\s*(.+)$") {
            var target = m[1]
            let here = ["지금", "현재", "여기", "이 창", "열린", "켜진", "켜져 있는", "보고 있는", "떠 있는", "떠있는", "열려 있는"].contains { target.contains($0) } || (m[3].hasPrefix("창에") && target.isEmpty)
            for w in ["프로젝트", "세션", "창", "에 있는", "떠 있는", "떠있는", "열려 있는", "있는", "지금", "켜져 있는", "켜진", "열린", "현재", "여기", "보고"] { target = target.replacingOccurrences(of: w, with: "") }
            target = target.trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
            // "켜져있는 클로드에게" — what's left is only a "the open one" word → the current window
            let openWords = ["켜져", "켜져있는", "떠", "떠있는", "열려", "열려있는", "켜진", "열린", "지금", "현재", "여기", "이"]
            let isHere = here || openWords.contains(Parser.squash(target))
            if openWords.contains(Parser.squash(target)) { target = "" }
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
                return .claude(target: target, message: verbStem ? rest : q[1], newSession: target.isEmpty && !isHere)
            }
            return .claude(target: target, message: rest, newSession: target.isEmpty && !isHere)
        }
        if let m = Parser.match(s, "^(ask|tell|have)\\s+claude(\\s+code)?\\s+(to\\s+)?(.+)$") {
            return .claude(target: "", message: m[4], newSession: m[1].lowercased() != "tell")
        }

        // YouTube: play the first result right away
        if let m = Parser.match(s, "^(유튜브|youtube)\\s*(에다가(?=\\s)|에다(?=\\s)|에서(?=\\s)|로(?=\\s)|에(?=\\s))?\\s*(.*?)\\s*(?:검색해서|검색해 가지고|찾아서)?\\s*(틀어|재생\\s*시켜|재생해|재생|켜|보여|찾아|검색|열어)" + tail) {
            let filler: Set<String> = ["아무거나", "영상", "하나", "동영상", "거", "좀", "한", "개", "아무", "창", "화면", "페이지", "사이트", "홈", "앱", "참"]   // 참 = 창 misheard
            return .youtube(m[3].split(separator: " ").map(String.init).filter { !filler.contains($0) }.joined(separator: " "))
        }
        if let m = Parser.match(s, "^play\\s+(.+?)\\s+on\\s+youtube$") ?? Parser.match(s, "^youtube\\s+([^가-힣]+)$") { return .youtube(m[1]) }
        if hasYouTubeList {
            if let m = Parser.match(s, "^(.+?)\\s*(번째|번)\\s*(거|것|영상|꺼)?\\s*(틀어|켜|재생|열어|보여)" + tail), let n = Parser.ordinal(m[1]) { return .youtubeNth(n) }
            if let m = Parser.match(s, "^play\\s+(the\\s+)?(number\\s+)?(\\w+)(\\s+one)?$"), let n = Parser.ordinal(m[3]) { return .youtubeNth(n) }
        }

        // Two things in one breath ("영상 멈추고 쿠팡에서 …", "X 하고 Y") → Claude does them in order.
        if let m = Parser.match(s, "^(기억해|기억해 둬|기억해둬|메모해|remember(?: that)?)\\s*[:,]?\\s*(.+)$") { return .remember(m[2]) }
        if let m = Parser.match(s, "^(.+?)\\s*(이?라고|라는 거|라는 걸)?\\s*(기억해 둬|기억해둬|기억해)$"), m[1].count >= 2 { return .remember(m[1]) }
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
            // "쿠팡에/쿠팡의/쿠팡이 …" — a particle only when glued to the name ("쿠팡 에어팟" keeps 에어팟)
            guard let m = Parser.match(s, "^(" + pat + ")(?:(?:에다가|에다|에서|에|의|이|가|은|는|으로|로)(?=\\s|$))?\\s*(.*)$") else { continue }
            var q = m[2]
            // drop "홈페이지에 들어가서", "사이트에서", "에서", "가서", "접속해서" …
            for lead in ["홈페이지에 들어가서", "홈페이지 들어가서", "홈페이지에서", "홈페이지에", "사이트에 들어가서", "사이트에서", "앱에서",
                         "에 들어가서", "들어가서", "에 가서", "가서", "접속해서", "띄워서", "열어서", "켜서", "들어가 가지고"] {
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

    /// "알았어. 그러면 유튜브에 …" → "유튜브에 …" (a reply to it, then the actual command).
    static func dropLeadIn(_ s: String) -> String {
        var t = s
        let leads = ["아니 그게 아니라", "그게 아니라", "아니야", "아니", "알았어", "알겠어", "오케이", "좋아", "그래", "그러면", "그럼", "자", "음", "아", "okay", "ok", "so", "then", "no"]
        var changed = true
        while changed {
            changed = false
            let low = t.lowercased()
            for l in leads where low.hasPrefix(l) {
                let rest = String(t.dropFirst(l.count))
                guard let c = rest.first, c == " " || c == "," || c == "." else { continue }
                let r = rest.trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
                if r.count >= 2 { t = r; changed = true }
                break
            }
        }
        return t
    }
    /// "지금 켜져 있는 유튜브 창 꺼", "쿠팡 탭 닫아" → close those tabs (not just pause).
    static func closeTabs(_ s: String) -> (String, String)? {
        let q = squash(s)
        guard ["창", "탭", "페이지", "화면", "window", "tab"].contains(where: q.contains),
              ["꺼", "닫아", "닫어", "종료", "없애", "close"].contains(where: q.contains) else { return nil }
        let sites = [("유튜브", "youtube.com"), ("youtube", "youtube.com"), ("쿠팡", "coupang.com"), ("네이버", "naver.com"), ("구글", "google.com"), ("아마존", "amazon.com")]
        // "구글이나 이런 거 탭들 다 꺼" — more than one site, vaguely → Claude decides.
        if ["이나", "같은거", "이런거", "같은것", "등등"].contains(where: q.contains) { return nil }
        guard let (word, host) = sites.first(where: { q.contains($0.0) }) else { return nil }
        return (word == "youtube" ? "유튜브" : word, host)
    }
    /// "화면 꺼", "화면 전체를 아예 꺼 버려", "모니터 꺼" → the display itself. Only those words — "이미지랑 폴더 화면에
    ///있는 거 다 꺼" is about windows, so anything else in the sentence sends it to Claude.
    static func isDisplayOff(_ s: String) -> Bool {
        var q = squash(s)
        guard ["화면", "모니터", "디스플레이", "screen", "display"].contains(where: q.contains), ["꺼", "끄", "off"].contains(where: q.contains) else { return false }
        let ok = ["디스플레이", "버리라고", "turnoff", "display", "screen", "모니터", "전체를", "이제", "화면", "전체", "아예", "버려", "라고", "꺼", "끄", "다", "좀", "줘", "the", "off"]
        var changed = true
        while changed && !q.isEmpty {
            changed = false
            for w in ok where q.hasPrefix(w) { q.removeFirst(w.count); changed = true; break }
        }
        return q.isEmpty
    }
    /// "창 다 꺼", "지금 켜져 있는 창들 다 꺼줘", "켜 놨던 거 다 닫아" — no particular site → what it opened.
    static func isCloseOpened(_ s: String) -> Bool {
        let q = squash(s)
        if ["다꺼", "다꺼줘", "다끄라고", "다꺼라", "다꺼버려", "전부꺼", "싹다꺼", "다닫아", "다닫아줘", "전부닫아"].contains(q) { return true }
        guard q.count <= 30, ["꺼", "닫아", "닫어", "종료", "없애", "close"].contains(where: q.contains) else { return false }
        let what = ["창", "탭", "켜놨던", "켜놓은", "켜둔", "열어놓은", "열어둔", "열어놨던", "띄운", "띄워놓은", "띄워둔", "windows", "tabs"]
        let all = ["다", "전부", "모두", "싹", "all"]
        // "썸네일 이미지들 다 꺼", "폴더 창 다 닫아" — something specific it didn't open → Claude
        if ["이미지", "사진", "썸네일", "폴더", "파일", "문서", "미리보기", "finder", "image", "folder"].contains(where: q.contains) { return false }
        return what.contains(where: q.contains) && all.contains(where: q.contains)
    }
    /// 「뒤로 가기 눌러」「뒤로 가」「앞으로 가」「새로고침」 (short sentences only — longer ones go to Claude)
    static func browserNav(_ s: String) -> String? {
        let q = squash(s)
        guard q.count <= 18 else { return nil }
        if ["뒤로가", "뒤로가기", "이전페이지", "goback"].contains(where: q.contains), !q.contains("채널") { return "back" }
        if ["앞으로가", "다음페이지", "goforward"].contains(where: q.contains) { return "forward" }
        if ["새로고침", "새로고쳐", "refresh", "reload"].contains(where: q.contains) { return "reload" }
        return nil
    }
    /// 「소리 키워」「볼륨 좀 줄여」「소리 30으로」「음소거」 → (set, delta, mute)
    static func volume(_ s: String) -> (Int?, Int, Bool)? {
        let q = squash(s)
        guard q.count <= 16, ["소리", "볼륨", "음량", "volume", "음소거", "mute"].contains(where: q.contains) else { return nil }
        if q.contains("음소거") && !q.contains("해제") || q.contains("mute") && !q.contains("unmute") { return (nil, 0, true) }
        if let n = Int(q.filter(\.isNumber)), (0...100).contains(n) { return (n, 0, false) }
        if ["키워", "크게", "올려", "높여", "up", "louder"].contains(where: q.contains) { return (nil, 15, false) }
        if ["줄여", "작게", "낮춰", "내려", "down", "quieter"].contains(where: q.contains) { return (nil, -15, false) }
        if q.contains("해제") || q.contains("unmute") { return (nil, 0, false) }
        return nil
    }
    /// 「몇 시야」「지금 몇 시」 → false · 「오늘 며칠이야」「무슨 요일」 → true
    static func clock(_ s: String) -> Bool? {
        let q = squash(s)
        guard q.count <= 14 else { return nil }
        if ["몇시", "whattime", "시간알려"].contains(where: q.contains) { return false }
        if ["며칠", "몇일", "무슨요일", "오늘날짜", "whatday", "date"].contains(where: q.contains) { return true }
        return nil
    }
    /// "다음 영상으로 넘겨", "다음 곡", "next video"
    static func isNext(_ s: String) -> Bool {
        let q = squash(s)
        return q.count <= 16 && (["다음영상", "다음곡", "다음노래", "다음거틀어", "다음걸로", "nextvideo", "nextsong", "skip"].contains(where: q.contains))
    }
    /// "영상 멈춰", "유튜브 꺼", "노래 정지", "틀어져 있는 영상들 다 꺼" → pause · "다시 틀어", "이어서 재생" → play.
    static func mediaControl(_ s: String) -> Bool? {
        let q = squash(s)
        guard q.count <= 24 else { return nil }
        let things = ["영상", "동영상", "유튜브", "youtube", "음악", "노래", "재생중", "틀어져", "video", "music"]
        let stops = ["멈춰", "멈춤", "정지", "일시정지", "중지", "꺼", "끄", "스톱", "stop", "pause"]
        if things.contains(where: q.contains),
           stops.contains(where: { q.hasSuffix($0) || q.hasSuffix($0 + "줘") || q.hasSuffix($0 + "봐") || q.hasPrefix($0) }) { return false }
        if ["다시틀어", "다시재생", "이어서틀어", "이어서재생", "계속틀어", "계속재생", "resume", "playagain"].contains(where: q.contains) { return true }
        return nil
    }
    /// Claude's reply says it started a video / music ("…재생했습니다", "틀었습니다", "Playing …").
    static func startedMedia(_ answer: String) -> Bool {
        let a = answer.lowercased()
        return ["재생했", "재생합니다", "재생 중", "재생중", "틀었", "틀어 드렸", "틀어드렸", "now playing", "started playing", "is playing"].contains(where: a.contains)
            && !["멈췄", "정지했", "껐", "paused", "stopped"].contains(where: a.contains)
    }
    /// "X 멈추고 Y", "X 하고 Y", "X 그리고 Y", "X 한 다음 Y" — more than one action.
    static func isCompound(_ s: String) -> Bool {
        if [" 그리고 ", "한 다음", "하고 나서", "고 나서", "한 뒤에", "다음에 "].contains(where: { s.contains($0) }) { return true }
        return match(s, "(멈추|끄|켜|열|닫|틀|누르|찾|가|보|치|하)고\\s+\\S+.*(해|줘|봐|켜|열어|틀어|찾아|검색|보여)") != nil
    }
    /// Removes a trailing ask: "찾아 줘", "검색해", "보여 줘", "알아봐", "좀".
    static func stripAsk(_ q: String) -> String {
        var t = q.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let asks = ["띄워 봐", "띄워봐", "띄워 줘", "띄워줘", "서치해 줘", "서치해줘", "서치해 봐", "서치 해 봐", "서치해봐", "서치해", "서치", "검색해 봐", "검색해봐",
                    "검색해 줘", "검색해줘", "검색해", "검색", "찾아 줘", "찾아줘", "찾아 봐", "찾아봐", "찾아", "보여 줘", "보여줘", "보여", "알아봐 줘", "알아봐", "열어 줘", "열어줘", "열어", "좀"]
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
