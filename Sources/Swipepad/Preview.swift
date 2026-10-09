import AppKit
import Foundation
import SwipepadCore

@MainActor func renderPreviews(to directory: String, owner: AppDelegate) throws {
  let app = NSApplication.shared
  app.setActivationPolicy(.prohibited)
  let folder = URL(fileURLWithPath: directory, isDirectory: true)
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
    let overlay=OverlayKeyboardView(frame:NSRect(x:0,y:0,width:960,height:365))
    overlay.path=Keyboard.path("hello");overlay.appearance=NSAppearance(named:appearance)
    let overlayWindow=NSWindow(contentRect:overlay.frame,styleMask:[],backing:.buffered,defer:false)
    overlayWindow.contentView=overlay;overlayWindow.displayIfNeeded();overlay.display()
    if let bitmap=overlay.bitmapImageRepForCachingDisplay(in:overlay.bounds) {
      overlay.cacheDisplay(in:overlay.bounds,to:bitmap)
      if let data=bitmap.representation(using:.png,properties:[:]) {
        try data.write(to:folder.appendingPathComponent("overlay-\(name).png"))
      }
    }
    overlayWindow.orderOut(nil)
    for trusted in [false, true] {
      let view = SetupView(owner: owner)
      view.previewTrusted = trusted
      view.appearance = NSAppearance(named: appearance)
      view.refresh(); view.layoutSubtreeIfNeeded()
      let window = SetupWindow(contentRect: view.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
      window.contentView = view
      view.fitWindow()
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
  try "Offscreen actual SetupView and OverlayKeyboardView renders. Permission states and hello stroke are illustrative fixtures. No window shown, permission requested, physical touch tested, or text inserted.\n".write(to: folder.appendingPathComponent("EVIDENCE.txt"), atomically: true, encoding: .utf8)
}
