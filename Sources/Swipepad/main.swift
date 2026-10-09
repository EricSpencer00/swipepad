import AppKit
import Darwin
import Foundation

let delegate = AppDelegate()
if let index = CommandLine.arguments.firstIndex(of: "--render-previews"), CommandLine.arguments.indices.contains(index + 1) {
  do { try renderPreviews(to: CommandLine.arguments[index + 1], owner: delegate) } catch { print(error); exit(2) }
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
