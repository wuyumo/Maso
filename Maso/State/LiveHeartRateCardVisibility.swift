import CoreGraphics
import SwiftUI

// iPhone live heart-rate card — presence only.
//
// The training screen and the playlist are the same fullScreenCover. The
// playlist is the bottom drawer (`playlistHeight`), not a separate route.
// It is open from the start (default height), by dragging the handle up,
// or by tapping the handle. All of those write `playlistHeight`. Collapsing
// back to the handle (`playlistMinHeight`) is "return to the training stage".
//
// Other covers (exercise detail, edit, adjust, add, end confirm) are sheets
// on top of whichever surface is already showing. They are intentionally not
// inputs here: opening one must not hide the card by itself.
//
// This does not start, stop, or retarget heart-rate collection. The watch
// footer still decides when a sample is on screen. There is no heart-rate
// card view in this revision — the ripple treatment belongs to that other
// change. `LiveHeartRateCardSlot` is the only mount so a later visual stays
// behind this gate instead of being restyled here.

enum LiveHeartRateCardVisibility {
    /// Same slack PlanPlayerScreen used for `playlistExpanded`.
    static let playlistOpenSlack: CGFloat = 40

    static func playlistPresented(height: CGFloat, collapsedHeight: CGFloat) -> Bool {
        height > collapsedHeight + playlistOpenSlack
    }

    /// True only while the in-progress training stage is the foreground.
    /// Playlist open → false, even though the session is still running.
    /// Session ended or not started → false, so nothing is left on screen.
    static func showsCard(sessionActive: Bool, playlistPresented: Bool) -> Bool {
        sessionActive && !playlistPresented
    }
}

struct LiveHeartRateCardNavigation: Equatable {
    var sessionActive: Bool
    var playlistHeight: CGFloat
    var collapsedHeight: CGFloat

    var showsCard: Bool {
        LiveHeartRateCardVisibility.showsCard(
            sessionActive: sessionActive,
            playlistPresented: LiveHeartRateCardVisibility.playlistPresented(
                height: playlistHeight,
                collapsedHeight: collapsedHeight
            )
        )
    }

    func openPlaylist(height: CGFloat) -> LiveHeartRateCardNavigation {
        var copy = self
        copy.playlistHeight = height
        return copy
    }

    func returnToTraining() -> LiveHeartRateCardNavigation {
        var copy = self
        copy.playlistHeight = collapsedHeight
        return copy
    }

    func endSession() -> LiveHeartRateCardNavigation {
        var copy = self
        copy.sessionActive = false
        return copy
    }
}

/// Mount point for the training-stage heart-rate card. Empty until the card
/// visual exists; do not draw a second treatment here.
struct LiveHeartRateCardSlot: View {
    var body: some View {
        EmptyView()
    }
}
