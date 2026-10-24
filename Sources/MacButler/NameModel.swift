// Teach the Mac's own speech recognizer the assistant's name (2026-10-24, owner: 「사사리사 발음 인식 더럽게 안 된다, 방법 찾아서
// 고쳐」). Apple's recognizer has never seen a made-up word, so 「사사리사」 came back as 「서 서 있어」「수술 있어」「Safari 있어」.
// macOS 14+ can build a custom language model on the Mac (SFCustomLanguageModelData → SFSpeechLanguageModel): we give it the
// name and a few hundred sentences people say with it, so the recognizer expects the word. Built once per name/version in
// ~/.macbutler/lm, entirely on this Mac; if the locale or OS can't do it, recognition simply carries on as before.
import Foundation
import Speech

enum NameModel {
    static let version = "1"
    static var folder: URL { Paths.home.appendingPathComponent("lm") }

    /// Sentences that teach the name: the name alone, with 「헤이」, and in front of common commands.
    static func phrases(names: [String], ko: Bool) -> [(String, Int)] {
        let commands = ko
            ? ["유튜브 틀어", "소리 줄여", "소리 키워", "몇 시야", "오늘 며칠이야", "창 다 꺼", "클로드한테 전달해", "쿠팡에서 찾아 줘", "날씨 어때", "받아써",
               "됐어", "멈춰", "다음 영상", "음악 틀어 줘", "타이머 3분", "크롬 열어", "카톡 열어", "검색해 줘", "이거 요약해 줘", "지금 뭐 해"]
            : ["play some music", "turn it down", "what time is it", "close all windows", "tell Claude", "open Chrome", "search for", "stop", "next video", "set a timer"]
        var out: [(String, Int)] = []
        for n in names where !n.isEmpty {
            out += [(n, 400), ((ko ? "헤이 " : "hey ") + n, 200), (n + (ko ? "야" : ""), 60)]
            out += commands.map { (n + " " + $0, 20) }
        }
        return out
    }

    /// The prepared configuration for these names, building it the first time (async, a few seconds). nil if unsupported.
    static func prepare(names: [String], locale: String, ko: Bool) async -> Any? {
        guard #available(macOS 14, *) else { return nil }
        let key = (names.joined(separator: "|") + "|" + locale + "|" + version).data(using: .utf8)!.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-").prefix(40)
        let dir = folder.appendingPathComponent(String(key))
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let asset = dir.appendingPathComponent("name.bin"), lm = dir.appendingPathComponent("lm"), vocab = dir.appendingPathComponent("vocab")
        let config = SFSpeechLanguageModel.Configuration(languageModel: lm, vocabulary: vocab)
        do {
            if !FileManager.default.fileExists(atPath: asset.path) {
                let data = SFCustomLanguageModelData(locale: Locale(identifier: locale), identifier: "com.sasarisa.name", version: version) {
                    for (p, c) in phrases(names: names, ko: ko) { SFCustomLanguageModelData.PhraseCount(phrase: p, count: c) }
                }
                try await data.export(to: asset)
            }
            if !FileManager.default.fileExists(atPath: lm.path) {
                try await SFSpeechLanguageModel.prepareCustomLanguageModel(for: asset, clientIdentifier: "com.sasarisa.name", configuration: config)
            }
            log("name model ready: \(names.joined(separator: ", ")) (\(locale))")
            return config
        } catch {
            log("name model not available: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: dir)     // try again from scratch next launch
            return nil
        }
    }
}
