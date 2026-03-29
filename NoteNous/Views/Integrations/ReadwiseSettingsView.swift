import SwiftUI

/// Settings panel for Readwise API integration.
struct ReadwiseSettingsView: View {
    @ObservedObject var readwiseService: ReadwiseService

    @State private var apiKeyInput: String = ""
    @State private var isTestingConnection: Bool = false
    @State private var connectionTestResult: ConnectionTestResult?
    @State private var syncError: String?
    @State private var books: [ReadwiseService.ReadwiseBook] = []
    @State private var selectedBookId: Int?
    @State private var isFetchingBooks: Bool = false

    enum ConnectionTestResult {
        case success
        case failure(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Moros.spacing16) {
                sectionHeader("Readwise Integration")

                apiKeySection
                connectionStatusSection
                syncSection
                statsSection
                importBookSection
            }
            .padding(Moros.spacing20)
        }

        .onAppear {
            apiKeyInput = readwiseService.apiKey ?? ""
        }
    }

    // MARK: - Sections

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: Moros.spacing8) {
            Text("API Key")
                .font(Moros.fontSmall)
                .foregroundStyle(Moros.textSub)

            HStack(spacing: Moros.spacing8) {
                SecureField("Enter your Readwise API key", text: $apiKeyInput)
                    .textFieldStyle(.plain)
                    .font(Moros.fontBody)
                    .foregroundStyle(Moros.textMain)
                    .padding(Moros.spacing8)
                    .background(Moros.limit02)
                    .overlay(
                        Rectangle()
                            .stroke(Moros.border, lineWidth: 1)
                    )

                Button("Save") {
                    readwiseService.apiKey = apiKeyInput.isEmpty ? nil : apiKeyInput
                    connectionTestResult = nil
                }
                .buttonStyle(MorosButtonStyle())
            }

            Text("Get your API key from readwise.io/access_token")
                .font(Moros.fontCaption)
                .foregroundStyle(Moros.textDim)
        }
        .padding(Moros.spacing12)
        .background(Moros.limit02)
        .overlay(Rectangle().stroke(Moros.border, lineWidth: 1))
    }

    private var connectionStatusSection: some View {
        VStack(alignment: .leading, spacing: Moros.spacing8) {
            HStack {
                Text("Connection")
                    .font(Moros.fontSmall)
                    .foregroundStyle(Moros.textSub)

                Spacer()

                if isTestingConnection {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("Test Connection") {
                        testConnection()
                    }
                    .buttonStyle(MorosButtonStyle())
                    .disabled(!readwiseService.isConfigured)
                }
            }

            if let result = connectionTestResult {
                HStack(spacing: Moros.spacing4) {
                    switch result {
                    case .success:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.green)
                        Text("Connected")
                            .font(Moros.fontSmall)
                            .foregroundStyle(Color.green)
                    case .failure(let msg):
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Moros.signal)
                        Text(msg)
                            .font(Moros.fontSmall)
                            .foregroundStyle(Moros.signal)
                    }
                }
            }

            HStack(spacing: Moros.spacing4) {
                Circle()
                    .fill(readwiseService.isConfigured ? Color.green : Moros.textDim)
                    .frame(width: 6, height: 6)
                Text(readwiseService.isConfigured ? "API key configured" : "No API key set")
                    .font(Moros.fontCaption)
                    .foregroundStyle(Moros.textDim)
            }
        }
        .padding(Moros.spacing12)
        .background(Moros.limit02)
        .overlay(Rectangle().stroke(Moros.border, lineWidth: 1))
    }

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: Moros.spacing8) {
            HStack {
                Text("Sync")
                    .font(Moros.fontSmall)
                    .foregroundStyle(Moros.textSub)

                Spacer()

                if readwiseService.isImporting {
                    HStack(spacing: Moros.spacing4) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Importing...")
                            .font(Moros.fontSmall)
                            .foregroundStyle(Moros.textSub)
                    }
                } else {
                    Button("Sync Now") {
                        syncAll()
                    }
                    .buttonStyle(MorosButtonStyle(accent: Moros.oracle))
                    .disabled(!readwiseService.isConfigured)
                }
            }

            if let lastSync = readwiseService.lastSyncDate {
                Text("Last sync: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                    .font(Moros.fontCaption)
                    .foregroundStyle(Moros.textDim)
            } else {
                Text("Never synced")
                    .font(Moros.fontCaption)
                    .foregroundStyle(Moros.textDim)
            }

            if let error = syncError {
                Text(error)
                    .font(Moros.fontCaption)
                    .foregroundStyle(Moros.signal)
            }

            Toggle("Auto-sync daily", isOn: Binding(
                get: { readwiseService.autoSyncEnabled },
                set: { readwiseService.autoSyncEnabled = $0 }
            ))
            .font(Moros.fontSmall)
            .foregroundStyle(Moros.textSub)
            .toggleStyle(.switch)
            .tint(Moros.oracle)
        }
        .padding(Moros.spacing12)
        .background(Moros.limit02)
        .overlay(Rectangle().stroke(Moros.border, lineWidth: 1))
    }

    private var statsSection: some View {
        Group {
            if let stats = readwiseService.importStats {
                VStack(alignment: .leading, spacing: Moros.spacing8) {
                    Text("Last Import")
                        .font(Moros.fontSmall)
                        .foregroundStyle(Moros.textSub)

                    HStack(spacing: Moros.spacing16) {
                        statItem(label: "Books", value: "\(stats.booksImported)")
                        statItem(label: "Highlights", value: "\(stats.highlightsImported)")
                        statItem(label: "Notes", value: "\(stats.notesCreated)")
                        statItem(label: "Sources", value: "\(stats.sourcesCreated)")
                    }
                }
                .padding(Moros.spacing12)
                .background(Moros.limit02)
                .overlay(Rectangle().stroke(Moros.border, lineWidth: 1))
            }
        }
    }

    private var importBookSection: some View {
        VStack(alignment: .leading, spacing: Moros.spacing8) {
            HStack {
                Text("Import Specific Book")
                    .font(Moros.fontSmall)
                    .foregroundStyle(Moros.textSub)

                Spacer()

                if isFetchingBooks {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("Fetch Books") {
                        fetchBooksList()
                    }
                    .buttonStyle(MorosButtonStyle())
                    .disabled(!readwiseService.isConfigured)
                }
            }

            if !books.isEmpty {
                Picker("Select book", selection: Binding(
                    get: { selectedBookId ?? books.first?.id ?? 0 },
                    set: { selectedBookId = $0 }
                )) {
                    ForEach(books) { book in
                        Text("\(book.title) (\(book.num_highlights) highlights)")
                            .tag(book.id)
                    }
                }
                .font(Moros.fontSmall)

                Button("Import Selected") {
                    if let bookId = selectedBookId {
                        importSelectedBook(bookId: bookId)
                    }
                }
                .buttonStyle(MorosButtonStyle(accent: Moros.oracle))
                .disabled(selectedBookId == nil)
            }
        }
        .padding(Moros.spacing12)
        .background(Moros.limit02)
        .overlay(Rectangle().stroke(Moros.border, lineWidth: 1))
    }

    // MARK: - Helpers

    private func statItem(label: String, value: String) -> some View {
        VStack(spacing: Moros.spacing2) {
            Text(value)
                .font(Moros.fontH3)
                .foregroundStyle(Moros.oracle)
            Text(label)
                .font(Moros.fontCaption)
                .foregroundStyle(Moros.textDim)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Moros.fontH2)
            .foregroundStyle(Moros.textMain)
    }

    private func testConnection() {
        isTestingConnection = true
        connectionTestResult = nil
        Task {
            do {
                let ok = try await readwiseService.testConnection()
                await MainActor.run {
                    connectionTestResult = ok ? .success : .failure("Connection failed")
                    isTestingConnection = false
                }
            } catch {
                await MainActor.run {
                    connectionTestResult = .failure(error.localizedDescription)
                    isTestingConnection = false
                }
            }
        }
    }

    private func syncAll() {
        syncError = nil
        // Import requires CoreData context + services injected from parent.
        // This view signals intent; actual import is triggered via the provided service.
        // For now, post a notification that the parent can observe.
        NotificationCenter.default.post(name: .readwiseSyncRequested, object: nil)
    }

    private func fetchBooksList() {
        isFetchingBooks = true
        Task {
            do {
                let fetched = try await readwiseService.fetchBooks()
                await MainActor.run {
                    books = fetched
                    if selectedBookId == nil { selectedBookId = fetched.first?.id }
                    isFetchingBooks = false
                }
            } catch {
                await MainActor.run {
                    syncError = error.localizedDescription
                    isFetchingBooks = false
                }
            }
        }
    }

    private func importSelectedBook(bookId: Int) {
        NotificationCenter.default.post(
            name: .readwiseImportBookRequested,
            object: nil,
            userInfo: ["bookId": bookId]
        )
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let readwiseSyncRequested = Notification.Name("readwiseSyncRequested")
    static let readwiseImportBookRequested = Notification.Name("readwiseImportBookRequested")
}

// MARK: - MOROS Button Style

struct MorosButtonStyle: ButtonStyle {
    var accent: Color = Moros.ambient

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Moros.fontSmall)
            .foregroundStyle(configuration.isPressed ? accent : Moros.textMain)
            .padding(.horizontal, Moros.spacing8)
            .padding(.vertical, Moros.spacing4)
            .background(configuration.isPressed ? Moros.limit04 : Moros.limit03)
            .overlay(Rectangle().stroke(Moros.border, lineWidth: 1))
    }
}
