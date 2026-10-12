// Metadata only: no AX calls, window inspection, app termination or permission changes.
import AppKit
import Foundation
import Darwin
guard CommandLine.arguments.count==2 else {exit(2)}
let target=URL(fileURLWithPath:CommandLine.arguments[1]).standardizedFileURL.resolvingSymlinksInPath()
let running=NSWorkspace.shared.runningApplications.filter {$0.bundleIdentifier=="com.ericspencer00.swipepad" && $0.bundleURL?.resolvingSymlinksInPath()==target}
guard running.isEmpty else {
 print("Refusing to overwrite the running app. Build to a separate SWIPEPAD_BUILD_APP candidate; coordinate quitting/replacement with its owner.")
 exit(3)
}
