import CoreGraphics
import Foundation

// 解剖图数据 — react-body-highlighter (MIT, https://github.com/giavinh79/react-body-highlighter)
// 原始坐标 1:1 搬过来 (anteriorData / posteriorData), 没有 silhouette / 自创 sub 切片.
//
// 每个 polygon 5-12 vertex 手画风格, Strong / Hevy 同款.
// 坐标系: anterior 100 (x) × 200 (y), posterior 100 × 220 (在组装时 scaleY * 200/220 归一到 200).
// 上游源: https://raw.githubusercontent.com/giavinh79/react-body-highlighter/master/src/assets/index.ts

struct AnatomyPolygon: Hashable, Sendable {
    let muscle: MuscleGroup
    let points: [CGPoint]
}

enum BodyRegion: String, Hashable, Sendable {
    case upper
    case lower
    case full
}

// MARK: - 区域裁剪 viewBox (跟 web 同步)

extension BodyRegion {
    /// 返回 (yMin, height) — 给 BodyHint 计算 viewBox 用
    var viewBox: (yMin: CGFloat, height: CGFloat) {
        switch self {
        case .upper: return (0, 125)   // 头到下腹
        case .lower: return (95, 110)  // 髋到脚踝
        case .full:  return (0, 200)
        }
    }
}

// MARK: - 上 / 下肢分类

private let upperBodyMuscles: Set<MuscleGroup> = [
    .chest, .upperChest, .midChest, .lowerChest,
    .back, .lats, .upperLats, .lowerLats,
    .upperTraps, .midTraps, .lowerTraps, .rhomboids, .teres, .lowerBack,
    .shoulders, .frontDelts, .sideDelts, .rearDelts, .rotatorCuff,
    .biceps, .bicepsLong, .bicepsShort, .brachialis, .brachioradialis,
    .triceps, .tricepsLong, .tricepsLateral, .tricepsMedial,
    .forearms, .forearmFlexors, .forearmExtensors, .arms,
    .core, .abs, .upperAbs, .lowerAbs, .obliques, .serratus, .neck,
]

private let lowerBodyMuscles: Set<MuscleGroup> = [
    .legs, .quads, .rectusFemoris, .vastusLateralis, .vastusMedialis,
    .hamstrings, .bicepsFemoris, .semitendinosus,
    .glutes, .gluteusMaximus, .gluteusMedius,
    .calves, .gastrocnemius, .soleus, .tibialisAnterior, .adductors,
]

func detectBodyRegion(_ muscles: [MuscleGroup]) -> BodyRegion {
    guard !muscles.isEmpty else { return .full }
    var hasUpper = false
    var hasLower = false
    for m in muscles {
        if upperBodyMuscles.contains(m) { hasUpper = true }
        if lowerBodyMuscles.contains(m) { hasLower = true }
        if hasUpper && hasLower { return .full }
    }
    if hasUpper { return .upper }
    if hasLower { return .lower }
    return .full
}

// MARK: - 子肌肉 → 父肌肉 / 复合展开

private let directToMajor: [MuscleGroup: MuscleGroup] = [
    .upperChest: .chest, .midChest: .chest, .lowerChest: .chest,
    .upperLats: .back, .lowerLats: .back,
    .upperTraps: .back, .midTraps: .back, .lowerTraps: .back,
    .rhomboids: .back, .teres: .back, .lowerBack: .back,
    .frontDelts: .shoulders, .sideDelts: .shoulders, .rearDelts: .shoulders, .rotatorCuff: .shoulders,
    .tricepsLong: .triceps, .tricepsLateral: .triceps, .tricepsMedial: .triceps,
    .forearmFlexors: .forearms, .forearmExtensors: .forearms, .brachioradialis: .forearms,
    .upperAbs: .core, .lowerAbs: .core, .obliques: .core, .serratus: .core,
    .rectusFemoris: .quads, .vastusLateralis: .quads, .vastusMedialis: .quads,
    .bicepsFemoris: .hamstrings, .semitendinosus: .hamstrings,
    .gluteusMaximus: .glutes, .gluteusMedius: .glutes,
    .gastrocnemius: .calves, .soleus: .calves, .tibialisAnterior: .calves,
    .bicepsLong: .biceps, .bicepsShort: .biceps, .brachialis: .biceps,
]

