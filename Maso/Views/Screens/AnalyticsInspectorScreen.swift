#if DEBUG
import SwiftUI

// 本地分析事件查看器 (仅 DEBUG) — 让 owner 在自己机器上**看到事件真的在触发**.
// 只读: 列出 Analytics.shared 缓冲里的事件 (newest first), 显示名称 + 时间 + 属性, 顶部给总数 + anon_id.
// Phase 0 默认 NoOpSink (事件不离开设备), 这屏就是 option (a) 的"自查" 价值落点.
// 入口: Settings → Debug → "Analytics events". 整文件被 #if DEBUG 包裹 → Release/上架包不编译.
struct AnalyticsInspectorScreen: View {
    @State private var analytics = Analytics.shared

    private var events: [AnalyticsEvent] {
        analytics.buffer.reversed()   // newest first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if events.isEmpty {
                    Text("No events buffered yet.\nUse the app and come back.")
                        .font(.system(size: 14))
                        .foregroundStyle(MasoColor.textDim)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 60)
                } else {
                    ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                        eventRow(event)
                    }
                }
            }
            .padding(MasoMetrics.pagePaddingHorizontal)
        }
        .background(MasoColor.background.ignoresSafeArea())
        .navigationTitle("Analytics events")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(analytics.buffer.count) events buffered")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(MasoColor.text)
            Text("anon_id: \(analytics.anonymousId)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(MasoColor.textDim)
                .textSelection(.enabled)
            Text("Phase 0: NoOpSink — nothing leaves this device.")
                .font(.system(size: 12))
                .foregroundStyle(MasoColor.textDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(MasoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func eventRow(_ event: AnalyticsEvent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(event.name)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(MasoColor.accent)
                Spacer(minLength: 8)
                Text(Self.timeFormatter.string(from: event.ts))
                    .font(.system(size: 11))
                    .foregroundStyle(MasoColor.textDim)
            }
            if !event.props.isEmpty {
                ForEach(event.props.keys.sorted(), id: \.self) { key in
                    HStack(spacing: 6) {
                        Text(key)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(MasoColor.textDim)
                        Text(event.props[key]?.displayValue ?? "")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(MasoColor.text)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(MasoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        return f
    }()
}
#endif
