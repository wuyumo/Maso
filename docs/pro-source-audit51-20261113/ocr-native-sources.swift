import Foundation
import Vision
import AppKit
let input=URL(fileURLWithPath:CommandLine.arguments[1])
let rows=try JSONSerialization.jsonObject(with:Data(contentsOf:input)) as! [[String:Any]]
var output=[[String:Any]]()
for row in rows {
 var result=row
 do {
  let request=VNRecognizeTextRequest();request.recognitionLevel = .accurate;request.usesLanguageCorrection=false
  let supported=try request.supportedRecognitionLanguages()
  request.recognitionLanguages=[row["visionLocale"] as! String,"en-US"].filter{supported.contains($0)}
  let image=NSImage(contentsOfFile:row["path"] as! String)!
  let cg=image.cgImage(forProposedRect:nil,context:nil,hints:nil)!
  try VNImageRequestHandler(cgImage:cg,options:[:]).perform([request])
  result["recognizedLines"]=(request.results ?? []).compactMap { item -> [String:Any]? in
   guard let text=item.topCandidates(1).first else {return nil}
   return ["text":text.string,"confidence":text.confidence,"x":item.boundingBox.minX,"y":item.boundingBox.minY,"width":item.boundingBox.width,"height":item.boundingBox.height]
  }
 } catch {result["error"]=String(describing:error)}
 output.append(result)
}
let data=try JSONSerialization.data(withJSONObject:output,options:[.prettyPrinted,.sortedKeys])
try data.write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
print("OCR sources: \(output.count); no images modified")
