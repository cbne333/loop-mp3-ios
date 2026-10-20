import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var player: PlayerStore
    @State private var showImporter = false
    @State private var scrubPosition: Double = 0
    @State private var isScrubbing = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 20) {
                        Image(systemName: player.isPlaying ? "waveform.circle.fill" : "music.note")
                            .font(.system(size: 64))
                            .foregroundStyle(.indigo)
                            .frame(height: 90)
                            .accessibilityHidden(true)
                        VStack(spacing: 6) {
                            Text(player.currentTrack?.title ?? "반복하고 싶은 음악")
                                .font(.title2.bold())
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                            Text(player.currentTrack == nil ? "MP3 파일을 추가하고 곡을 선택하세요" : player.repeatMode.title)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        VStack(spacing: 4) {
                            Slider(
                                value: Binding(
                                    get: { isScrubbing ? scrubPosition : player.position },
                                    set: { scrubPosition = $0 }
                                ),
                                in: 0...max(player.duration, 1),
                                onEditingChanged: { editing in
                                    if editing {
                                        scrubPosition = player.position
                                        isScrubbing = true
                                    } else {
                                        player.seek(to: scrubPosition)
                                        isScrubbing = false
                                    }
                                }
                            )
                            .disabled(player.currentTrack == nil)
                            .accessibilityLabel("재생 위치")
                            .accessibilityValue(time(isScrubbing ? scrubPosition : player.position))
                            HStack {
                                Text(time(isScrubbing ? scrubPosition : player.position))
                                Spacer()
                                Text(time(player.duration))
                            }
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 36) {
                            Button(action: player.previous) {
                                Image(systemName: "backward.end.fill").font(.title2)
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("이전 곡 또는 처음부터")
                            Button(action: player.togglePlayback) {
                                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 66))
                                    .frame(width: 72, height: 72)
                            }
                            .accessibilityLabel(player.isPlaying ? "일시 정지" : "재생")
                            Button(action: player.next) {
                                Image(systemName: "forward.end.fill").font(.title2)
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("다음 곡")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.indigo)
                        .disabled(player.tracks.isEmpty)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                Section {
                    Picker("반복 방식", selection: $player.repeatMode) {
                        ForEach(RepeatMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("반복 재생")
                } footer: {
                    Text(repeatExplanation)
                }
                Section {
                    if player.tracks.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("아직 추가한 MP3가 없어요").font(.headline)
                            Text("오른쪽 위 + 버튼으로 파일 앱 또는 iCloud Drive에서 여러 곡을 가져오세요.")
                                .foregroundStyle(.secondary)
                            Button("MP3 가져오기") { showImporter = true }
                                .padding(.top, 4)
                        }
                        .padding(.vertical, 8)
                    }
                    ForEach(player.tracks) { track in
                        Button { player.select(track) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: track.id == player.currentID ? "speaker.wave.2.fill" : "music.note")
                                    .foregroundStyle(track.id == player.currentID ? Color.indigo : Color.secondary)
                                    .frame(width: 24)
                                Text(track.title)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                Spacer(minLength: 8)
                                Text(time(track.duration))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(track.title), \(time(track.duration))")
                        .accessibilityAddTraits(track.id == player.currentID ? .isSelected : [])
                    }
                    .onMove(perform: player.move)
                    .onDelete(perform: player.remove)
                } header: {
                    Text("재생 목록 · \(player.tracks.count)곡")
                } footer: {
                    if !player.tracks.isEmpty {
                        Text("편집에서 순서를 바꿀 수 있습니다. 삭제하면 앱에 복사된 파일만 지워집니다.")
                    }
                }
                if player.isImporting {
                    HStack {
                        ProgressView()
                        Text("MP3 파일을 가져오는 중…").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Loop MP3")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton().disabled(player.tracks.isEmpty)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showImporter = true } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(player.isImporting)
                    .accessibilityLabel("MP3 파일 추가")
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.mp3],
                          allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): player.importFiles(urls)
                case .failure(let error): player.errorMessage = "파일을 가져오지 못했습니다: \(error.localizedDescription)"
                }
            }
            .alert("확인이 필요해요", isPresented: Binding(
                get: { player.errorMessage != nil },
                set: { if !$0 { player.errorMessage = nil } }
            )) {
                Button("확인", role: .cancel) { player.errorMessage = nil }
            } message: {
                Text(player.errorMessage ?? "")
            }
            .onChange(of: player.currentID) { _ in isScrubbing = false }
        }
    }

    private var repeatExplanation: String {
        switch player.repeatMode {
        case .off: return "목록 순서대로 재생하고 마지막 곡이 끝나면 멈춥니다."
        case .one: return "현재 곡을 계속 반복합니다. 다음 곡 버튼으로 곡을 바꿀 수 있습니다."
        case .all: return "목록을 순서대로 재생하고 마지막 곡 다음에 첫 곡으로 돌아갑니다."
        }
    }

    private func time(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.isFinite ? seconds : 0))
        if value >= 3600 { return String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) }
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