private let composites: [MuscleGroup: [MuscleGroup]] = [
    .chest: [.upperChest, .midChest, .lowerChest],
    .back: [.upperLats, .lowerLats, .upperTraps, .midTraps, .lowerTraps, .rhomboids, .teres, .lowerBack],
    .lats: [.upperLats, .lowerLats, .teres],
    .shoulders: [.frontDelts, .sideDelts, .rearDelts, .rotatorCuff],
    .triceps: [.tricepsLong, .tricepsLateral, .tricepsMedial],
    .forearms: [.forearmFlexors, .forearmExtensors, .brachioradialis],
    .arms: [.biceps, .tricepsLong, .tricepsLateral, .tricepsMedial, .forearmFlexors, .forearmExtensors, .brachioradialis],
    .abs: [.upperAbs, .lowerAbs],
    .core: [.upperAbs, .lowerAbs, .obliques, .serratus],
    .quads: [.rectusFemoris, .vastusLateralis, .vastusMedialis],
    .hamstrings: [.bicepsFemoris, .semitendinosus],
    .glutes: [.gluteusMaximus, .gluteusMedius],
    .calves: [.gastrocnemius, .soleus, .tibialisAnterior],
    .legs: [.rectusFemoris, .vastusLateralis, .vastusMedialis, .bicepsFemoris, .semitendinosus, .gluteusMaximus, .gluteusMedius, .gastrocnemius, .soleus, .tibialisAnterior, .adductors],
    .biceps: [.bicepsLong, .bicepsShort, .brachialis],
]

/// 视觉代理 — 部分细分肌群在解剖图上没有独立 polygon, 选中时让它"借用"另一块视觉上最接近的 polygon 来亮起.
private let proxyAnatomy: [MuscleGroup: [MuscleGroup]] = [
    .sideDelts:        [.frontDelts],     // 中束 anterior view 跟前束相邻
    .rotatorCuff:      [.rearDelts],      // 肩袖深层, 用后束位置示意
    .rhomboids:        [.upperTraps],     // 菱形肌深植斜方下
    .teres:            [.upperLats],      // 大圆肌紧贴 lats 上端
    .brachialis:       [.biceps],         // 肱肌在二头深层
    .brachioradialis:  [.forearms],       // 肱桡肌跨肘, 跟前臂
    .tricepsMedial:    [.triceps],        // 内侧头被长/外侧头覆盖
    .serratus:         [.obliques],       // 前锯肌薄层, 跟腹斜相邻
    .midTraps:         [.upperTraps],     // upstream 只给一个 trapezius polygon
    .lowerTraps:       [.upperTraps],
    .lowerLats:        [.upperLats],      // upstream 只给一个 upper_back polygon
    .rectusFemoris:    [.quads],          // upstream 没切 RF/VL/VM, 全在 .quads 一组
    .vastusLateralis:  [.quads],
    .vastusMedialis:   [.quads],
    .bicepsFemoris:    [.hamstrings],
    .semitendinosus:   [.hamstrings],
    .gluteusMaximus:   [.glutes],
    .gluteusMedius:    [.glutes],
    .gastrocnemius:    [.calves],
    .soleus:           [.calves],
    .upperChest:       [.chest],
    .midChest:         [.chest],
    .lowerChest:       [.chest],
    .upperAbs:         [.abs],
    .lowerAbs:         [.abs],
    .bicepsLong:       [.biceps],
    .bicepsShort:      [.biceps],
    .tricepsLong:      [.triceps],
    .tricepsLateral:   [.triceps],
    .forearmFlexors:   [.forearms],
    .forearmExtensors: [.forearms],
]

func expandAnatomyMuscles(_ groups: [MuscleGroup]) -> Set<MuscleGroup> {
    var out: Set<MuscleGroup> = []
    for g in groups {
        out.insert(g)
        if let children = composites[g] { for c in children { out.insert(c) } }
        if let parent = directToMajor[g] { out.insert(parent) }
        if let proxies = proxyAnatomy[g] { for p in proxies { out.insert(p) } }
    }
    return out
}

// MARK: - polygon 字符串解析

private func parse(_ raw: String) -> [CGPoint] {
    let toks = raw.replacingOccurrences(of: ",", with: " ")
        .split(separator: " ", omittingEmptySubsequences: true)
        .compactMap { Double($0) }
    var pts: [CGPoint] = []
    var i = 0
    while i + 1 < toks.count {
        pts.append(CGPoint(x: toks[i], y: toks[i + 1]))
        i += 2
    }
    return pts
}

