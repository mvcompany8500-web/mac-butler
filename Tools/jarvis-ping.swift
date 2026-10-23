// Send a local signal to My Jarvis.   jarvis-ping <say|type|delegate> <text>
//   say       "open chrome"            — run a command as if spoken
//   type      "hello"                  — type into the focused field, character by character
//   delegate  "session name|task"      — hand a task to Claude (empty session name = new session)
import Foundation
let a = CommandLine.arguments
guard a.count >= 2 else { print("usage: jarvis-ping <say|type|delegate> <text>"); exit(1) }
DistributedNotificationCenter.default().postNotificationName(.init("com.myjarvis." + a[1]), object: a.dropFirst(2).joined(separator: " "), userInfo: nil, deliverImmediately: true)
