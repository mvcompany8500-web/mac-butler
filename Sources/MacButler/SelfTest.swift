// Grammar tests: `MacButler.app/Contents/MacOS/MacButler --selftest`
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
        check(pk, "유튜브에서 로파이 음악 틀어", .youtube("로파이 음악"))
        check(pk, "두 번째 거 틀어", .youtubeNth(2), yt: true)
        check(pk, "3번째 영상 재생해", .youtubeNth(3), yt: true)
        check(pk, "안녕하세요 라고 써 줘", .type("안녕하세요"))
        check(pk, "클로드코드에게 지금 켜져있는 모든 프로젝트 전체 점검해서 텔레그램으로 우선순위 정해서 보내",
              .claude(target: "", message: "지금 켜져있는 모든 프로젝트 전체 점검해서 텔레그램으로 우선순위 정해서 보내", newSession: true))
        check(pk, "클로드 코드한테 시켜서 블로그 점검하고 보고해", .claude(target: "", message: "블로그 점검하고 보고해", newSession: true))
        check(pk, "음성 제어 Mac 설정 프로젝트 클로드에다가 시험이라고 전달해", .claude(target: "음성 제어 Mac 설정", message: "시험", newSession: false))
        check(pk, "쿠팡에서 무선 이어폰 찾아 줘", .web(label: "쿠팡", query: "무선 이어폰", url: "https://www.coupang.com/np/search?q="))
        check(pk, "네이버 쇼핑에서 맥미니 검색해", .web(label: "네이버 쇼핑", query: "맥미니", url: "https://search.shopping.naver.com/search/all?query="))
        check(pk, "에어팟 최저가 찾아 줘", .web(label: "네이버 쇼핑", query: "에어팟", url: "https://search.shopping.naver.com/search/all?query="))
        check(pk, "네이버에서 오늘 날씨 검색해", .web(label: "네이버", query: "오늘 날씨", url: "https://search.naver.com/search.naver?query="))
        check(pk, "지금 켜진 클로드 창에 로그인 버그 고쳐 줘", .claude(target: "", message: "로그인 버그 고쳐 줘", newSession: false))
        check(pk, "지금 켜진 클로드 창에 로그인 버그 고치고, 아니, 취소", .hush)
        check(pk, "지금 켜진 클로드 창에다가 버그 고치라고 해", .claude(target: "", message: "버그 고치라고 해", newSession: false))
        checkBool("알았어 조용히 해 = hush", pk.isHush("알았어 조용히 해"))
        check(pk, "쿠팡 홈페이지에 들어가서 맥미니 가격", .web(label: "쿠팡", query: "맥미니 가격", url: "https://www.coupang.com/np/search?q="))
        check(pk, "쿠팡 들어가서 무선 이어폰 찾아 줘", .web(label: "쿠팡", query: "무선 이어폰", url: "https://www.coupang.com/np/search?q="))
        check(pk, "쿠팡 열어", .web(label: "쿠팡", query: "", url: "https://www.coupang.com/"))
        check(pk, "영상 멈추고 쿠팡에서 맥미니 찾아 줘", .multi(["영상 멈춰", "쿠팡에서 맥미니 찾아 줘"]))   // 10/23: quick parts run in order
        checkBool("영상 멈춰 is not hush", !pk.isHush("이거 영상 멈춰"))
        check(pk, "클로드한테 얘기해. 애플 인증서 받는 게 좋은지", .claude(target: "", message: "애플 인증서 받는 게 좋은지", newSession: true))
        check(pk, "그래 다 꺼", .closeOpened)   // 10/23: 「다 꺼」 = close what it opened
        check(pk, "너 꺼", .bye)
        check(pk, "기억해: 내 유튜브 채널은 거북이버프야", .remember("내 유튜브 채널은 거북이버프야"))
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
        check(pe, "play lofi music on youtube", .youtube("lofi music"))
        check(pe, "play the second one", .youtubeNth(2), yt: true)
        check(pe, "type hello world", .type("hello world"))
        check(pe, "ask claude code to review all my projects", .claude(target: "", message: "review all my projects", newSession: true))
        check(pe, "find usb c cable on amazon", .web(label: "Amazon", query: "usb c cable", url: "https://www.amazon.com/s?k="))
        check(pe, "that's all", .bye)
        check(pe, "daddy's home", .greet)
        checkBool("en wake strip", pe.stripWake("Hey Jarvis, open chrome") == "open chrome")

        // Hands ask before send / pay / post / delete, and before handing work to a full-power Claude session
        checkBool("「카톡으로 보내 줘」 asked to send", Butler.userAskedFor("send", "엄마한테 카톡으로 보내 줘"))
        checkBool("「카톡 열어」 didn't ask to send", !Butler.userAskedFor("send", "카톡 열어서 엄마 채팅 찾아"))
        checkBool("「결제해」 asked to pay", Butler.userAskedFor("pay", "장바구니 결제해"))
        checkBool("「보내」 is not a pay request", !Butler.userAskedFor("pay", "이거 보내"))
        checkBool("plain host kept", Butler.safeHost("www.youtube.com"))
        checkBool("AppleScript-breaking host refused", !Butler.safeHost("x\" then\ntell current application to do shell script \"id"))
        checkBool("percent-encoded host refused", !Butler.safeHost("x%22%20then"))
        checkBool("MCP tap → jax line", Brain.commandLine("tap", ["name": "저장", "n": 2]) == "jax tap \"저장\" \"2\"")
        checkBool("MCP open_url → jax line", Brain.commandLine("open_url", ["url": "https://naver.com"]) == "jax open-url \"https://naver.com\"")
        checkBool("MCP steps are learnable", Learning.replayable([Brain.commandLine("open_url", ["url": "https://naver.com"])]) != nil)
        checkBool("MCP delegate is never learned", Learning.replayable([Brain.commandLine("delegate", ["session": "", "task": "x"])]) == nil)

        // Plug-in voices and brains: keys only over https, plain http only to this Mac
        var hv = Config(); hv.tts = "http"; hv.ttsURL = "http://127.0.0.1:5002/tts"
        checkBool("http voice on this Mac", Mouth.speechRequest(hv, "안녕")?.url?.absoluteString == "http://127.0.0.1:5002/tts")
        hv.ttsURL = "http://example.com/tts"
        checkBool("http voice elsewhere needs https", Mouth.speechRequest(hv, "안녕") == nil)
        var az = Config(); az.tts = "azure"; az.ttsRegion = "korea.central/../x"
        checkBool("azure region can't inject a host", Mouth.speechRequest(az, "안녕") == nil)
        checkBool("brain base: https ok", APIBrain.safeBase("https://openrouter.ai/api/v1") != nil)
        checkBool("brain base: local http ok", APIBrain.safeBase("http://127.0.0.1:11434/v1") != nil)
        checkBool("brain base: remote http refused", APIBrain.safeBase("http://evil.example/v1") == nil)
        var cc = Config(); checkBool("default brain is Claude Code", APIBrain.provider(cc) == nil)
        cc.brainProvider = "ollama"; checkBool("ollama brain", APIBrain.provider(cc)?.local == true)

        // Whisper sanity
        checkBool("whisper drops subtitle line", Whisper.clean("한글자막 by 한효정\n 헤이 자비스 지금 몇 시야?", apple: "헤이 자비스 지금 몇 시야") == "헤이 자비스 지금 몇 시야?")
        checkBool("whisper unrelated rejected", !Whisper.related("자비스, 이거 지금, 고맙습니다.", "됐어"))
        checkBool("whisper related kept", Whisper.related("한글 인식 자체가 생각보다 많이 안 돼.", "한글 이진식 자체가 생각보다 많이 안 돼"))
        for (said, want) in [("쿠팡의 맥미니 서치해봐", "web(label: \"쿠팡\", query: \"맥미니\""), ("알았어. 그러면 유튜브에 터틀메이커 검색해서 재생시켜봐", "youtube(\"터틀메이커\")"),
                             ("유튜브 로파이 틀어", "youtube(\"로파이\")"), ("멈춰, 영상", "media(play: false)"), ("YouTube 영상 멈춰", "media(play: false)"),
                             ("지금 틀어져 있는 영상들 다 꺼", "media(play: false)"), ("영상 다시 틀어", "media(play: true)"), ("멈춰", "hush"),
                             ("쿠팡 띄워서 Mac mini 찾아봐", "web(label: \"쿠팡\", query: \"Mac mini\""), ("쿠팡이 나에게 맞는 컴퓨터 찾아줘", "web(label: \"쿠팡\", query: \"나에게 맞는 컴퓨터\""),
                             ("쿠팡 에어팟 찾아 줘", "web(label: \"쿠팡\", query: \"에어팟\""), ("쿠팡 의자 찾아 줘", "web(label: \"쿠팡\", query: \"의자\""),
                             ("지금 켜져 있는 유튜브 창 꺼", "closeTabs(label: \"유튜브\""), ("YouTube 창 꺼 종료시켜", "closeTabs(label: \"유튜브\""),
                             ("자비스, 자비스, 클로드 창에다가 지금 버그 체크해서 다시 고쳐놓으라 그래", "claude(target: \"\""),
                             ("하이재비스 유튜브 참 켜", "youtube(\"\")"), ("YouTube창 켜", "youtube(\"\")"), ("유튜브 창 켜 봐", "youtube(\"\")"),
                             ("하이 재비스 쿠팡 열어", "web(label: \"쿠팡\", query: \"\""),
                             ("이제 화면 다 꺼", "displayOff"), ("화면 전체를 아예 꺼버리라고", "displayOff"), ("다음 영상으로 넘겨", "mediaNext"),
                             ("그래, 사파리 영상이 다 꺼. 유튜브 켜져 있는 화면 다 꺼.", "closeTabs(label: \"유튜브\""),
                             ("켜져있는 클로드에게 지금 버그 지금까지 된거 한번 더 체크해서 고치라고 해", "claude(target: \"\", message: \"지금 버그 지금까지 된거 한번 더 체크해서 고치라고 해\", newSession: false)"),
                             ("자비스야, 쿠팡 말고 유튜브 터틀메이커 검색해봐.", "youtube(\"터틀메이커\")"), ("아니, 유튜브에다가 터틀메이커 검색해줘.", "youtube(\"터틀메이커\")"),
                             ("지금 켜져 있는 창들 다 꺼줘.", "closeOpened"), ("창 다 꺼", "closeOpened"), ("아니 취소", "hush"),
                             ("지금 켜져 있는 유튜브 뒤로 가기 누르라고", "browser(\"back\")"), ("소리 키워", "volume(set: nil, delta: 15"), ("볼륨 30으로 해", "volume(set: Optional(30)"),
                             ("몇 시야", "clock(date: false)"), ("오늘 며칠이야", "clock(date: true)"), ("다 끄라고", "closeOpened"),
                             ("라면 3분", "timer(seconds: 180, label: \"라면\")"), ("10분 뒤에 알려 줘", "timer(seconds: 600"), ("1시간 30분 후에 회의라고 알려 줘", "timer(seconds: 5400, label: \"회의\")"),
                             ("3분짜리 영상 찾아 줘", "search("), ("타이머 취소", "cancelTimers"), ("강남역 가는 길", "map(\"강남역\")"), ("지금 어디야", "none"),
                             ("로파이 틀고 소리 줄이고 화면 꺼", "multi([\"로파이 틀어\", \"소리 줄여\", \"화면 꺼\"])"), ("로파이 틀어", "youtube(\"로파이\")"),
                             ("쿠팡 열고 클로드에 버그 고치라고 해", "none"),
                             ("앞으로 작업 시작 하면 클로드 열고 로파이 틀고 소리 30으로 해", "makeRoutine(name: \"작업 시작\", steps: [\"클로드 열어\", \"로파이 틀어\", \"소리 30으로 해\"])"),
                             ("작업 시작이라고 하면 카톡에 보내고 결제해", "badRoutine("), ("쿠팡 열면 맥미니 찾아", "web(label: \"쿠팡\", query: \"맥미니\""),
                             ("지금 떠있는 클로드 창에 이제 시작한다고 말해줘", "claude(target: \"\", message: \"이제 시작한다고 말해줘\", newSession: false)")] {
            checkBool("parse: \(said)", "\(pk.parse(pk.stripWake(said), hasYouTubeList: true))".hasPrefix(want))
        }
        checkBool("whisper repeated tail dropped", Whisper.dropRepeatedTail("맥미니 M6 찾아. 고팩! 고팩! 고팩!", apple: "Mac mini MS 찾아").0 == "맥미니 M6 찾아.")
        checkBool("whisper YouTube = 유튜브", Whisper.related("지금 켜져 있는 유튜브 창 꺼.", "자비스 지금 켜져 있는 YouTube 창 꺼"))
        do {   // breath vs voice: a 140 Hz voice-like tone with harmonics is voiced; dark noise (a puff on the mic) isn't
            var voice = [Float](repeating: 0, count: 1600), puff = [Float](repeating: 0, count: 1600), acc: Float = 0
            for i in 0..<1600 {
                let t = Float(i) / 16000
                voice[i] = 0.1 * (sin(2 * .pi * 140 * t) + 0.5 * sin(2 * .pi * 280 * t) + 0.3 * sin(2 * .pi * 420 * t))
                acc = acc * 0.97 + Float.random(in: -1...1); puff[i] = acc * 0.01
            }
            checkBool("voice is voiced", voice.withUnsafeBufferPointer { DoubleTalk.periodicity($0.baseAddress!, 1600) } > DoubleTalk.voiced)
            checkBool("breath is not voiced", puff.withUnsafeBufferPointer { DoubleTalk.periodicity($0.baseAddress!, 1600) } < DoubleTalk.voiced)
        }
        checkBool("sentence sounds finished", Ear.soundsFinished("유튜브 로파이 틀어") && Ear.soundsFinished("몇 시야?") && !Ear.soundsFinished("유튜브에서") && !Ear.soundsFinished("그리고"))
        checkBool("brain started a video", Parser.startedMedia("사파리에서 유튜브에 터틀메이커를 검색해 첫 영상을 재생했습니다."))
        checkBool("brain paused a video", !Parser.startedMedia("영상을 일시정지했습니다."))
        checkBool("whisper shaky word → Apple text", !Whisper.shaky([("자비스,", 0.9), ("신별시야.", 0.2)], apple: "자비스 지금 몇 시야").isEmpty)
        checkBool("whisper sure word kept", Whisper.shaky([("한글", 0.9), ("인식", 0.6)], apple: "한글 이진식").isEmpty)
        checkBool("whisper shaky word Apple also heard", Whisper.shaky([("코덱스", 0.2)], apple: "코덱스 켜").isEmpty)

        // Learning: only safe action steps are replayable
        checkBool("learn jax key", Learning.replayable(["jax front", "jax key space"])?.count == 1)
        checkBool("learn rejects shell", Learning.replayable(["jax key space; rm -rf ~"]) == nil)
        checkBool("learn rejects delegate", Learning.replayable(["butler delegate \"|x\""]) == nil)
        checkBool("learn rejects click", Learning.replayable(["jax click 10 10"]) == nil)
        checkBool("tokens quoted", Learning.tokens("jax tap \"Save as\" 2") == ["jax", "tap", "Save as", "2"])

        // Growth: names are studied, verbs are not
        checkBool("study ignores verbs", !Growth.words("크롬 열어 줘").contains("열어") || Growth.study(whisper: "열어", live: "x", known: []).isEmpty)
        checkBool("words latin", Growth.words("open ComfyUI now").contains("ComfyUI"))

        // Korean reading for TTS
        let kr: [(String, String)] = [
            ("오후 3시 16분입니다", "오후 세 시 십육 분입니다"), ("1,399,900원", "백삼십구만 구천구백 원"), ("사과 2개", "사과 두 개"),
            ("10월 23일", "시월 이십삼 일"), ("M4 맥미니", "엠포 맥미니"), ("24GB", "이십사 기가"), ("30%", "삼십 퍼센트"),
            ("2026년", "이천이십육 년"), ("17분 10초", "십칠 분 십 초"), ("20명", "스무 명"), ("1.5배", "일 점 오 배"), ("10000원", "만 원")]
        for (a, b) in kr { checkBool("read \(a) → \(KoreanReader.read(a))", KoreanReader.read(a) == b) }

        // YouTube parser
        let html = #""videoRenderer":{"videoId":"abcdefghijk","thumbnail":{},"title":{"runs":[{"text":"First video"}]}"#
        checkBool("youtube parse", Butler.parseYouTube(html).first?.id == "abcdefghijk")

        print(fails == 0 ? "selftest: all \(total) passed" : "selftest: \(fails)/\(total) failed")
        return fails == 0
    }
}
