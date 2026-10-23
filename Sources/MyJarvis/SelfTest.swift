// Grammar tests: `MyJarvis.app/Contents/MacOS/MyJarvis --selftest`
import Foundation

enum SelfTest {
    static func run() -> Bool {
        var ko = Config(); ko.language = "ko"; ko.userName = "대표님"; ko.apps = ["브루": "Vrew"]
        var en = Config(); en.language = "en"
        let pk = Parser(cfg: ko), pe = Parser(cfg: en)
        var fails = 0, total = 0
        func check(_ p: Parser, _ s: String, _ want: Intent, yt: Bool = false) {
            total += 1
            let got = p.parse(s, hasYouTubeList: yt)
            if got != want { fails += 1; print("FAIL  「\(s)」\n      want \(want)\n      got  \(got)") }
        }
        func checkBool(_ name: String, _ v: Bool) { total += 1; if !v { fails += 1; print("FAIL  \(name)") } }

        // Korean
        check(pk, "크롬 열어 줘", .openApp(spoken: "크롬", app: "Google Chrome"))
        check(pk, "브루 켜", .openApp(spoken: "브루", app: "Vrew"))
        check(pk, "맥미니 가격 검색해", .search("맥미니 가격"))
        check(pk, "유튜브 거북이 버프 영상 하나 켜봐", .youtube("거북이 버프"))
        check(pk, "유튜브에서 아이언맨 틀어", .youtube("아이언맨"))
        check(pk, "두 번째 거 틀어", .youtubeNth(2), yt: true)
        check(pk, "3번째 영상 재생해", .youtubeNth(3), yt: true)
        check(pk, "안녕하세요 라고 써 줘", .type("안녕하세요"))
        check(pk, "클로드코드에게 지금 켜져있는 모든 프로젝트 전체 점검해서 텔레그램으로 우선순위 정해서 보내",
              .claude(target: "", message: "지금 켜져있는 모든 프로젝트 전체 점검해서 텔레그램으로 우선순위 정해서 보내", newSession: true))
        check(pk, "클로드 코드한테 시켜서 블로그 점검하고 보고해", .claude(target: "", message: "블로그 점검하고 보고해", newSession: true))
        check(pk, "음성 제어 Mac 설정 프로젝트 클로드에다가 시험이라고 전달해", .claude(target: "음성 제어 Mac 설정", message: "시험", newSession: false))
        check(pk, "됐어", .bye)
        check(pk, "너 꺼", .bye)
        check(pk, "시끄러워", .hush)
        check(pk, "엔터", .enter)
        check(pk, "받아써", .dictation)
        check(pk, "아빠 왔다", .greet)
        check(pk, "오늘 일정 정리해서 알려 줘", .none)
        checkBool("ko wake strip", pk.stripWake("자비스, 크롬 열어") == "크롬 열어")
        checkBool("ko wake strip 야", pk.stripWake("자비스야 엔터") == "엔터")
        checkBool("ko instant app", pk.instant("크롬 켜"))
        checkBool("ko not instant search", !pk.instant("맥미니 가격 검색해"))
        checkBool("크롬 꺼 is not bye", !pk.isBye("크롬 꺼"))

        // English
        check(pe, "open chrome", .openApp(spoken: "chrome", app: "Google Chrome"))
        check(pe, "search for mac mini price", .search("mac mini price"))
        check(pe, "play iron man on youtube", .youtube("iron man"))
        check(pe, "play the second one", .youtubeNth(2), yt: true)
        check(pe, "type hello world", .type("hello world"))
        check(pe, "ask claude code to review all my projects", .claude(target: "", message: "review all my projects", newSession: true))
        check(pe, "that's all", .bye)
        check(pe, "daddy's home", .greet)
        checkBool("en wake strip", pe.stripWake("Hey Jarvis, open chrome") == "open chrome")

        // YouTube parser
        let html = #""videoRenderer":{"videoId":"abcdefghijk","thumbnail":{},"title":{"runs":[{"text":"First video"}]}"#
        checkBool("youtube parse", Jarvis.parseYouTube(html).first?.id == "abcdefghijk")

        print(fails == 0 ? "selftest: all \(total) passed" : "selftest: \(fails)/\(total) failed")
        return fails == 0
    }
}