private func bounds(_ pts: [CGPoint]) -> (minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat) {
    guard let first = pts.first else { return (0, 0, 0, 0) }
    var b = (minX: first.x, maxX: first.x, minY: first.y, maxY: first.y)
    for p in pts.dropFirst() {
        if p.x < b.minX { b.minX = p.x }
        if p.x > b.maxX { b.maxX = p.x }
        if p.y < b.minY { b.minY = p.y }
        if p.y > b.maxY { b.maxY = p.y }
    }
    return b
}

/// 按 y 把 polygon 切成 n 个水平条 — 公用 helper, 当前数据不再调用, 留作未来扩展.
private func splitHorizontalY(_ pts: [CGPoint], _ n: Int) -> [[CGPoint]] {
    guard n > 0 else { return [] }
    let b = bounds(pts)
    let bandH = (b.maxY - b.minY) / CGFloat(n)
    var result: [[CGPoint]] = []
    for i in 0..<n {
        let yMin = b.minY + bandH * CGFloat(i)
        let yMax = yMin + bandH
        let band = clipBandY(pts, yMin: yMin, yMax: yMax)
        result.append(band)
    }
    return result
}

/// 对一个凸多边形做 y 范围裁剪 (Sutherland-Hodgman 简化版, 只处理水平裁剪线)
private func clipBandY(_ pts: [CGPoint], yMin: CGFloat, yMax: CGFloat) -> [CGPoint] {
    func clipAxis(_ input: [CGPoint], threshold: CGFloat, keepBelow: Bool) -> [CGPoint] {
        guard !input.isEmpty else { return [] }
        var out: [CGPoint] = []
        let n = input.count
        for i in 0..<n {
            let cur = input[i]
            let prev = input[(i + n - 1) % n]
            let curInside = keepBelow ? cur.y <= threshold : cur.y >= threshold
            let prevInside = keepBelow ? prev.y <= threshold : prev.y >= threshold
            if curInside {
                if !prevInside {
                    if let inter = intersectY(prev, cur, threshold) {
                        out.append(inter)
                    }
                }
                out.append(cur)
            } else if prevInside {
                if let inter = intersectY(prev, cur, threshold) {
                    out.append(inter)
                }
            }
        }
        return out
    }
    func intersectY(_ a: CGPoint, _ b: CGPoint, _ y: CGFloat) -> CGPoint? {
        let dy = b.y - a.y
        guard abs(dy) > 0.0001 else { return nil }
        let t = (y - a.y) / dy
        return CGPoint(x: a.x + (b.x - a.x) * t, y: y)
    }
    let step1 = clipAxis(pts, threshold: yMax, keepBelow: true)
    let step2 = clipAxis(step1, threshold: yMin, keepBelow: false)
    return step2
}

// MARK: - 原始 polygon 数据 (react-body-highlighter MIT, 1:1 搬运)

private struct R {
    // ==================== ANTERIOR (100 × 200) ====================

    // HEAD — 装饰 (.fullBody, 不参与点击)
    static let HEAD_A = "42.4489796 2.85714286 40 11.8367347 42.0408163 19.5918367 46.122449 23.2653061 49.7959184 25.3061224 54.6938776 22.4489796 57.5510204 19.1836735 59.1836735 10.2040816 57.1428571 2.44897959 49.7959184 0"

    // NECK
    static let NECK_A1 = "55.5102041 23.6734694 50.6122449 33.4693878 50.6122449 39.1836735 61.6326531 40 70.6122449 44.8979592 69.3877551 36.7346939 63.2653061 35.1020408 58.3673469 30.6122449"
    static let NECK_A2 = "28.9795918 44.8979592 30.2040816 37.1428571 36.3265306 35.1020408 41.2244898 30.2040816 44.4897959 24.4897959 48.9795918 33.877551 48.5714286 39.1836735 37.9591837 39.5918367"

    // FRONT DELTOIDS
    static let FD_A1 = "78.3673469 53.0612245 79.5918367 47.755102 79.1836735 41.2244898 75.9183673 37.9591837 71.0204082 36.3265306 72.244898 42.8571429 71.4285714 47.3469388"
    static let FD_A2 = "28.1632653 47.3469388 21.2244898 53.0612245 20 47.755102 20.4081633 40.8163265 24.4897959 37.1428571 28.5714286 37.1428571 26.9387755 43.2653061"

