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
  // Cropped keyboard (only the right-hand part of QWERTY) and the crop-editing view of the full keyboard.
  let cropped=OverlayKeyboardView(frame:NSRect(x:0,y:0,width:960,height:365))
  cropped.viewport=KeyboardViewport(minX:0.35,minY:0,maxX:1,maxY:1)
  cropped.path=[Point(0.15,0.25),Point(0.45,0.55),Point(0.8,0.4)] // pad coordinates, as a live stroke
  let croppedWindow=NSWindow(contentRect:cropped.frame,styleMask:[],backing:.buffered,defer:false)
  croppedWindow.contentView=cropped;croppedWindow.displayIfNeeded();cropped.display()
  if let bitmap=cropped.bitmapImageRepForCachingDisplay(in:cropped.bounds) {
    cropped.cacheDisplay(in:cropped.bounds,to:bitmap)
    if let data=bitmap.representation(using:.png,properties:[:]) {try data.write(to:folder.appendingPathComponent("overlay-cropped.png"))}
  }
  let editing=OverlayKeyboardView(frame:NSRect(x:0,y:0,width:960,height:365))
  editing.editable=true;editing.viewport=KeyboardViewport(minX:0.2,minY:0.1,maxX:0.8,maxY:1)
  let editingWindow=NSWindow(contentRect:editing.frame,styleMask:[],backing:.buffered,defer:false)
  editingWindow.contentView=editing;editingWindow.displayIfNeeded();editing.display()
  if let bitmap=editing.bitmapImageRepForCachingDisplay(in:editing.bounds) {
    editing.cacheDisplay(in:editing.bounds,to:bitmap)
    if let data=bitmap.representation(using:.png,properties:[:]) {try data.write(to:folder.appendingPathComponent("layout-crop-edit.png"))}
  }
  // A close call: the top strip offers three words; nothing is typed until one is tapped.
  let choosing=OverlayKeyboardView(frame:NSRect(x:0,y:0,width:960,height:365))
  choosing.choices=["hello","hallo","hells"]
  let choosingWindow=NSWindow(contentRect:choosing.frame,styleMask:[],backing:.buffered,defer:false)
  choosingWindow.contentView=choosing;choosingWindow.displayIfNeeded();choosing.display()
  if let bitmap=choosing.bitmapImageRepForCachingDisplay(in:choosing.bounds) {
    choosing.cacheDisplay(in:choosing.bounds,to:bitmap)
    if let data=bitmap.representation(using:.png,properties:[:]) {try data.write(to:folder.appendingPathComponent("overlay-choices.png"))}
  }
  try "Offscreen actual SetupView and OverlayKeyboardView renders. Permission states and hello stroke are illustrative fixtures. No window shown, permission requested, physical touch tested, or text inserted.\n".write(to: folder.appendingPathComponent("EVIDENCE.txt"), atomically: true, encoding: .utf8)
}
