import SwiftUI
import AVKit
import ImageIO

/// One entry in shared Exercise Details, used from Coach plans, saved workouts and the library.
struct ExerciseDemoGenerationSection: View {
    let exercise: Exercise
    @State private var presented = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if CoreExerciseDemos.assets[exercise.id] == nil && ExerciseDemoService.shared.files[exercise.id] == nil {
                Button { presented = true } label: { Label("demo.title", systemImage: "sparkles.tv") }
                    .buttonStyle(.bordered).controlSize(.small).tint(MasoColor.text)
            }
        }
        .sheet(isPresented: $presented) { ExerciseDemoGenerationSheet(exercise: exercise) }
    }
}
struct ExerciseDemoGenerationSheet: View {
    let exercise: Exercise
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var result: ExerciseDemoResult?
    @State private var working = false
    @State private var confirms = false
    @State private var errorText: String?
    @State private var pollingID = 0
    @Environment(\.locale) private var locale
    var service = ExerciseDemoService.shared
    var body: some View {
        AppNavigationStack {
            Form {
                Section { Text(exercise.displayName).font(.headline) }
                if let wallet = result?.wallet {
                    Section("demo.credits") {
                        LabeledContent("demo.available", value: wallet.available.formatted(.number.locale(locale)))
                        if wallet.held > 0 { LabeledContent("demo.reserved", value: wallet.held.formatted(.number.locale(locale))) }
                    }
                }
                Section {
                    if working { ProgressView() }
                    if let result {
                        Text(LocalizedStringKey(statusKey(result.status)))
                        if result.status == "missing", result.enabled == true, let cost = result.cost {
                            Text(String(format: NSLocalizedString("demo.cost", comment: ""), locale: locale, cost)).foregroundStyle(.secondary)
                            Button("demo.generate") { confirms = true }
                                .buttonStyle(.borderedProminent).tint(MasoColor.accent)
                                .disabled(working || (result.wallet?.available ?? 0) < cost)
                            if (result.wallet?.available ?? 0) < cost { Text("demo.insufficient").foregroundStyle(.secondary) }
                        } else if result.status == "missing", result.enabled != true {
                            Text("demo.unavailable").foregroundStyle(.secondary)
                        }
                        if result.status == "failed" {
                            Button("demo.check") { Task { await refresh() } }.buttonStyle(.bordered).tint(MasoColor.text)
                        }
                    }
                    if let errorText { Text(errorText).foregroundStyle(.secondary) }
                    Button("demo.refresh") { Task { await refresh() } }.tint(MasoColor.text).disabled(working)
                }
                Section { Text("demo.sharing").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle(Text("demo.title")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.tint(MasoColor.text) } }
            .alert("demo.confirm", isPresented: $confirms) {
                Button("Cancel", role: .cancel) { }
                Button("demo.generate") { Task { await generate() } }
            } message: {
                Text(String(format: NSLocalizedString("demo.confirmBody", comment: ""), locale: locale, result?.cost ?? 0))
            }
            .task(id: "\(scenePhase)-\(pollingID)") {
                guard scenePhase == .active else { return }
                await refresh()
                while !Task.isCancelled, ["queued", "running", "review"].contains(result?.status ?? "") {
                    do { try await Task.sleep(for: .seconds(10)); try Task.checkCancellation() } catch { return }
                    await refresh()
                }
            }
        }.presentationDetents([.large])
    }
    private func statusKey(_ status: String?) -> String {
        switch status {
        case "ready": return "demo.ready"
        case "queued": return "demo.queued"
        case "running": return "demo.running"
        case "review": return "demo.review"
        case "failed": return "demo.failed"
        case "core_pending": return "demo.corePending"
        default: return "demo.missing"
        }
    }
    private func refresh() async {
        guard !working else { return }; working = true; defer { working = false }
        do {
            if let job = result?.jobId, result?.status != "ready", result?.status != "failed" { result = try await service.status(job) }
            else { result = try await service.quote(exercise.id) }
            errorText = nil
            if result?.status == "ready" { await service.loadMedia(exercise.id, force: true) }
        } catch { if !Task.isCancelled { errorText = ExerciseDemoService.message(for: error) } }
    }
    private func generate() async {
        guard let quote = result, !working else { return }
        working = true; defer { working = false }
        do { result = try await service.generate(exercise.id, quote: quote); errorText = nil; pollingID += 1 }
        catch { errorText = ExerciseDemoService.message(for: error) }
    }
}

/// Displays original GIF bytes in the shared detail, training and list media.
/// Each frame retains its source delay and playback can be paused by the scene.
struct GeneratedExerciseGIF: UIViewRepresentable {
    let url: URL
    var playbackEnabled = true
    var maxPixelSize = 720
    var contentMode: ContentMode = .fill