    // CHEST
    static let CHEST_A1 = "51.8367347 41.6326531 51.0204082 55.1020408 57.9591837 57.9591837 67.755102 55.5102041 70.6122449 47.3469388 62.0408163 41.6326531"
    static let CHEST_A2 = "29.7959184 46.5306122 31.4285714 55.5102041 40.8163265 57.9591837 48.1632653 55.1020408 47.755102 42.0408163 37.5510204 42.0408163"

    // OBLIQUES
    static let OBL_A1 = "68.5714286 63.2653061 67.3469388 57.1428571 58.7755102 59.5918367 60 64.0816327 60.4081633 83.2653061 65.7142857 78.7755102 66.5306122 69.7959184"
    static let OBL_A2 = "33.877551 78.3673469 33.0612245 71.8367347 31.0204082 63.2653061 32.244898 57.1428571 40.8163265 59.1836735 39.1836735 63.2653061 39.1836735 83.6734694"

    // ABS
    static let ABS_A1 = "56.3265306 59.1836735 57.9591837 64.0816327 58.3673469 77.9591837 58.3673469 92.6530612 56.3265306 98.3673469 55.1020408 104.081633 51.4285714 107.755102 51.0204082 84.4897959 50.6122449 67.3469388 51.0204082 57.1428571"
    static let ABS_A2 = "43.6734694 58.7755102 48.5714286 57.1428571 48.9795918 67.3469388 48.5714286 84.4897959 48.1632653 107.346939 44.4897959 103.673469 40.8163265 91.4285714 40.8163265 78.3673469 41.2244898 64.4897959"

    // BICEPS
    static let BIC_A1 = "16.7346939 68.1632653 17.9591837 71.4285714 22.8571429 66.122449 28.9795918 53.877551 27.755102 49.3877551 20.4081633 55.9183673"
    static let BIC_A2 = "71.4285714 49.3877551 70.2040816 54.6938776 76.3265306 66.122449 81.6326531 71.8367347 82.8571429 68.9795918 78.7755102 55.5102041"

    // TRICEPS (anterior sliver)
    static let TRI_A1 = "69.3877551 55.5102041 69.3877551 61.6326531 75.9183673 72.6530612 77.5510204 70.2040816 75.5102041 67.3469388"
    static let TRI_A2 = "22.4489796 69.3877551 29.7959184 55.5102041 29.7959184 60.8163265 22.8571429 73.0612245"

    // FOREARM (anterior, 4 polys)
    static let FORE_A1 = "6.12244898 88.5714286 10.2040816 75.1020408 14.6938776 70.2040816 16.3265306 74.2857143 19.1836735 73.4693878 4.48979592 97.5510204 0 100"
    static let FORE_A2 = "84.4897959 69.7959184 83.2653061 73.4693878 80 73.0612245 95.1020408 98.3673469 100 100.408163 93.4693878 89.3877551 89.7959184 76.3265306"
    static let FORE_A3 = "77.5510204 72.244898 77.5510204 77.5510204 80.4081633 84.0816327 85.3061224 89.7959184 92.244898 101.22449 94.6938776 99.5918367"
    static let FORE_A4 = "6.93877551 101.22449 13.4693878 90.6122449 18.7755102 84.0816327 21.6326531 77.1428571 21.2244898 71.8367347 4.89795918 98.7755102"

    // ADDUCTORS (上游 ABDUCTORS, 是内收位置)
    static let ADD_A1 = "52.6530612 110.204082 54.2857143 124.897959 60 110.204082 62.0408163 100 64.8979592 94.2857143 60 92.6530612 56.7346939 104.489796"
    static let ADD_A2 = "47.755102 110.612245 44.8979592 125.306122 42.0408163 115.918367 40.4081633 113.061224 39.5918367 107.346939 37.9591837 102.44898 34.6938776 93.877551 39.5918367 92.244898 41.6326531 99.1836735 43.6734694 105.306122"

