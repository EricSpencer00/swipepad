import SwiftUI
import SwipepadCore

/// Settings for the trackpad area and typing timing. Changes apply immediately and are saved.
@MainActor final class SettingsModel: ObservableObject {
  @Published var region: PadRegion {
    didSet { UserDefaults.standard.set(region.stored, forKey: "padRegion") }
  }
  @Published var liftDelay: Double {
    didSet {
      UserDefaults.standard.set(liftDelay, forKey: "liftGrace")
      NotificationCenter.default.post(name: .swipepadSettingsChanged, object: nil)
    }
  }
  init() {
    region = PadRegion(stored: UserDefaults.standard.array(forKey: "padRegion") as? [Double])
    let stored = UserDefaults.standard.object(forKey: "liftGrace") as? Double
    liftDelay = stored ?? LiftGrace.defaultSeconds
  }
}
extension Notification.Name {
  static let swipepadSettingsChanged = Notification.Name("swipepadSettingsChanged")
}

struct PadSettingsView: View {
  @ObservedObject var model: SettingsModel

  var body: some View {
    Form {
      Section {
        Picker("Area", selection: presetBinding) {
          Text("Full").tag("full")
          Text("iPhone").tag("iPhone")
          Text("Compact").tag("compact")
        }
        .pickerStyle(.segmented)
        TrackpadArea(region: $model.region)
          .frame(height: 210)
          .padding(.vertical, 6)
        Text(sizeCaption)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .center)
      } header: {
        Text("Trackpad Area")
      } footer: {
        Text("Only touches inside the area type. Drag a corner to resize it.")
      }

      Section {
        LabeledContent("Pause before a word ends") {
          HStack {
            Slider(value: $model.liftDelay, in: 0...0.4, step: 0.02).frame(width: 160)
            Text(String(format: "%.2f s", model.liftDelay))
              .monospacedDigit()
              .frame(width: 52, alignment: .trailing)
          }
        }
      } header: {
        Text("Typing")
      } footer: {
        Text("A short pause in the middle of a swipe keeps the same word going.")
      }
    }
    .formStyle(.grouped)
  }

  /// The preset the current area matches, or "custom" for a hand-made area.
  private var presetBinding: Binding<String> {
    Binding(
      get: { model.region.matchingPreset ?? "custom" },
      set: { key in
        guard let region = PadRegion.named(key) else { return }
        withAnimation(.easeInOut(duration: 0.25)) { model.region = region }
      })
  }

  private var sizeCaption: String {
    let mm = model.region.physicalSizeMM
    return String(format: "About %.0f × %.0f mm", mm.width, mm.height)
  }
}

/// A trackpad drawing with the active area highlighted. Its corner handles resize the area.
struct TrackpadArea: View {
  @Binding var region: PadRegion
  private let handle: CGFloat = 22

  var body: some View {
    GeometryReader { geo in
      let size = fitted(geo.size)
      let origin = CGPoint(x: (geo.size.width - size.width) / 2, y: (geo.size.height - size.height) / 2)
      ZStack(alignment: .topLeading) {
        RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.06))
          .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.2), lineWidth: 1))
        RoundedRectangle(cornerRadius: 8)
          .fill(Color.accentColor.opacity(0.22))
          .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 2))
          .frame(width: CGFloat(region.spanX) * size.width, height: CGFloat(region.spanY) * size.height)
          .offset(x: CGFloat(region.minX) * size.width, y: CGFloat(1 - region.maxY) * size.height)
        ForEach(corners, id: \.name) { corner in
          Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
            .shadow(radius: 2, y: 1)
            .frame(width: handle, height: handle)
            .position(position(of: corner.corner, in: size))
            .gesture(
              DragGesture(coordinateSpace: .local)
                .onChanged { value in
                  let x = Double((value.location.x) / size.width)
                  let y = Double(1 - value.location.y / size.height)
                  region = region.dragging(corner.corner, to: Point(x, y))
                })
        }
      }
      .frame(width: size.width, height: size.height)
      .offset(x: origin.x, y: origin.y)
      .animation(.easeInOut(duration: 0.2), value: region)
    }
  }

  private var corners: [(name: String, corner: PadRegion.Corner)] {
    [("tl", .topLeft), ("tr", .topRight), ("bl", .bottomLeft), ("br", .bottomRight)]
  }
  private func position(of corner: PadRegion.Corner, in size: CGSize) -> CGPoint {
    let x = corner == .topLeft || corner == .bottomLeft ? region.minX : region.maxX
    let y = corner == .topLeft || corner == .topRight ? region.maxY : region.minY
    return CGPoint(x: CGFloat(x) * size.width, y: CGFloat(1 - y) * size.height)
  }
  /// The trackpad keeps its physical proportion (110 : 75) inside the available space.
  private func fitted(_ available: CGSize) -> CGSize {
    let ratio = PadRegion.trackpadMM.width / PadRegion.trackpadMM.height
    let width = min(available.width, available.height * ratio)
    return CGSize(width: width, height: width / ratio)
  }
}
