import SwiftUI

struct DeskNoteCard: View {
    @ObservedObject var note: NoteEntity
    let displayMode: DeskCanvasState.CardDisplayMode
    let isSelected: Bool
    let zoomLevel: CGFloat
    let onTap: (Bool) -> Void
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: (DragGesture.Value) -> Void

    @State private var isHovered: Bool = false

    // MARK: - Card sizing

    private var cardSize: CGSize {
        switch displayMode {
        case .compact: CGSize(width: 200, height: 60)
        case .normal: CGSize(width: 200, height: 140)
        case .expanded: CGSize(width: 260, height: 220)
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            colorStripe
            cardContent
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isSelected ? Color.accentColor : Color.clear,
                    lineWidth: isSelected ? 2 : 0
                )
        )
        .shadow(
            color: .black.opacity(isHovered ? 0.18 : 0.08),
            radius: isHovered ? 8 : 3,
            y: isHovered ? 4 : 1
        )
        .scaleEffect(isSelected ? 1.03 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
        .onTapGesture {
            let shiftHeld = NSEvent.modifierFlags.contains(.shift)
            onTap(shiftHeld)
        }
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged(onDragChanged)
                .onEnded(onDragEnded)
        )
    }

    // MARK: - Subviews

    private var colorStripe: some View {
        Rectangle()
            .fill(stripeColor)
            .frame(height: 8)
    }

    @ViewBuilder
    private var cardContent: some View {
        switch displayMode {
        case .compact:
            compactContent
        case .normal:
            normalContent
        case .expanded:
            expandedContent
        }
    }

    private var compactContent: some View {
        HStack(spacing: 6) {
            if note.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
            }
            Text(note.title.isEmpty ? "Untitled" : note.title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Spacer()
            noteTypeIcon
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var normalContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                }
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
            }

            Text(previewText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Spacer(minLength: 0)

            cardFooter
        }
        .padding(10)
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                }
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
            }

            Text(previewText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(6)

            if !note.tagsArray.isEmpty {
                tagsRow
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                cardFooter
                Spacer()
                linkCountBadge
            }
        }
        .padding(10)
    }

    private var cardFooter: some View {
        HStack(spacing: 6) {
            if let zettelId = note.zettelId {
                Text(zettelId)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            noteTypeIcon
            paraBadge
        }
    }

    private var noteTypeIcon: some View {
        Image(systemName: note.noteType.icon)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .help(note.noteType.label)
    }

    private var paraBadge: some View {
        Text(note.paraCategory.label)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(paraColor.opacity(0.15), in: Capsule())
            .foregroundStyle(paraColor)
    }

    private var tagsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(note.tagsArray.prefix(5), id: \.self) { tag in
                    Text("#\(tag.name ?? "")")
                        .font(.system(size: 9))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.1), in: Capsule())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var linkCountBadge: some View {
        let count = note.totalLinkCount
        return Group {
            if count > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "link")
                        .font(.system(size: 9))
                    Text("\(count)")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Computed properties

    private var previewText: String {
        let plain = note.contentPlainText
        return plain.isEmpty ? "No content" : String(plain.prefix(200))
    }

    private var stripeColor: Color {
        if let hex = note.colorHex {
            return Color(hex: hex)
        }
        return paraColor.opacity(0.6)
    }

    private var paraColor: Color {
        switch note.paraCategory {
        case .inbox: .gray
        case .project: .blue
        case .area: .green
        case .resource: .orange
        case .archive: .secondary
        }
    }
}

// Color(hex:) is defined in Utilities/ColorExtensions.swift
