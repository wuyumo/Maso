// Converts the approved demo's GLB buffers directly, without changing its geometry.
import Foundation
import SceneKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = root.appendingPathComponent("design/muscle-3d-demo/imported-ecorche/assets/ecorche-arms-preview.glb")
let output = root.appendingPathComponent("Maso/Resources/Anatomy")
let data = try Data(contentsOf: source)
func uint32(_ offset: Int) -> Int {
    Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }.littleEndian)
}
let jsonSize = uint32(12)
let document = try JSONSerialization.jsonObject(with: data.subdata(in: 20..<(20 + jsonSize))) as! [String: Any]
let binaryStart = 28 + jsonSize
let accessors = document["accessors"] as! [[String: Any]]
let views = document["bufferViews"] as! [[String: Any]]
let meshes = document["meshes"] as! [[String: Any]]
func buffer(_ id: Int) -> (Data, Int, Int) {
    let accessor = accessors[id], view = views[accessor["bufferView"] as! Int]
    let count = accessor["count"] as! Int
    let width = accessor["type"] as! String == "VEC3" ? 3 : 1
    let bytes = (accessor["componentType"] as! Int) == 5123 ? 2 : 4
    let stride = view["byteStride"] as? Int ?? width * bytes
    let start = binaryStart + (view["byteOffset"] as? Int ?? 0) + (accessor["byteOffset"] as? Int ?? 0)
    precondition(stride == width * bytes, "Expected packed approved GLB buffers")
    return (data.subdata(in: start..<(start + count * stride)), count, bytes)
}
let scene = SCNScene()
var mapping = [[String: Any]]()
var triangles = 0
for node in document["nodes"] as! [[String: Any]] {
    guard let meshIndex = node["mesh"] as? Int else { continue }
    let primitive = (meshes[meshIndex]["primitives"] as! [[String: Any]])[0]
    let attributes = primitive["attributes"] as! [String: Int]
    let (positions, count, _) = buffer(attributes["POSITION"]!)
    let (normals, _, _) = buffer(attributes["NORMAL"]!)
    let (indices, indexCount, indexSize) = buffer(primitive["indices"] as! Int)
    let geometry = SCNGeometry(sources: [
        SCNGeometrySource(data: positions, semantic: .vertex, vectorCount: count, usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12),
        SCNGeometrySource(data: normals, semantic: .normal, vectorCount: count, usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12)
    ], elements: [SCNGeometryElement(data: indices, primitiveType: .triangles, primitiveCount: indexCount / 3, bytesPerIndex: indexSize)])
    let material = SCNMaterial()
    material.lightingModel = .physicallyBased
    material.roughness.contents = 0.78
    material.metalness.contents = 0.0
    geometry.materials = [material]
    let meshNode = SCNNode(geometry: geometry)
    meshNode.name = node["name"] as? String
    scene.rootNode.addChildNode(meshNode)
    let extras = node["extras"] as! [String: Any]
    mapping.append(["node": meshNode.name!, "muscles": extras["muscleGroups"]!, "fatigueEligible": extras["fatigueEligible"]!])
    triangles += indexCount / 3
}
precondition(mapping.count == 37 && mapping.filter { $0["fatigueEligible"] as! Bool }.count == 32)
let sceneURL = output.appendingPathComponent("MuscleBody.scn")
precondition(scene.write(to: sceneURL, options: nil, delegate: nil, progressHandler: nil))
try JSONSerialization.data(withJSONObject: mapping, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("MuscleBodyMapping.json"))
let reloaded = try SCNScene(url: sceneURL)
precondition(reloaded.rootNode.childNodes.count == 37)
precondition(reloaded.rootNode.childNodes.reduce(0) { $0 + ($1.geometry?.elements.first?.primitiveCount ?? 0) } == triangles)
print("Exported and reloaded \(mapping.count) native meshes, \(triangles) unchanged triangles")
