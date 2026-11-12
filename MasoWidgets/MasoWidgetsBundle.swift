import SwiftUI
import WidgetKit

// Home Screen widgets and the existing training Live Activity share one extension.
@main
struct MasoWidgetsBundle: WidgetBundle {
    var body: some Widget {
        MassoDailyOverviewWidget()
        MassoDailyRingWidget()
        MassoDietProgressWidget()
        MassoSleepProgressWidget()
        MasoTrainingLiveActivity()
    }
}