    // QUADRICEPS (6 polys)
    static let QUAD_A1 = "34.6938776 98.7755102 37.1428571 108.163265 37.1428571 127.755102 34.2857143 137.142857 31.0204082 132.653061 29.3877551 120 28.1632653 111.428571 29.3877551 100.816327 32.244898 94.6938776"
    static let QUAD_A2 = "63.2653061 105.714286 64.4897959 100 66.9387755 94.6938776 70.2040816 101.22449 71.0204082 111.836735 68.1632653 133.061224 65.3061224 137.55102 62.4489796 128.571429 62.0408163 111.428571"
    static let QUAD_A3 = "38.7755102 129.387755 38.3673469 112.244898 41.2244898 118.367347 44.4897959 129.387755 42.8571429 135.102041 40 146.122449 36.3265306 146.530612 35.5102041 140"
    static let QUAD_A4 = "59.5918367 145.714286 55.5102041 128.979592 60.8163265 113.877551 61.2244898 130.204082 64.0816327 139.591837 62.8571429 146.530612"
    static let QUAD_A5 = "32.6530612 138.367347 26.5306122 145.714286 25.7142857 136.734694 25.7142857 127.346939 26.9387755 114.285714 29.3877551 133.469388"
    static let QUAD_A6 = "71.8367347 113.061224 73.877551 124.081633 73.877551 140.408163 72.6530612 145.714286 66.5306122 138.367347 70.2040816 133.469388"

    // CALVES (anterior = 胫骨前肌 tibialis anterior, 4 polys)
    static let CALF_A1 = "71.4285714 160.408163 73.4693878 153.469388 76.7346939 161.22449 79.5918367 167.755102 78.3673469 187.755102 79.5918367 195.510204 74.6938776 195.510204"
    static let CALF_A2 = "24.8979592 194.693878 27.755102 164.897959 28.1632653 160.408163 26.122449 154.285714 24.8979592 157.55102 22.4489796 161.632653 20.8163265 167.755102 22.0408163 188.163265 20.8163265 195.510204"
    static let CALF_A3 = "72.6530612 195.102041 69.7959184 159.183673 65.3061224 158.367347 64.0816327 162.44898 64.0816327 165.306122 65.7142857 177.142857"
    static let CALF_A4 = "35.5102041 158.367347 35.9183673 162.44898 35.9183673 166.938776 35.1020408 172.244898 35.1020408 176.734694 32.244898 182.040816 30.6122449 187.346939 26.9387755 194.693878 27.3469388 187.755102 28.1632653 180.408163 28.5714286 175.510204 28.9795918 169.795918 29.7959184 164.081633 30.2040816 158.77551"

    // ==================== POSTERIOR (100 × 220, scaleY * 200/220 在组装时) ====================

    // HEAD
    static let HEAD_P = "50.6382979 0 45.9574468 0.85106383 40.8510638 5.53191489 40.4255319 12.7659574 45.106383 20 55.7446809 20 59.1489362 13.6170213 59.5744681 4.68085106 55.7446809 1.27659574"

    // TRAPEZIUS
    static let TRAP_P1 = "44.6808511 21.7021277 47.6595745 21.7021277 47.2340426 38.2978723 47.6595745 64.6808511 38.2978723 53.1914894 35.3191489 40.8510638 31.0638298 36.5957447 39.1489362 33.1914894 43.8297872 27.2340426"
    static let TRAP_P2 = "52.3404255 21.7021277 55.7446809 21.7021277 56.5957447 27.2340426 60.8510638 32.7659574 68.9361702 36.5957447 64.6808511 40.4255319 61.7021277 53.1914894 52.3404255 64.6808511 53.1914894 38.2978723"

    // BACK DELTOIDS
    static let BD_P1 = "29.3617021 37.0212766 22.9787234 39.1489362 17.4468085 44.2553191 18.2978723 53.6170213 24.2553191 49.3617021 27.2340426 46.3829787"
    static let BD_P2 = "71.0638298 37.0212766 78.2978723 39.5744681 82.5531915 44.6808511 81.7021277 53.6170213 74.893617 48.9361702 72.3404255 45.106383"

    // UPPER BACK (lats)
    static let LAT_P1 = "31.0638298 38.7234043 28.0851064 48.9361702 28.5106383 55.3191489 34.0425532 75.3191489 47.2340426 71.0638298 47.2340426 66.3829787 36.5957447 54.0425532 33.6170213 41.2765957"
    static let LAT_P2 = "68.9361702 38.7234043 71.9148936 49.3617021 71.4893617 56.1702128 65.9574468 75.3191489 52.7659574 71.0638298 52.7659574 66.3829787 63.4042553 54.4680851 66.3829787 41.7021277"

