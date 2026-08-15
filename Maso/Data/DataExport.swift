import Foundation

// 训练数据导出 —— 让用户随时能把自己的东西带走.
//
// 为什么值得做 (2026-08 竞品调研): 品类第二大痛点就是"改版倒退 + 历史数据把人锁死"。
// 原话: "feel locked in because all my old workout history is stored here"。
// 而扫完 13 个竞品 4300 条评论, **没有一家因为数据可导出被夸过** —— 因为几乎没人做。
//
// Masso 本来就是本地存储、无账号, 导出对我们几乎零成本, 却正好戳在别人流血的地方。
// 这不是"迁移走"的功能, 是"你随时能走, 所以你敢留下"的功能。
enum DataExport {

    /// 导出产物 — 两个文件一起丢进系统分享面板.
    struct Bundle {
        let jsonURL: URL   // 全量, 可完整还原
        let csvURL: URL    // 逐组明细, Excel / Numbers / Google Sheets 直接打开
    }

    /// 全量快照的外层信封 —— 带上版本号和导出时间, 以后要做"导入"时能识别格式.
    private struct Envelope: Encodable {
        let format = "masso.export.v1"
        let exportedAt: Date
        let appVersion: String
        let plans: [Plan]
        let sets: [SetRecord]
        let settings: UserSettings
    }

    /// 生成两个临时文件. 调用方拿去喂 UIActivityViewController.
    /// 抛错 → 调用方给用户一句失败提示 (不要静默, 这个功能的全部意义就是可信).
    @MainActor
    static func makeBundle(from data: DataStore) throws -> Bundle {
        let version = Foundation.Bundle.main
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let env = Envelope(exportedAt: Date(), appVersion: version,
                           plans: data.plans, sets: data.sets, settings: data.settings)

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        let json = try enc.encode(env)

        let stamp = Self.fileStamp(Date())
        let dir = FileManager.default.temporaryDirectory
        let jsonURL = dir.appendingPathComponent("masso-backup-\(stamp).json")
        let csvURL = dir.appendingPathComponent("masso-workouts-\(stamp).csv")
        try json.write(to: jsonURL, options: .atomic)
        try Data(csv(from: data.sets).utf8).write(to: csvURL, options: .atomic)
        return Bundle(jsonURL: jsonURL, csvURL: csvURL)
    }

    /// 逐组明细 CSV. 重量恒用 **kg** 落列 (导出是数据不是界面 —— 换个单位就对不上历史了),
    /// 列名里写清单位, 用户自己换算。
    static func csv(from sets: [SetRecord]) -> String {
        var out = "date,exercise,category,weight_kg,reps,duration_seconds,routine\n"
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        for s in sets.sorted(by: { $0.performedAt < $1.performedAt }) {
            let cols = [
                iso.string(from: s.performedAt),
                s.exerciseName,
                s.category.rawValue,
                s.weight.map { String(format: "%g", $0) } ?? "",
                s.reps.map(String.init) ?? "",
                s.duration.map(String.init) ?? "",
                s.planName ?? "",
            ]
            out += cols.map(escape).joined(separator: ",") + "\n"
        }
        return out
    }

    /// CSV 转义 —— 动作名和 routine 名是用户自由输入, 里面真的会有逗号/引号/换行.
    private static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// 文件名时间戳 —— 用户会连续导好几次, 名字必须能区分, 且不能带 `:` (会被某些网盘拒).
    private static func fileStamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return f.string(from: date)
    }
}

#if DEBUG
extension DataExport {
    /// 自检 — CSV 转义是唯一有分支的逻辑, 用户自由输入真的会打进来.
    static func _selfCheck() {
        assert(escape("Bench Press") == "Bench Press")
        assert(escape("Row (Cable, Seated)") == "\"Row (Cable, Seated)\"")
        assert(escape("He said \"go\"") == "\"He said \"\"go\"\"\"")
        let rows = csv(from: []).split(separator: "\n")
        assert(rows.count == 1 && rows[0].hasPrefix("date,exercise"))
    }
}
#endif
