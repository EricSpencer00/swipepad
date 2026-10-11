import Foundation

/// Tracks held contacts, so a completed lift can rearm without another idle frame.
public struct ContactGate: Sendable {
  public private(set) var contactsPresent=false
  public var waitingForLift=false
  public private(set) var observedLift=false
  public init() {}
  public mutating func observe(activeContacts:Int) {
    contactsPresent=activeContacts>0
    if !contactsPresent {waitingForLift=false;observedLift=true}
  }
  public mutating func rearm() {waitingForLift=contactsPresent}
  public mutating func noteLift() {observedLift=true}
  public mutating func reset() {contactsPresent=false;waitingForLift=false;observedLift=false}
}
public enum InsertionContinuation {
  /// Replacement collapses selection after the inserted UTF-16 text, in the same target.
  public static func permits(originalLocation:Int,insertedUTF16Count:Int,resultLocation:Int,resultLength:Int,sameTarget:Bool) -> Bool {
    guard sameTarget,originalLocation>=0,insertedUTF16Count>=0 else {return false}
    let (expected,overflow)=originalLocation.addingReportingOverflow(insertedUTF16Count)
    return !overflow && resultLocation==expected && resultLength==0
  }
}
/// Presentation never contributes to word ranking, thinning or the contact source label.
public enum Recognition {
  /// Fresh tap in the canonical A/I key region, with bounded jitter; no time gate.
  public static func singleLetter(_ samples:[StrokeSample],freshContact:Bool)->String? {
    guard freshContact,samples.count>=2,let first=samples.first,
      samples.allSatisfy({$0.source==first.source && $0.time.isFinite && Keyboard.nearestKey($0.point) != nil}),
      zip(samples,samples.dropFirst()).allSatisfy({$0.time <= $1.time}),
      let key=Keyboard.nearestKey(first.point),key=="a" || key=="i",
      samples.allSatisfy({Keyboard.nearestKey($0.point)==key}) else {return nil}
    let xs=samples.map {$0.point.x},ys=samples.map {$0.point.y}
    guard hypot(xs.max()!-xs.min()!,ys.max()!-ys.min()!)<=0.05,
      zip(samples,samples.dropFirst()).reduce(0.0,{$0+$1.0.point.distance($1.1.point)})<=0.12 else {return nil}
    return key=="i" ? "I":"a"
  }
  public static func candidates(_ samples:[StrokeSample],words:[String]) -> [String] {
    StrokeDecoder.candidates(samples,words:words)
  }
}
