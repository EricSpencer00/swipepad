import AppKit
import Foundation

@MainActor func renderPreviews(to directory: String, owner: AppDelegate) throws {
  let app = NSApplication.shared
  app.setActivationPolicy(.prohibited)
  let folder = URL(fileURLWithPath: directory, isDirectory: true)
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
    for trusted in [false, true] {
      let view = SetupView(owner: owner)
      view.previewTrusted = trusted
      view.appearance = NSAppearance(named: appearance)
      view.refresh(); view.layoutSubtreeIfNeeded()
      let window = SetupWindow(contentRect: view.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
      window.contentView = view
      window.layoutIfNeeded()
      window.displayIfNeeded()
      view.layoutSubtreeIfNeeded()
      view.display()
      if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if let data = bitmap.representation(using: .png, properties: [:]) {
          try data.write(to: folder.appendingPathComponent("setup-\(trusted ? "ready" : "access")-\(name).png"))
        }
      }
      window.orderOut(nil)
    }
  }
  try "Offscreen actual SetupView renders. Permission states are illustrative overrides. No window shown, permission requested, physical touch tested, or text inserted.\n".write(to: folder.appendingPathComponent("EVIDENCE.txt"), atomically: true, encoding: .utf8)
}
