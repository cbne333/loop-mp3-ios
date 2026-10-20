import AVFoundation
import Combine
import MediaPlayer
import SwiftUI

struct Track: Codable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let filename: String
    let duration: TimeInterval
}

private struct ImportResult: Sendable {
    var tracks: [Track] = []
    var failures: [String] = []
}

@MainActor
final class PlayerStore: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var currentID: UUID?
    @Published private(set) var isPlaying = false
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isImporting = false
    @Published var errorMessage: String?
    @Published var repeatMode: RepeatMode {
        didSet {
            UserDefaults.standard.set(repeatMode.rawValue, forKey: "repeatMode")
            audioPlayer?.numberOfLoops = repeatMode == .one ? -1 : 0
        }
    }

    private var audioPlayer: AVAudioPlayer?
    private var ticker: AnyCancellable?
    private var resumeAfterInterruption = false
    private let directory: URL
    private var libraryURL: URL { directory.appendingPathComponent("library.json") }
    var currentTrack: Track? { tracks.first { $0.id == currentID } }
    private var currentIndex: Int? { tracks.firstIndex { $0.id == currentID } }

    override init() {
        directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Audio", isDirectory: true)
        repeatMode = RepeatMode(rawValue: UserDefaults.standard.string(forKey: "repeatMode") ?? "") ?? .one
        super.init()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: libraryURL.path) {
                tracks = try JSONDecoder().decode([Track].self, from: Data(contentsOf: libraryURL))
            }
        } catch {
            errorMessage = "저장된 목록을 읽지 못했습니다: \(error.localizedDescription)"
        }
        ticker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                guard let self, let player = self.audioPlayer, self.isPlaying else { return }
                self.position = player.currentTime
            }
        NotificationCenter.default.addObserver(
            self, selector: #selector(interruption(_:)),
            name: AVAudioSession.interruptionNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(routeChanged(_:)),
            name: AVAudioSession.routeChangeNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(mediaReset(_:)),
            name: AVAudioSession.mediaServicesWereResetNotification, object: nil
        )
        configureRemoteCommands()
    }

    func importFiles(_ urls: [URL]) {
        guard !isImporting else { return }
        isImporting = true
        let destination = directory
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Self.copyFiles(urls, to: destination)
            }.value
            let updated = tracks + result.tracks
            if persist(updated) {
                tracks = updated
            } else {
                // Roll back new copies if the playlist could not be saved.
                for track in result.tracks {
                    try? FileManager.default.removeItem(at: destination.appendingPathComponent(track.filename))
                }
            }
            isImporting = false
            if !result.failures.isEmpty {
                let failures = "가져오지 못한 파일:\n" + result.failures.joined(separator: "\n")
                errorMessage = [errorMessage, failures].compactMap { $0 }.joined(separator: "\n\n")
            }
        }
    }

    nonisolated private static func copyFiles(_ urls: [URL], to directory: URL) -> ImportResult {
        var result = ImportResult()
        for source in urls {
            let access = source.startAccessingSecurityScopedResource()
            defer { if access { source.stopAccessingSecurityScopedResource() } }
            let id = UUID()
            let filename = "\(id.uuidString).mp3"
            let target = directory.appendingPathComponent(filename)
            do {
                guard source.pathExtension.lowercased() == "mp3" else {
                    throw NSError(domain: "LoopMP3", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "MP3 파일만 추가할 수 있습니다."])
                }
                // Coordinate provider-backed reads, including files selected from iCloud Drive.
                var coordinationError: NSError?
                var copyError: Error?
                NSFileCoordinator().coordinate(readingItemAt: source, options: [],
                                               error: &coordinationError) { readable in
                    do { try FileManager.default.copyItem(at: readable, to: target) }
                    catch { copyError = error }
                }
                if let error = coordinationError { throw error }
                if let error = copyError { throw error }
                let probe = try AVAudioPlayer(contentsOf: target)
                guard probe.duration > 0 else {
                    throw NSError(domain: "LoopMP3", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "재생 가능한 오디오가 없습니다."])
                }
                result.tracks.append(Track(id: id,
                                           title: source.deletingPathExtension().lastPathComponent,
                                           filename: filename, duration: probe.duration))
            } catch {
                try? FileManager.default.removeItem(at: target)
                result.failures.append("\(source.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return result
    }

    @discardableResult
    private func persist(_ items: [Track]) -> Bool {
        do {
            try JSONEncoder().encode(items).write(to: libraryURL, options: .atomic)
            return true
        } catch {
            errorMessage = "목록을 저장하지 못했습니다: \(error.localizedDescription)"
            return false
        }
    }

    func select(_ track: Track) {
        guard tracks.contains(where: { $0.id == track.id }) else { return }
        resumeAfterInterruption = false
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        currentID = track.id
        position = 0
        duration = track.duration
        do {
            let player = try AVAudioPlayer(contentsOf: directory.appendingPathComponent(track.filename))
            player.delegate = self
            player.numberOfLoops = repeatMode == .one ? -1 : 0
            audioPlayer = player
            duration = player.duration
            play()
        } catch {
            updateNowPlaying()
            errorMessage = "파일을 재생할 수 없습니다: \(error.localizedDescription)"
        }
    }

    func play() {
        if audioPlayer == nil {
            if let track = currentTrack ?? tracks.first { select(track) }
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            if let player = audioPlayer, player.currentTime >= player.duration {
                player.currentTime = 0
            }
            guard audioPlayer?.play() == true else {
                throw NSError(domain: "LoopMP3", code: 3,
                              userInfo: [NSLocalizedDescriptionKey: "오디오 재생을 시작하지 못했습니다."])
            }
            isPlaying = true
            position = audioPlayer?.currentTime ?? 0
            updateNowPlaying()
        } catch {
            isPlaying = false
            updateNowPlaying()
            errorMessage = "재생을 시작하지 못했습니다: \(error.localizedDescription)"
        }
    }

    func pause() {
        resumeAfterInterruption = false
        audioPlayer?.pause()
        position = audioPlayer?.currentTime ?? position
        isPlaying = false
        updateNowPlaying()
    }

    func togglePlayback() {
        if isPlaying { pause() } else { play() }
    }

    func seek(to time: TimeInterval) {
        guard let audioPlayer, time.isFinite else { return }
        position = min(max(0, time), duration)
        audioPlayer.currentTime = position
        updateNowPlaying()
    }

    func next() {
        guard let index = currentIndex else {
            if let first = tracks.first { select(first) }
            return
        }
        if let next = repeatMode.nextIndex(after: index, count: tracks.count, automatic: false) {
            select(tracks[next])
        }
    }

    func previous() {
        guard let index = currentIndex else { return }
        if position > 3 { seek(to: 0); return }
        if index > 0 { select(tracks[index - 1]) }
        else if repeatMode == .all, let last = tracks.last { select(last) }
        else { seek(to: 0) }
    }

    func move(from offsets: IndexSet, to destination: Int) {
        var updated = tracks
        updated.move(fromOffsets: offsets, toOffset: destination)
        if persist(updated) { tracks = updated }
    }

    func remove(at offsets: IndexSet) {
        let removed = offsets.map { tracks[$0] }
        var updated = tracks
        updated.remove(atOffsets: offsets)
        guard persist(updated) else { return }
        if removed.contains(where: { $0.id == currentID }) {
            pause()
            audioPlayer?.stop()
            audioPlayer = nil
            currentID = nil
            position = 0
            duration = 0
        }
        tracks = updated
        updateNowPlaying()
        for track in removed {
            do { try FileManager.default.removeItem(at: directory.appendingPathComponent(track.filename)) }
            catch { errorMessage = "목록에서 삭제했지만 앱 내부 파일을 지우지 못했습니다: \(error.localizedDescription)" }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.audioPlayer === player else { return }
            self.isPlaying = false
            self.position = self.duration
            if flag, let index = self.currentIndex,
               let next = self.repeatMode.nextIndex(after: index, count: self.tracks.count, automatic: true) {
                self.select(self.tracks[next])
            } else {
                self.updateNowPlaying()
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                if !flag { self.errorMessage = "오디오 재생이 정상적으로 끝나지 않았습니다." }
            }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self, self.audioPlayer === player else { return }
            self.pause()
            self.errorMessage = "오디오를 읽는 중 오류가 발생했습니다."
        }
    }

    @objc private func interruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if type == .began {
            let wasPlaying = isPlaying
            pause()
            resumeAfterInterruption = wasPlaying
        } else {
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let shouldResume = resumeAfterInterruption &&
                AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)
            resumeAfterInterruption = false
            if shouldResume { play() }
        }
    }

    @objc private func routeChanged(_ notification: Notification) {
        let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
        if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { pause() }
    }

    @objc private func mediaReset(_ notification: Notification) {
        pause()
        audioPlayer = nil
        position = 0
        updateNowPlaying()
    }

    private func updateNowPlaying() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: "Loop MP3",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
    }

    private func configureRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.play() }
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayback() }
            return .success
        }
        commands.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        commands.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor in self?.seek(to: position) }
            return .success
        }
    }
}
