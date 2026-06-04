import SwiftUI
import AVFoundation

@MainActor
final class TeamChatVoiceRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var level: CGFloat = 0
    @Published private(set) var elapsed: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var outputURL: URL?

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString).m4a")
        outputURL = url
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder?.isMeteringEnabled = true
        recorder?.delegate = self
        recorder?.record()
        isRecording = true
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.recorder else { return }
            recorder.updateMeters()
            let power = recorder.averagePower(forChannel: 0)
            let normalized = max(0, min(1, (power + 50) / 50))
            Task { @MainActor in
                self.level = CGFloat(normalized)
                self.elapsed = recorder.currentTime
            }
        }
    }

    func stop() -> URL? {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        isRecording = false
        level = 0
        let url = outputURL
        recorder = nil
        return url
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        recorder?.deleteRecording()
        recorder = nil
        isRecording = false
        level = 0
        outputURL = nil
    }
}

struct VoiceRecordingBar: View {
    @ObservedObject var recorder: TeamChatVoiceRecorder
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 3) {
                ForEach(0..<7, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.red)
                        .frame(width: 3, height: barHeight(for: index))
                        .animation(.easeInOut(duration: 0.1), value: recorder.level)
                }
            }
            .frame(height: 32)

            Text(formatTime(recorder.elapsed))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.red)

            Spacer()

            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.18))
                    .frame(width: pulse ? 34 : 24, height: pulse ? 34 : 24)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
                Image(systemName: "mic.fill")
                    .foregroundStyle(.red)
                    .font(.body.weight(.bold))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: MessagesTheme.composerCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MessagesTheme.composerCornerRadius, style: .continuous)
                .strokeBorder(Color.red.opacity(0.25), lineWidth: 1)
        )
        .onAppear { pulse = true }
        .onDisappear { pulse = false }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let wave = sin(Double(index) * 0.9 + recorder.level * 4) * 0.5 + 0.5
        let base: CGFloat = 6 + CGFloat(index % 3) * 3
        return base + CGFloat(wave) * 14 + recorder.level * 12
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let s = Int(t) % 60
        let m = Int(t) / 60
        return String(format: "%d:%02d", m, s)
    }
}

@MainActor
final class VoiceMessagePlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    @Published private(set) var progress: CGFloat = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func toggle(url: URL) {
        if isPlaying {
            stop()
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.play()
            isPlaying = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                guard let self, let player = self.player, player.duration > 0 else { return }
                Task { @MainActor in
                    self.progress = CGFloat(player.currentTime / player.duration)
                }
            }
        } catch {
            stop()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        player?.stop()
        player = nil
        isPlaying = false
        progress = 0
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}

struct VoiceMessageBubble: View {
    let attachment: AnnouncementAttachment
    let outgoing: Bool
    @StateObject private var player = VoiceMessagePlayer()
    @State private var localURL: URL?

    private let barHeights: [CGFloat] = [10, 18, 14, 22, 12, 20, 16, 24, 11, 19, 15, 21]

    private var durationLabel: String {
        player.isPlaying ? "announcements.chat.playing".localized : "announcements.chat.voice".localized
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                Task { await playToggle() }
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(outgoing ? .white : .white)
                    .frame(width: 28, height: 28)
            }

            HStack(spacing: 2) {
                ForEach(0..<barHeights.count, id: \.self) { index in
                    let played = index < Int(player.progress * CGFloat(barHeights.count)) + 1
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(outgoing ? Color.white.opacity(played ? 0.95 : 0.45) : Color.white.opacity(played ? 0.95 : 0.4))
                        .frame(width: 2.5, height: barHeights[index] * (played ? 1 : 0.55))
                        .animation(.easeOut(duration: 0.08), value: player.progress)
                }
            }
            .frame(height: 26)

            Text(durationLabel)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(outgoing ? Color.white.opacity(0.85) : Color.white.opacity(0.85))
        }
        .padding(.horizontal, MessagesTheme.bubblePaddingH)
        .padding(.vertical, MessagesTheme.bubblePaddingV)
        .background(outgoing ? MessagesTheme.outgoingBubble : MessagesTheme.incomingBubble)
        .foregroundStyle(outgoing ? .white : .white)
        .task { await resolveURL() }
    }

    private func resolveURL() async {
        localURL = await AttachmentPreviewLoader.localURL(for: attachment)
    }

    private func playToggle() async {
        if localURL == nil {
            localURL = await AttachmentPreviewLoader.localURL(for: attachment)
        }
        guard let url = localURL else { return }
        player.toggle(url: url)
    }
}
