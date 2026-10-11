import Foundation
public enum TextReplacement {
  static func range(in value:String,location:Int,length:Int)->Range<String.Index>? {
    guard location>=0,length>=0,location<=value.utf16.count,length<=value.utf16.count-location else {return nil}
    let start=String.Index(utf16Offset:location,in:value),end=String.Index(utf16Offset:location+length,in:value)
    // AX ranges use UTF-16, but insertion must not split a user-perceived character.
    guard (start==value.endIndex || value.indices.contains(start)),
      (end==value.endIndex || value.indices.contains(end)) else {return nil}
    return start..<end
  }
  public static func replacing(_ value:String,location:Int,length:Int,with inserted:String)->String? {
    guard let range=range(in:value,location:location,length:length) else {return nil}
    return value.replacingCharacters(in:range,with:inserted)
  }
}
/// Word insertion changes only the selected span; existing separators and punctuation stay intact.
public enum WordInsertion {
  public struct Plan:Equatable,Sendable {
    public let text:String,leadingSeparator:Bool,trailingSeparator:Bool
  }
  public enum Refusal:Error,Equatable,Sendable {case invalidRange,partialWord,invalidWord}
  private static let connectors:Set<Character>=["'","’","-","‐","‑"]
  private static let closing:Set<Character>=[".",",",";",":","!","?","…","%"]
  private static func wordBase(_ c:Character)->Bool {
    c.isLetter || c.isNumber || c.unicodeScalars.allSatisfy {
      [.nonspacingMark,.spacingMark,.enclosingMark].contains($0.properties.generalCategory)
    }
  }
  private static func wordCharacter(at index:String.Index,in value:String)->Bool {
    if wordBase(value[index]) {return true}
    guard connectors.contains(value[index]),index>value.startIndex else {return false}
    let next=value.index(after:index)
    return next<value.endIndex && wordBase(value[value.index(before:index)]) && wordBase(value[next])
  }
  private static func opening(at index:String.Index,in value:String)->Bool {
    let c=value[index]
    if c=="¿" || c=="¡" {return true}
    if c.unicodeScalars.contains(where:{[.openPunctuation,.initialPunctuation].contains($0.properties.generalCategory)}) {return true}
    guard c=="\"" || c=="'" else {return false}
    guard index>value.startIndex else {return true}
    let preceding=value[value.index(before:index)]
    return preceding.isWhitespace || preceding.unicodeScalars.contains {
      [.openPunctuation,.initialPunctuation].contains($0.properties.generalCategory)
    }
  }
  public static func boundaryRefusal(_ value:String,location:Int,length:Int)->Refusal? {
    guard let span=TextReplacement.range(in:value,location:location,length:length) else {return .invalidRange}
    let previous=span.lowerBound>value.startIndex ? value.index(before:span.lowerBound):nil
    let next=span.upperBound<value.endIndex ? span.upperBound:nil
    if span.isEmpty {
      if let previous,let next,wordCharacter(at:previous,in:value),wordCharacter(at:next,in:value) {return .partialWord}
    } else {
      if let previous,wordCharacter(at:previous,in:value),wordCharacter(at:span.lowerBound,in:value) {return .partialWord}
      if let next,wordCharacter(at:value.index(before:span.upperBound),in:value),wordCharacter(at:next,in:value) {return .partialWord}
    }
    return nil
  }
  public static func plan(_ value:String,location:Int,length:Int,word:String)->Result<Plan,Refusal> {
    guard !word.isEmpty,!word.contains(where:{$0.isWhitespace || $0.isNewline}) else {return .failure(.invalidWord)}
    guard let span=TextReplacement.range(in:value,location:location,length:length) else {return .failure(.invalidRange)}
    let previous=span.lowerBound>value.startIndex ? value.index(before:span.lowerBound):nil
    let next=span.upperBound<value.endIndex ? span.upperBound:nil
    if let refusal=boundaryRefusal(value,location:location,length:length) {return .failure(refusal)}
    let leading=previous.map {!value[$0].isWhitespace && !opening(at:$0,in:value)} ?? false
    let trailing=next.map {index in
      let c=value[index]
      return !c.isWhitespace && !closing.contains(c) &&
        !c.unicodeScalars.contains(where:{[.closePunctuation,.finalPunctuation].contains($0.properties.generalCategory)}) &&
        !((c=="\"" || c=="'") && !opening(at:index,in:value))
    } ?? true
    return .success(Plan(text:(leading ? " ":"")+word+(trailing ? " ":""),leadingSeparator:leading,trailingSeparator:trailing))
  }
}
public struct DisplayBounds:Sendable {
 public let x:Double,y:Double,width:Double,height:Double
 public init(x:Double,y:Double,width:Double,height:Double) {self.x=x;self.y=y;self.width=width;self.height=height}
}
public enum ScreenCorner:Hashable,Sendable {case topLeft,topRight,bottomLeft,bottomRight}
public enum CornerAvoidance {
 public static func redirected(_ p:Point,displays:[DisplayBounds],enabled:Set<ScreenCorner>=[.topLeft,.topRight,.bottomLeft,.bottomRight])->Point {
   guard p.x.isFinite,p.y.isFinite else {return p}
   for r in displays where r.width>0 && r.height>0 && p.x>=r.x && p.x<=r.x+r.width && p.y>=r.y && p.y<=r.y+r.height {
     let radius=min(24,r.width/8,r.height/8),inset=min(36,r.width/4,r.height/4)
     let left=p.x-r.x<=radius,right=r.x+r.width-p.x<=radius,top=p.y-r.y<=radius,bottom=r.y+r.height-p.y<=radius
     let corner:ScreenCorner = top ? (left ? .topLeft:.topRight):(left ? .bottomLeft:.bottomRight)
     if (left || right) && (top || bottom) && enabled.contains(corner) {return Point(left ? r.x+inset:r.x+r.width-inset,top ? r.y+inset:r.y+r.height-inset)}
     return p
   };return p
 }
}