    // TRICEPS (posterior, 4 polys)
    static let TRI_P1 = "26.8085106 49.787234 17.8723404 55.7446809 14.4680851 72.3404255 16.5957447 81.7021277 21.7021277 63.8297872 26.8085106 55.7446809"
    static let TRI_P2 = "73.6170213 50.212766 82.1276596 55.7446809 85.9574468 73.1914894 83.4042553 82.1276596 77.8723404 62.9787234 73.1914894 55.7446809"
    static let TRI_P3 = "26.8085106 58.2978723 26.8085106 68.5106383 22.9787234 75.3191489 19.1489362 77.4468085 22.5531915 65.5319149"
    static let TRI_P4 = "72.7659574 58.2978723 77.0212766 64.6808511 80.4255319 77.4468085 76.5957447 75.3191489 72.7659574 68.9361702"

    // LOWER BACK
    static let LB_P1 = "47.6595745 72.7659574 34.4680851 77.0212766 35.3191489 83.4042553 49.3617021 102.12766 46.8085106 82.9787234"
    static let LB_P2 = "52.3404255 72.7659574 65.5319149 77.0212766 64.6808511 83.4042553 50.6382979 102.12766 53.1914894 83.8297872"

    // FOREARM (posterior, 4 polys)
    static let FORE_P1 = "86.3829787 75.7446809 91.0638298 83.4042553 93.1914894 94.0425532 100 106.382979 96.1702128 104.255319 88.0851064 89.3617021 84.2553191 83.8297872"
    static let FORE_P2 = "13.6170213 75.7446809 8.93617021 83.8297872 6.80851064 93.6170213 0 106.382979 3.82978723 104.255319 12.3404255 88.5106383 15.7446809 82.9787234"
    static let FORE_P3 = "81.2765957 79.5744681 77.4468085 77.8723404 79.1489362 84.6808511 91.0638298 103.829787 93.1914894 108.93617 94.4680851 104.680851"
    static let FORE_P4 = "18.7234043 79.5744681 22.1276596 77.8723404 20.8510638 84.2553191 9.36170213 102.978723 6.80851064 108.510638 5.10638298 104.680851"

    // GLUTEAL
    static let GL_P1 = "44.6808511 99.5744681 30.212766 108.510638 29.787234 118.723404 31.4893617 125.957447 47.2340426 121.276596 49.3617021 114.893617"
    static let GL_P2 = "55.3191489 99.1489362 51.0638298 114.468085 52.3404255 120.851064 68.0851064 125.957447 69.787234 119.148936 69.3617021 108.510638"

    // ABDUCTOR (gluteus medius region)
    static let ABD_P1 = "48.0851064 122.978723 44.6808511 122.978723 41.2765957 125.531915 45.106383 144.255319 48.5106383 135.744681 48.9361702 129.361702"
    static let ABD_P2 = "51.9148936 122.553191 55.7446809 123.404255 59.1489362 125.957447 54.893617 144.255319 51.9148936 136.170213 51.0638298 129.361702"

    // HAMSTRING (4 polys)
    static let HAM_P1 = "28.9361702 122.12766 31.0638298 129.361702 36.5957447 125.957447 35.3191489 135.319149 34.4680851 150.212766 29.3617021 158.297872 28.9361702 146.808511 27.6595745 141.276596 27.2340426 131.489362"
    static let HAM_P2 = "71.4893617 121.702128 69.3617021 128.93617 63.8297872 125.957447 65.5319149 136.595745 66.3829787 150.212766 71.0638298 158.297872 71.4893617 147.659574 72.7659574 142.12766 73.6170213 131.914894"
    static let HAM_P3 = "38.7234043 125.531915 44.2553191 145.957447 40.4255319 166.808511 36.1702128 152.765957 37.0212766 135.319149"
    static let HAM_P4 = "61.7021277 125.531915 63.4042553 136.170213 64.2553191 153.191489 60 166.808511 56.1702128 146.382979"

    // CALVES (posterior, 4 polys)
    static let CALF_P1 = "29.3617021 160.425532 28.5106383 167.234043 24.6808511 179.574468 23.8297872 192.765957 25.5319149 197.021277 28.5106383 193.191489 29.787234 180 31.9148936 171.06383 31.9148936 166.808511"
    static let CALF_P2 = "37.4468085 165.106383 35.3191489 167.659574 33.1914894 171.914894 31.0638298 180.425532 30.212766 191.914894 34.0425532 200 38.7234043 190.638298 39.1489362 168.93617"
    static let CALF_P3 = "62.9787234 165.106383 61.2765957 168.510638 61.7021277 190.638298 66.3829787 199.574468 70.6382979 191.914894 68.9361702 179.574468 66.8085106 170.212766"
    static let CALF_P4 = "70.6382979 160.425532 72.3404255 168.510638 75.7446809 179.148936 76.5957447 192.765957 74.4680851 196.595745 72.3404255 193.617021 70.6382979 179.574468 68.0851064 168.085106"