    func makeUIView(context: Context) -> GIFView {
        let view = GIFView()
        view.load(url, maxPixelSize: maxPixelSize)
        view.setPlaybackEnabled(playbackEnabled)
        view.layer.contentsGravity = contentMode == .fit ? .resizeAspect : .resizeAspectFill
        return view
    }
    func updateUIView(_ view: GIFView, context: Context) {
        if view.url != url { view.load(url, maxPixelSize: maxPixelSize) }
        view.setPlaybackEnabled(playbackEnabled)
        view.layer.contentsGravity = contentMode == .fit ? .resizeAspect : .resizeAspectFill
    }
    static func dismantleUIView(_ view: GIFView, coordinator: ()) { view.stop() }

    final class GIFView: UIView {
        private(set) var url: URL?
        private var decode: Task<Void, Never>?
        private var frames: [CGImage] = []
        private var delays: [TimeInterval] = []
        private var enabled = true

        override init(frame: CGRect) {
            super.init(frame: frame)
            layer.contentsGravity = .resizeAspectFill
            clipsToBounds = true
            isUserInteractionEnabled = false
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func load(_ url: URL, maxPixelSize: Int) {
            stop()
            self.url = url
            decode = Task { [weak self] in
                let result = await Task.detached(priority: .utility) { Self.decodeGIF(url, maxPixelSize: maxPixelSize) }.value
                guard !Task.isCancelled, let self, self.url == url else { return }
                self.frames = result.0
                self.delays = result.1
                self.showFrames()
            }
        }
        func setPlaybackEnabled(_ enabled: Bool) {
            guard self.enabled != enabled else { return }
            self.enabled = enabled
            showFrames()
        }
        func stop() {
            decode?.cancel(); decode = nil
            layer.removeAnimation(forKey: "exerciseGIF")
            layer.contents = nil
            frames = []; delays = []; url = nil
        }
        private func showFrames() {
            layer.removeAnimation(forKey: "exerciseGIF")
            guard let first = frames.first else { return }
            layer.contents = first
            guard enabled, frames.count > 1 else { return }
            let total = delays.reduce(0, +)
            guard total > 0 else { return }
            var elapsed: TimeInterval = 0
            let times = delays.map { delay in
                defer { elapsed += delay }
                return NSNumber(value: elapsed / total)
            }
            let animation = CAKeyframeAnimation(keyPath: "contents")
            animation.values = frames
            animation.keyTimes = times
            animation.calculationMode = .discrete
            animation.duration = total
            animation.repeatCount = .infinity
            layer.add(animation, forKey: "exerciseGIF")
        }
        nonisolated private static func decodeGIF(_ url: URL, maxPixelSize: Int) -> ([CGImage], [TimeInterval]) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return ([], []) }
            var images: [CGImage] = [], durations: [TimeInterval] = []
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                             kCGImageSourceThumbnailMaxPixelSize: maxPixelSize]
            for index in 0..<CGImageSourceGetCount(source) {
                guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else { return ([], []) }
                let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
                let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
                let raw = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue
                    ?? (gif?[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue ?? 0.1
                images.append(image)
                durations.append(raw > 0 ? max(raw, 0.02) : 0.1)
            }
            return (images, durations)
        }
    }
}

/// Same approved, downloaded asset is used by exercise details and active training.
struct GeneratedExerciseVideo: View {
    typealias PlayerView = GeneratedExercisePlayer.PlayerView
    let url: URL
    var playbackEnabled = true
    var contentMode: ContentMode = .fill
    @State private var pair: [UIImage] = []
    @State private var interval: TimeInterval = 0.9
    @State private var frame = 0

