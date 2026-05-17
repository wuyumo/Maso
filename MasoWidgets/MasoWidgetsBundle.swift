import SwiftUI
import WidgetKit

// Widget extension 入口 — 只声明 Maso 的 Live Activity widget.
// 暂时没传统 Home Screen widget; 后续要加直接在 body 加.
@main
struct MasoWidgetsBundle: WidgetBundle {
    var body: some Widget {
        MasoTrainingLiveActivity()
    }
}
