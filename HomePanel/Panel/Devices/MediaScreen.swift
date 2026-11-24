import HAKit
import SwiftUI

/// Media players: artwork, now playing, transport, volume and source when supported.
struct MediaScreen: View {
    @Environment(AppModel.self) private var app
    let card: Card

    var body: some View {
        let player = app.store[card.entityID]
        let f = player?.mediaFeatures ?? []
        let name = app.displayName(card)
        let id = card.entityID
        let isOff = player?.state == "off"
        let available = player?.isAvailable == true
        let active = available && !isOff

        VStack(alignment: .leading, spacing: 16) {
            BackHeader(name) {
                if available, !f.isDisjoint(with: [.turnOn, .turnOff]) {
                    PowerButton(isOn: !isOff, label: name) {
                        app.call("media_player", isOff ? "turn_on" : "turn_off", [id])
                    }
                }
            }

            HStack(alignment: .center, spacing: 12) {
                Artwork(path: player?.entityPicture, fallback: DeviceIcon.symbol(card, player))
                VStack(alignment: .leading, spacing: 3) {
                    Text(player?.mediaTitle ?? (player.map(DeviceText.summary) ?? "Unavailable"))
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(2)
                    if let artist = [player?.mediaArtist, player?.mediaAlbum].compactMap({ $0 }).first {
                        Text(artist).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if let appName = player?.mediaAppName ?? player?.mediaSource {
                        Text(appName).font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }

            if let player, player.mediaDuration != nil, ["playing", "paused"].contains(player.state) {
                ProgressLine(player: player)
            }

            if active {
                transport(player, f)
            }

            if f.contains(.volumeSet), let player, active {
                HStack(spacing: 8) {
                    if f.contains(.volumeMute) {
                        RoundIconButton(
                            systemImage: player.isVolumeMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                            label: player.isVolumeMuted ? "Unmute" : "Mute"
                        ) {
                            app.call("media_player", "volume_mute", [id], ["is_volume_muted": .bool(!player.isVolumeMuted)])
                        }
                    }
                    LiveSlider(
                        value: player.volumeLevel ?? 0,
                        systemImage: "speaker.wave.1.fill",
                        accessibilityName: "Volume",
                        label: { "\(Int(($0 * 100).rounded()))%" }
                    ) { [app] v in
                        app.call("media_player", "volume_set", [id], ["volume_level": .number((v * 100).rounded() / 100)])
                    }
                }
            } else if f.contains(.volumeStep), active {
                HStack(spacing: 8) {
                    CapsuleButton(title: "Volume down", systemImage: "speaker.wave.1") {
                        app.call("media_player", "volume_down", [id])
                    }
                    CapsuleButton(title: "Volume up", systemImage: "speaker.wave.3") {
                        app.call("media_player", "volume_up", [id])
                    }
                }
            }

            if f.contains(.selectSource), let player, !player.sourceList.isEmpty, active {
                PanelSection("Source") {
                    PillFlow(
                        options: player.sourceList.map { PillOption(value: $0, label: $0) },
                        selected: player.mediaSource
                    ) { app.call("media_player", "select_source", [id], ["source": .string($0)]) }
                }
            }
        }
    }

    @ViewBuilder
    private func transport(_ player: HAState?, _ f: MediaFeatures) -> some View {
        let id = card.entityID
        let playing = player?.state == "playing"
        HStack(spacing: 22) {
            if f.contains(.previousTrack) {
                RoundIconButton(systemImage: "backward.fill", label: "Previous") {
                    app.call("media_player", "media_previous_track", [id])
                }
            }
            if !f.isDisjoint(with: [.pause, .play]) {
                Button {
                    app.call("media_player", "media_play_pause", [id])
                } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.onText)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(Theme.onFill))
                        .contentTransition(.symbolEffect(.replace))
                        .contentShape(Circle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(playing ? "Pause" : "Play")
            } else if f.contains(.stop) {
                RoundIconButton(systemImage: "stop.fill", label: "Stop") { app.call("media_player", "media_stop", [id]) }
            }
            if f.contains(.nextTrack) {
                RoundIconButton(systemImage: "forward.fill", label: "Next") {
                    app.call("media_player", "media_next_track", [id])
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Album art from HA (its media proxy URL is already signed), or an icon.
private struct Artwork: View {
    let path: String?
    let fallback: String

    var body: some View {
        let url: URL? = path.flatMap { p in
            p.hasPrefix("http") ? URL(string: p) : SharedConfig.baseURL.flatMap { URL(string: p, relativeTo: $0) }
        }
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Image(systemName: fallback)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.primary.opacity(0.08))
            }
        }
        .frame(width: 84, height: 84)
        .clipShape(.rect(cornerRadius: 14, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Playback position, advancing locally while playing.
private struct ProgressLine: View {
    let player: HAState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let duration = max(1, player.mediaDuration ?? 1)
            let position = player.mediaPosition(at: context.date) ?? 0
            VStack(spacing: 3) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.12))
                        Capsule().fill(Color.primary.opacity(0.7)).frame(width: geo.size.width * position / duration)
                    }
                }
                .frame(height: 4)
                HStack {
                    Text(Self.time(position))
                    Spacer()
                    Text("-" + Self.time(duration - position))
                }
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(Self.time(player.mediaPosition(at: .now) ?? 0)) of \(Self.time(player.mediaDuration ?? 0))")
    }

    static func time(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}