    var body: some View {
        Group {
            if pair.count == 2 {
                ExerciseAspectFillPhoto(image: pair[playbackEnabled ? frame : 0], contentMode: contentMode)
                    .onReceive(Timer.publish(every: interval, on: .main, in: .common).autoconnect()) { _ in
                        if playbackEnabled { frame = 1 - frame }
                    }
            } else {
                GeneratedExercisePlayer(url: url, playbackEnabled: playbackEnabled, contentMode: contentMode)
            }
        }
        .task(id: url) {
            pair = []; frame = 0
            let asset = AVURLAsset(url: url)
            do {
                guard let track = try await asset.loadTracks(withMediaType: .video).first,
                      try await track.load(.nominalFrameRate) <= 2 else { return }
                let reader = try AVAssetReader(asset: asset)
                let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
                guard reader.canAdd(output) else { return }
                reader.add(output)
                guard reader.startReading() else { return }
                var times: [CMTime] = []
                while let sample = output.copyNextSampleBuffer(), times.count < 3 {
                    // AVAssetReader can emit empty boundary buffers alongside the
                    // actual compressed pictures; they are not video frames.
                    guard CMSampleBufferGetNumSamples(sample) > 0,
                          CMSampleBufferGetTotalSampleSize(sample) > 0 else { continue }
                    let timestamp = CMSampleBufferGetPresentationTimeStamp(sample)
                    guard timestamp.isNumeric else { continue }
                    times.append(timestamp)
                }
                guard times.count == 2, !Task.isCancelled else { return }
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.requestedTimeToleranceBefore = .zero
                generator.requestedTimeToleranceAfter = .zero
                let first = try await generator.image(at: times[0]).image
                let second = try await generator.image(at: times[1]).image
                guard !Task.isCancelled else { return }
                interval = max(0.1, CMTimeGetSeconds(times[1] - times[0]))
                pair = [UIImage(cgImage: first), UIImage(cgImage: second)]
                #if DEBUG
                print("[ExerciseMedia] Two-frame renderer ready: \(url.lastPathComponent)")
                #endif
            } catch {
                // The regular video player remains the fallback for unreadable clips.
                #if DEBUG
                print("[ExerciseMedia] Two-frame decoding failed: \(error)")
                #endif
            }
        }
    }
}

struct GeneratedExercisePlayer: UIViewRepresentable {
    let url: URL
    var playbackEnabled = true
    var contentMode: ContentMode = .fill
    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView(); view.play(url)
        if !playbackEnabled { view.player?.pause() }
        (view.layer as? AVPlayerLayer)?.videoGravity = contentMode == .fit ? .resizeAspect : .resizeAspectFill
        return view
    }
    func updateUIView(_ view: PlayerView, context: Context) {
        if view.url != url { view.play(url) }
        if playbackEnabled { view.player?.play() } else { view.player?.pause() }
        (view.layer as? AVPlayerLayer)?.videoGravity = contentMode == .fit ? .resizeAspect : .resizeAspectFill
    }
    static func dismantleUIView(_ view: PlayerView, coordinator: ()) { view.player?.pause(); view.looper = nil }
    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var player: AVQueuePlayer?
        var looper: AVPlayerLooper?
        var url: URL?
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override init(frame: CGRect) { super.init(frame: frame); backgroundColor = .clear }
        func play(_ url: URL) {
            player?.pause(); looper = nil; player = nil; self.url = nil
            (layer as? AVPlayerLayer)?.player = nil
            guard AppAudioSession.configure() else { return }
            self.url = url
            let player = AVQueuePlayer()
            player.isMuted = true
            player.volume = 0
            player.allowsExternalPlayback = false
            self.player = player
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            (layer as? AVPlayerLayer)?.player = player; (layer as? AVPlayerLayer)?.videoGravity = .resizeAspectFill
            player.play()
        }
    }
}
