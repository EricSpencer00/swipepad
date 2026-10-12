import Foundation

/// Conservative reconnection of an interrupted moving stroke; no generated points.
public enum LiftGrace {
  public static let defaultSeconds = 0.10
  public static let maximumBounces=3
  public static let maximumMissingSeconds=0.30
  public static func nearby(_ samples:[StrokeSample],point:Point,elapsed:Double,idChanged:Bool,bounces:Int,missing:Double,grace:Double)->Bool {
    guard elapsed>=0,elapsed<=min(grace,0.14),bounces<maximumBounces,
      missing+elapsed<=maximumMissingSeconds,let end=samples.last,
      point.x>=0,point.x<=1,point.y>=0,point.y<=1,
      let prior=samples.dropLast().reversed().first(where:{$0.point.distance(end.point)>0.012}),
      samples.first.map({first in samples.contains(where:{first.point.distance($0.point)>0.04})}) == true else {return false}
    let dt=max(0.008,end.time-prior.time)
    let speed=end.point.distance(prior.point)/dt
    let reach=min(idChanged ? 0.065:0.09,0.025+speed*elapsed*0.65)
    return end.point.distance(point)<=reach
  }
  public static func directionContinues(_ samples:[StrokeSample],first:Point,next:Point)->Bool? {
    guard let end=samples.last,let prior=samples.dropLast().reversed().first(where:{$0.point.distance(end.point)>0.012}) else {return false}
    let dx=next.x-first.x,dy=next.y-first.y,length=hypot(dx,dy)
    guard length>=0.005 else {return nil} // Need a real observed movement, not inferred velocity.
    let ax=end.point.x-prior.point.x,ay=end.point.y-prior.point.y
    return (ax*dx+ay*dy)/(hypot(ax,ay)*length)>=0.25
  }
}
