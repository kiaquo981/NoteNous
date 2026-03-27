import SwiftUI

/// Detail view for creating or editing a single source.
struct SourceDetailSheet: View {
    @ObservedObject var sourceService: SourceService
    @Environment(\.dismiss) private var dismiss

    let source: Source?

    @State private var title: String = ""
    @State private var author: String = ""
    @State private var sourceType: SourceType = .book
    @State private var url: String = ""
    @State private var isbn: String = ""
    @State private var dateConsumed: Date = Date()
    @State private var hasDateConsumed: Bool = false
    @State private var dateCarded: Date = Date()
    @State private var hasDateCarded: Bool = false
    @State private var rating: Int = 0
    @State private var notes: String = ""

    private var isNew: Bool { source == nil }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isNew ? "Add Source" : "Edit Source")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Title
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Title")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("Book title, article name, etc.", text: $title)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Author
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Author")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("Author name", text: $author)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Type
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Type")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Picker("Type", selection: $sourceType) {
                                ForEach(SourceType.allCases) { type in
                                    Label(type.label, systemImage: type.icon).tag(type)
                                }
                            }
                            .frame(width: 200)
                        }

                        Spacer()

                        // Rating
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Rating")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 4) {
                                ForEach(1...5, id: \.self) { star in
                                    Image(systemName: star <= rating ? "star.fill" : "star")
                                        .foregroundStyle(star <= rating ? .yellow : .gray)
                                        .onTapGesture {
                                            rating = rating == star ? 0 : star
                                        }
                                }
                            }
                            .font(.title3)
                        }
                    }

                    // URL
                    VStack(alignment: .leading, spacing: 4) {
                        Text("URL")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("https://...", text: $url)
                            .textFieldStyle(.roundedBorder)
                    }

                    // ISBN
                    if sourceType == .book {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("ISBN")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            TextField("ISBN (optional)", text: $isbn)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    // Dates
                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Date Consumed", isOn: $hasDateConsumed)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            if hasDateConsumed {
                                DatePicker("", selection: $dateConsumed, displayedComponents: .date)
                                    .labelsHidden()
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Date Carded", isOn: $hasDateCarded)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            if hasDateCarded {
                                DatePicker("", selection: $dateCarded, displayedComponents: .date)
                                    .labelsHidden()
                            }
                        }
                    }

                    // Waiting Period Indicator
                    if hasDateConsumed && !hasDateCarded {
                        waitingPeriodIndicator
                    }

                    // Notes
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Personal Notes")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextEditor(text: $notes)
                            .font(.body)
                            .frame(minHeight: 100)
                            .border(.quaternary, width: 1)
                    }

                    // Linked Notes (read-only, for existing sources)
                    if let existingSource = source, !existingSource.linkedNoteIds.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Linked Notes (\(existingSource.linkedNoteIds.count))")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text("Cards generated from this source")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                if !isNew {
                    Button("Delete", role: .destructive) {
                        if let source = source {
                            sourceService.deleteSource(id: source.id)
                        }
                        dismiss()
                    }
                }

                Spacer()

                if !isNew && !hasDateCarded, hasDateConsumed {
                    Button("Start Carding") {
                        if let source = source {
                            sourceService.startCarding(id: source.id)
                        }
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }

                Button(isNew ? "Add Source" : "Save") {
                    saveSource()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 500, minHeight: 500)
        .onAppear {
            if let source = source {
                title = source.title
                author = source.author ?? ""
                sourceType = source.sourceType
                url = source.url ?? ""
                isbn = source.isbn ?? ""
                if let dc = source.dateConsumed {
                    dateConsumed = dc
                    hasDateConsumed = true
                }
                if let dc = source.dateCarded {
                    dateCarded = dc
                    hasDateCarded = true
                }
                rating = source.rating ?? 0
                notes = source.notes ?? ""
            }
        }
    }

    // MARK: - Waiting Period Indicator

    private var waitingPeriodIndicator: some View {
        let daysSince = Calendar.current.dateComponents([.day], from: dateConsumed, to: Date()).day ?? 0
        let isReady = daysSince >= 14
        let remaining = max(0, 14 - daysSince)

        return HStack(spacing: 12) {
            Image(systemName: isReady ? "checkmark.circle.fill" : "clock.fill")
                .foregroundStyle(isReady ? .green : .orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(isReady ? "Ready to card" : "Waiting period: \(remaining) days remaining")
                    .font(.callout.weight(.medium))
                Text("Holiday recommends waiting 2-4 weeks before making cards from a source.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Progress
            ProgressView(value: Double(min(daysSince, 14)), total: 14)
                .frame(width: 80)
        }
        .padding(10)
        .background(isReady ? Color.green.opacity(0.08) : Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Actions

    private func saveSource() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        if var existing = source {
            existing.title = trimmedTitle
            existing.author = author.isEmpty ? nil : author
            existing.sourceType = sourceType
            existing.url = url.isEmpty ? nil : url
            existing.isbn = isbn.isEmpty ? nil : isbn
            existing.dateConsumed = hasDateConsumed ? dateConsumed : nil
            existing.dateCarded = hasDateCarded ? dateCarded : nil
            existing.rating = rating > 0 ? rating : nil
            existing.notes = notes.isEmpty ? nil : notes
            sourceService.updateSource(existing)
        } else {
            sourceService.addSource(
                title: trimmedTitle,
                author: author.isEmpty ? nil : author,
                sourceType: sourceType,
                url: url.isEmpty ? nil : url,
                isbn: isbn.isEmpty ? nil : isbn,
                dateConsumed: hasDateConsumed ? dateConsumed : nil,
                rating: rating > 0 ? rating : nil,
                notes: notes.isEmpty ? nil : notes
            )
        }

        dismiss()
    }
}
