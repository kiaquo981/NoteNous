import SwiftUI

/// Floating panel that shows during call listening — compact bar or expanded with live transcription.
struct CallListenerPanel: View {
    @Environment(\.moros) private var moros
    @ObservedObject var listener: CallListenerService

    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            compactBar
            if isExpanded {
                Divider().background(moros.border)
                expandedContent
            }
        }
        .background(moros.limit02, in: Rectangle())
        .overlay(
            Rectangle()
                .strokeBorder(Moros.signal.opacity(0.3), lineWidth: 1)
        )
        .animation(.easeInOut(duration: Moros.animBase), value: isExpanded)
    }

    // MARK: - Compact Bar

    private var compactBar: some View {
        HStack(spacing: Moros.spacing8) {
            // Pulsing red recording dot
            recordingDot

            // Duration counter
            Text(formatDuration(listener.duration))
                .font(Moros.fontMono)
                .foregroundStyle(moros.textMain)

            // Audio level bars
            audioLevelBars

            Spacer()

            // Capture mode indicator
            HStack(spacing: 4) {
                Image(systemName: listener.captureMode == .bothSides ? "person.2.fill" : "person.fill")
                    .font(.system(size: 9))
                Text(listener.captureMode == .bothSides ? "Both Sides" : "Mic Only")
            }
            .font(Moros.fontMicro)
            .foregroundStyle(listener.captureMode == .bothSides ? Moros.verdit : moros.textDim)

            // Expand/collapse
            Button {
                isExpanded.toggle()
            } label: {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(Moros.fontSmall)
                    .foregroundStyle(moros.textSub)
            }
            .buttonStyle(.plain)

            // Pause/Resume
            if listener.state == .paused {
                Button {
                    listener.resume()
                } label: {
                    Image(systemName: "play.fill")
                        .font(Moros.fontBody)
                        .foregroundStyle(moros.oracle)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    listener.pause()
                } label: {
                    Image(systemName: "pause.fill")
                        .font(Moros.fontBody)
                        .foregroundStyle(moros.textSub)
                }
                .buttonStyle(.plain)
            }

            // Stop
            Button {
                let _ = listener.stopListening()
            } label: {
                Image(systemName: "stop.fill")
                    .font(Moros.fontBody)
                    .foregroundStyle(Moros.signal)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Moros.spacing12)
        .padding(.vertical, Moros.spacing8)
        .contentShape(Rectangle())
        .onTapGesture {
            isExpanded.toggle()
        }
    }

    // MARK: - Recording Dot

    private var recordingDot: some View {
        Circle()
            .fill(listener.state == .paused ? moros.textDim : Moros.signal)
            .frame(width: 8, height: 8)
            .modifier(PulsingModifier(isPulsing: listener.state == .listening))
    }

    // MARK: - Audio Level Bars (5 bars)

    private var audioLevelBars: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                let threshold = Float(index + 1) / 5.0
                let isActive = listener.audioLevel >= threshold
                RoundedRectangle(cornerRadius: 1)
                    .fill(isActive ? Moros.signal : moros.textGhost)
                    .frame(width: 3, height: barHeight(for: index))
            }
        }
        .frame(height: 14)
        .animation(.easeOut(duration: Moros.animFast), value: listener.audioLevel)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let heights: [CGFloat] = [4, 7, 10, 13, 14]
        return heights[index]
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: Moros.spacing8) {
            // Live transcription area
            ScrollViewReader { proxy in
                ScrollView {
                    Text(listener.liveTranscription.isEmpty
                         ? "Waiting for speech..."
                         : listener.liveTranscription)
                        .font(Moros.fontBody)
                        .foregroundStyle(
                            listener.liveTranscription.isEmpty
                            ? moros.textDim
                            : moros.textMain
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("transcriptionBottom")
                }
                .frame(maxHeight: 200)
                .onChange(of: listener.liveTranscription) { _, _ in
                    withAnimation {
                        proxy.scrollTo("transcriptionBottom", anchor: .bottom)
                    }
                }
            }
            .padding(Moros.spacing8)
            .background(moros.limit01, in: Rectangle())

            // State indicator
            HStack(spacing: Moros.spacing4) {
                if listener.state == .paused {
                    Image(systemName: "pause.circle.fill")
                        .foregroundStyle(moros.textDim)
                    Text("Paused")
                        .font(Moros.fontSmall)
                        .foregroundStyle(moros.textDim)
                } else {
                    Image(systemName: "waveform")
                        .foregroundStyle(Moros.signal)
                    Text("\(Int(listener.liveTranscription.count)) chars transcribed")
                        .font(Moros.fontSmall)
                        .foregroundStyle(moros.textDim)
                }
            }
        }
        .padding(Moros.spacing12)
    }

    // MARK: - Helpers

    private func formatDuration(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Pulsing Animation Modifier

private struct PulsingModifier: ViewModifier {
    let isPulsing: Bool
    @State private var opacity: Double = 1.0

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .onAppear {
                if isPulsing {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        opacity = 0.3
                    }
                }
            }
            .onChange(of: isPulsing) { _, newValue in
                if newValue {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        opacity = 0.3
                    }
                } else {
                    withAnimation { opacity = 1.0 }
                }
            }
    }
}
