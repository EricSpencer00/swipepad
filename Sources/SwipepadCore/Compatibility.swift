import Foundation
public enum TextReplacement {
  public static func replacing(_ value:String,location:Int,length:Int,with inserted:String)->String? {
    guard location>=0,length>=0,location<=value.utf16.count,length<=value.utf16.count-location else {return nil}
    let start=String.Index(utf16Offset:location,in:value),end=String.Index(utf16Offset:location+length,in:value)
    guard start.samePosition(in:value.unicodeScalars) != nil,end.samePosition(in:value.unicodeScalars) != nil else {return nil}
    return value.replacingCharacters(in:start..<end,with:inserted)
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
