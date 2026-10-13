import AppKit
import Darwin
import Foundation

let delegate = AppDelegate()
if let index = CommandLine.arguments.firstIndex(of: "--self-test-write"), CommandLine.arguments.indices.contains(index + 1) {
  let word = CommandLine.arguments[index + 1]
  var delay = 6.0
  if let d = CommandLine.arguments.firstIndex(of: "--delay"), CommandLine.arguments.indices.contains(d + 1), let v = Double(CommandLine.arguments[d + 1]) { delay = v }
  let report = delegate.selfTestWrite(word, delay: delay)
  let data = try! JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
  print(String(data: data, encoding: .utf8)!)
  exit((report["ok"] as? Bool) == true ? 0 : 2)
} else if let index = CommandLine.arguments.firstIndex(of: "--render-previews"), CommandLine.arguments.indices.contains(index + 1) {
  do { try renderPreviews(to: CommandLine.arguments[index + 1], owner: delegate) } catch { print(error); exit(2) }
} else if CommandLine.arguments.contains("--capture-status") {
  guard let report=delegate.liveDoctorSnapshot(captureOnly:true),report.scope.hasPrefix("Live capture counters"),
    let data=try? JSONEncoder().encode(report),let json=String(data:data,encoding:.utf8) else {exit(2)}
  print(json);exit(0)
} else if CommandLine.arguments.contains("--doctor") {
  let report = delegate.liveDoctorSnapshot() ?? delegate.doctorReport(live: false)
  if CommandLine.arguments.contains("--json") {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(report), let json = String(data: data, encoding: .utf8) {
      print(json)
    }
  } else {
    print(report.text)
  }
  if report.checks.contains(where: { $0.status == .fail }) { exit(2) }
} else if CommandLine.arguments.contains("--relaunch-owned") {
  if !delegate.relaunchOwned() { exit(2) }
} else if CommandLine.arguments.contains("--show-setup") {
  DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("com.ericspencer00.swipepad.showSetup"), object: nil, userInfo: nil,
    deliverImmediately: true)
} else {
  let app = NSApplication.shared
  app.delegate = delegate
  app.run()
}