    // SOLEUS
    static let SOL_PL = "28.5106383 195.744681 30.212766 195.744681 33.6170213 201.702128 30.6382979 220 28.5106383 213.617021 26.8085106 198.297872"
    static let SOL_PR = "69.787234 195.744681 71.9148936 195.744681 73.6170213 198.297872 71.9148936 213.191489 70.212766 219.574468 67.2340426 202.12766"
}

private func scaleY(_ pts: [CGPoint], _ factor: CGFloat) -> [CGPoint] {
    pts.map { CGPoint(x: $0.x, y: $0.y * factor) }
}

private let posteriorScale: CGFloat = 200.0 / 220.0

// MARK: - 组装 ANTERIOR / POSTERIOR

/// HEAD 用 .fullBody — 渲染时填 idleGray, 不参与点击命中
let ANTERIOR: [AnatomyPolygon] = [
    // 头 (装饰)
    AnatomyPolygon(muscle: .fullBody, points: parse(R.HEAD_A)),
    // 颈
    AnatomyPolygon(muscle: .neck, points: parse(R.NECK_A1)),
    AnatomyPolygon(muscle: .neck, points: parse(R.NECK_A2)),
    // 前束
    AnatomyPolygon(muscle: .frontDelts, points: parse(R.FD_A1)),
    AnatomyPolygon(muscle: .frontDelts, points: parse(R.FD_A2)),
    // 胸
    AnatomyPolygon(muscle: .chest, points: parse(R.CHEST_A1)),
    AnatomyPolygon(muscle: .chest, points: parse(R.CHEST_A2)),
    // 腹外斜
    AnatomyPolygon(muscle: .obliques, points: parse(R.OBL_A1)),
    AnatomyPolygon(muscle: .obliques, points: parse(R.OBL_A2)),
    // 腹
    AnatomyPolygon(muscle: .abs, points: parse(R.ABS_A1)),
    AnatomyPolygon(muscle: .abs, points: parse(R.ABS_A2)),
    // 二头
    AnatomyPolygon(muscle: .biceps, points: parse(R.BIC_A1)),
    AnatomyPolygon(muscle: .biceps, points: parse(R.BIC_A2)),
    // 三头前侧
    AnatomyPolygon(muscle: .triceps, points: parse(R.TRI_A1)),
    AnatomyPolygon(muscle: .triceps, points: parse(R.TRI_A2)),
    // 前臂
    AnatomyPolygon(muscle: .forearms, points: parse(R.FORE_A1)),
    AnatomyPolygon(muscle: .forearms, points: parse(R.FORE_A2)),
    AnatomyPolygon(muscle: .forearms, points: parse(R.FORE_A3)),
    AnatomyPolygon(muscle: .forearms, points: parse(R.FORE_A4)),
    // 内收
    AnatomyPolygon(muscle: .adductors, points: parse(R.ADD_A1)),
    AnatomyPolygon(muscle: .adductors, points: parse(R.ADD_A2)),
    // 股四头 (6 polys, 都归 .quads)
    AnatomyPolygon(muscle: .quads, points: parse(R.QUAD_A1)),
    AnatomyPolygon(muscle: .quads, points: parse(R.QUAD_A2)),
    AnatomyPolygon(muscle: .quads, points: parse(R.QUAD_A3)),
    AnatomyPolygon(muscle: .quads, points: parse(R.QUAD_A4)),
    AnatomyPolygon(muscle: .quads, points: parse(R.QUAD_A5)),
    AnatomyPolygon(muscle: .quads, points: parse(R.QUAD_A6)),
    // 胫骨前肌 (anterior calves)
    AnatomyPolygon(muscle: .tibialisAnterior, points: parse(R.CALF_A1)),
    AnatomyPolygon(muscle: .tibialisAnterior, points: parse(R.CALF_A2)),
    AnatomyPolygon(muscle: .tibialisAnterior, points: parse(R.CALF_A3)),
    AnatomyPolygon(muscle: .tibialisAnterior, points: parse(R.CALF_A4)),
].compactMap { $0.points.isEmpty ? nil : $0 }

