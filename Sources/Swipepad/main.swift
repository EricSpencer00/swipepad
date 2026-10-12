import AppKit
import Darwin
import Foundation

let delegate = AppDelegate()
if CommandLine.arguments.contains("--stored-write-tracking") {
  delegate.loadWriteTracking()
  guard delegate.writeTrackingReadable,let data=try? JSONEncoder().encode(delegate.outstandingWriteReports()),let json=String(data:data,encoding:.utf8) else {exit(2)}
  print(json);exit(0)
} else if let index=CommandLine.arguments.firstIndex(of:"--preserve-write-tracking"),CommandLine.arguments.indices.contains(index+1) {
  guard delegate.importWriteTracking(CommandLine.arguments[index+1]) else {print("Tracking preservation failed; no restart or text action performed.");exit(2)}
  print("Unconfirmed-write protection preserved; no field query or text replay.");exit(0)
} else if let index = CommandLine.arguments.firstIndex(of: "--render-previews"), CommandLine.arguments.indices.contains(index + 1) {
  do { try renderPreviews(to: CommandLine.arguments[index + 1], owner: delegate) } catch { print(error); exit(2) }
 } else if CommandLine.arguments.contains("--self-health") || CommandLine.arguments.contains("--health-status") {
  let report:RuntimeHealth?
  if CommandLine.arguments.contains("--self-health") {report=delegate.runtimeHealth(live:false)} else {report=delegate.liveRuntimeHealth()}
  guard let report,let data=try? JSONEncoder().encode(report),let json=String(data:data,encoding:.utf8) else {print("Health-only response unavailable or unsupported; no field query performed.");exit(2)}
  print(json);exit(0)
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
