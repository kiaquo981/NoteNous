import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
            AISettingsView()
                .tabItem { Label("AI", systemImage: "brain") }
            LocalAISettingsView()
                .tabItem { Label("Local AI", systemImage: "cpu") }
            ImportExportView()
                .environmentObject(appState)
                .tabItem { Label("Import/Export", systemImage: "square.and.arrow.up.on.square") }
            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 500)
        .morosTheme()
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @AppStorage("defaultPARACategory") private var defaultPARACategory: Int = 0
    @AppStorage("defaultViewMode") private var defaultViewMode: Int = 2
    @AppStorage("morosThemeMode") private var themeMode: String = "Auto"
    @ObservedObject private var vaultService = VaultService.shared
    @State private var isSyncingAll = false

    var body: some View {
        Form {
            Section("Defaults") {
                Picker("Default PARA Category", selection: $defaultPARACategory) {
                    ForEach(PARACategory.allCases) { category in
                        Text(category.label).tag(Int(category.rawValue))
                    }
                }

                Picker("Default View Mode", selection: $defaultViewMode) {
                    ForEach(ViewMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
            }

            Section("Appearance") {
                Picker("Theme", selection: $themeMode) {
                    ForEach(MorosThemeMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.icon).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                // Theme is applied via preferredColorScheme in NoteNousApp
                Text("Auto follows your Mac's appearance (System Settings → Appearance)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Markdown Vault") {
                LabeledContent("Vault Path") {
                    HStack {
                        Text(vaultService.vaultPath.path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Change...") {
                            chooseVaultPath()
                        }
                    }
                }

                LabeledContent("Files on Disk") {
                    Text("\(vaultService.noteCount()) notes")
                        .monospacedDigit()
                }

                LabeledContent("Disk Usage") {
                    Text(ByteCountFormatter.string(fromByteCount: vaultService.diskUsage(), countStyle: .file))
                        .monospacedDigit()
                }

                HStack {
                    Button("Sync All Now") {
                        isSyncingAll = true
                        DispatchQueue.global(qos: .userInitiated).async {
                            vaultService.syncAll(context: CoreDataStack.shared.viewContext)
                            DispatchQueue.main.async {
                                isSyncingAll = false
                            }
                        }
                    }
                    .disabled(isSyncingAll)

                    if isSyncingAll {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Spacer()

                    Button("Open Vault in Finder") {
                        vaultService.openVaultInFinder()
                    }
                }
            }
        }
        .padding()
    }

    private func chooseVaultPath() {
        let panel = NSOpenPanel()
        panel.title = "Choose Vault Location"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            vaultService.updateVaultPath(url)
        }
    }
}

// MARK: - AI Settings

enum AIModelSelection: String, CaseIterable, Identifiable {
    case geminiFlash = "gemini-flash"
    case claudeHaiku = "claude-haiku"
    case bothWithFallback = "both-fallback"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .geminiFlash: return "Gemini Flash"
        case .claudeHaiku: return "Claude Haiku"
        case .bothWithFallback: return "Both (with fallback)"
        }
    }
}

struct AISettingsView: View {
    @AppStorage("openRouterAPIKey") private var apiKey = ""
    @AppStorage("aiDailyBudget") private var dailyBudget = 0.50
    @AppStorage("aiModelSelection") private var modelSelection = AIModelSelection.geminiFlash.rawValue
    @AppStorage("aiAutoClassify") private var autoClassify = true
    @AppStorage("aiClassifyThreshold") private var classifyThreshold = 0.7

    var body: some View {
        Form {
            Section("API") {
                SecureField("OpenRouter API Key", text: $apiKey)
                TextField("Daily Budget (USD)", value: $dailyBudget, format: .currency(code: "USD"))
            }

            Section("Model") {
                Picker("AI Model", selection: $modelSelection) {
                    ForEach(AIModelSelection.allCases) { model in
                        Text(model.label).tag(model.rawValue)
                    }
                }
            }

            Section("Classification") {
                Toggle("Auto-classify new notes", isOn: $autoClassify)

                VStack(alignment: .leading) {
                    HStack {
                        Text("Classify Threshold")
                        Spacer()
                        Text(String(format: "%.0f%%", classifyThreshold * 100))
                            .foregroundStyle(Moros.textDim)
                            .monospacedDigit()
                    }
                    Slider(value: $classifyThreshold, in: 0.3...1.0, step: 0.05)
                }
            }
        }
        .padding()
    }
}

// MARK: - About Settings

struct AboutSettingsView: View {
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    var body: some View {
        Form {
            Section("NoteNous") {
                LabeledContent("Version", value: "\(appVersion) (\(buildNumber))")
                LabeledContent("Platform", value: "macOS 14+")
            }

            Section("Credits") {
                Text("A Zettelkasten-inspired note-taking app with PARA organization, CODE workflow, and AI-assisted linking.")
                    .foregroundStyle(Moros.textSub)
                    .font(Moros.fontBody)
            }

            Section("Links") {
                Link("GitHub Repository", destination: URL(string: "https://github.com/notenous/notenous")!)
                Link("Report an Issue", destination: URL(string: "https://github.com/notenous/notenous/issues")!)
            }
        }
        .padding()
    }
}