let POSTERIOR: [AnatomyPolygon] = [
    // 头
    AnatomyPolygon(muscle: .fullBody, points: scaleY(parse(R.HEAD_P), posteriorScale)),
    // 斜方 (upstream 只一段, 都归 .upperTraps)
    AnatomyPolygon(muscle: .upperTraps, points: scaleY(parse(R.TRAP_P1), posteriorScale)),
    AnatomyPolygon(muscle: .upperTraps, points: scaleY(parse(R.TRAP_P2), posteriorScale)),
    // 后束
    AnatomyPolygon(muscle: .rearDelts, points: scaleY(parse(R.BD_P1), posteriorScale)),
    AnatomyPolygon(muscle: .rearDelts, points: scaleY(parse(R.BD_P2), posteriorScale)),
    // 阔背 (upstream 只一段, 都归 .upperLats)
    AnatomyPolygon(muscle: .upperLats, points: scaleY(parse(R.LAT_P1), posteriorScale)),
    AnatomyPolygon(muscle: .upperLats, points: scaleY(parse(R.LAT_P2), posteriorScale)),
    // 三头 (后侧, 4 polys)
    AnatomyPolygon(muscle: .triceps, points: scaleY(parse(R.TRI_P1), posteriorScale)),
    AnatomyPolygon(muscle: .triceps, points: scaleY(parse(R.TRI_P2), posteriorScale)),
    AnatomyPolygon(muscle: .triceps, points: scaleY(parse(R.TRI_P3), posteriorScale)),
    AnatomyPolygon(muscle: .triceps, points: scaleY(parse(R.TRI_P4), posteriorScale)),
    // 下背
    AnatomyPolygon(muscle: .lowerBack, points: scaleY(parse(R.LB_P1), posteriorScale)),
    AnatomyPolygon(muscle: .lowerBack, points: scaleY(parse(R.LB_P2), posteriorScale)),
    // 前臂
    AnatomyPolygon(muscle: .forearms, points: scaleY(parse(R.FORE_P1), posteriorScale)),
    AnatomyPolygon(muscle: .forearms, points: scaleY(parse(R.FORE_P2), posteriorScale)),
    AnatomyPolygon(muscle: .forearms, points: scaleY(parse(R.FORE_P3), posteriorScale)),
    AnatomyPolygon(muscle: .forearms, points: scaleY(parse(R.FORE_P4), posteriorScale)),
    // 臀
    AnatomyPolygon(muscle: .glutes, points: scaleY(parse(R.GL_P1), posteriorScale)),
    AnatomyPolygon(muscle: .glutes, points: scaleY(parse(R.GL_P2), posteriorScale)),
    // 外展 (臀中肌)
    AnatomyPolygon(muscle: .gluteusMedius, points: scaleY(parse(R.ABD_P1), posteriorScale)),
    AnatomyPolygon(muscle: .gluteusMedius, points: scaleY(parse(R.ABD_P2), posteriorScale)),
    // 腘绳 (4 polys)
    AnatomyPolygon(muscle: .hamstrings, points: scaleY(parse(R.HAM_P1), posteriorScale)),
    AnatomyPolygon(muscle: .hamstrings, points: scaleY(parse(R.HAM_P2), posteriorScale)),
    AnatomyPolygon(muscle: .hamstrings, points: scaleY(parse(R.HAM_P3), posteriorScale)),
    AnatomyPolygon(muscle: .hamstrings, points: scaleY(parse(R.HAM_P4), posteriorScale)),
    // 小腿 (后侧)
    AnatomyPolygon(muscle: .calves, points: scaleY(parse(R.CALF_P1), posteriorScale)),
    AnatomyPolygon(muscle: .calves, points: scaleY(parse(R.CALF_P2), posteriorScale)),
    AnatomyPolygon(muscle: .calves, points: scaleY(parse(R.CALF_P3), posteriorScale)),
    AnatomyPolygon(muscle: .calves, points: scaleY(parse(R.CALF_P4), posteriorScale)),
    // 比目鱼
    AnatomyPolygon(muscle: .soleus, points: scaleY(parse(R.SOL_PL), posteriorScale)),
    AnatomyPolygon(muscle: .soleus, points: scaleY(parse(R.SOL_PR), posteriorScale)),
].compactMap { $0.points.isEmpty ? nil : $0 }

// MARK: - 视图尺寸常量

enum AnatomyView {
    static let width: CGFloat = 100
    static let height: CGFloat = 200
}
