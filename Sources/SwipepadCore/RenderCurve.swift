import Foundation
public struct QuadraticSegment:Equatable,Sendable {
  public let start:Point,control:Point,end:Point
  public func point(at t:Double)->Point {let u=1-t;return Point(u*u*start.x+2*u*t*control.x+t*t*end.x,u*u*start.y+2*u*t*control.y+t*t*end.y)}
}
/// Causal midpoint rounding stays in each local triangle: no overshoot, exact endpoints.
/// Raw points are never replaced, resampled or fed back into recognition.
public enum RenderCurve {
  public static func segments(_ points:[Point])->[QuadraticSegment] {
    guard points.count>1 else {return []}
    var result:[QuadraticSegment]=[],start=points[0]
    for i in 0..<points.count-1 {
      let p=points[i],next=points[i+1]
      let reversal=i>0 && (p.x-points[i-1].x)*(next.x-p.x)+(p.y-points[i-1].y)*(next.y-p.y)<0
      let end=reversal ? p : Point((p.x+next.x)/2,(p.y+next.y)/2)
      result.append(QuadraticSegment(start:start,control:p,end:end));start=end
    }
    let last=points.last!;result.append(QuadraticSegment(start:start,control:last,end:last));return result
  }
}
public struct FrameOrdering:Sendable {
  private var cutoff=0.0,lastTime:Double?,lastFrame:Int32?,device:Int32?
  public init() {}
  public mutating func reset(receivedAfter:Double) {cutoff=receivedAfter;lastTime=nil;lastFrame=nil;device=nil}
  public mutating func accept(receivedAt:Double,timestamp:Double,frame:Int32,deviceID:Int32)->Bool {
    guard receivedAt.isFinite,timestamp.isFinite,timestamp>=0,receivedAt>=cutoff,
      lastTime.map({timestamp >= $0}) ?? true,lastFrame.map({frame > $0}) ?? true,
      device.map({deviceID == $0}) ?? true else {return false}
    lastTime=timestamp;lastFrame=frame;device=deviceID;return true
  }
}
