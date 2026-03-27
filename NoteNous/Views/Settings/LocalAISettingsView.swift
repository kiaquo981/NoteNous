import SwiftUI
import NaturalLanguage

// MARK: - Local AI Settings View

struct LocalAISettingsView: View {
    @AppStorage(AIProviderRouter.useLocalAIKey) private var useLocalAI = true
    @AppStorage(AIProviderRouter.preferLocalKey) private var preferLocal = true
    @AppStorage("localAIEmbeddingLanguage") private var embeddingLanguage = "en"

    @StateObject private var localAI = LocalAIService.shared

    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        Form {
            Section("Local AI") {
                Toggle("Enable Local AI", isOn: $useLocalAI)
                    .help("Use Apple NaturalLanguage framework for on-device AI. No API calls, zero cost, full privacy.")

                Toggle("Prefer Local over API", isOn: $preferLocal)
                    .help("When both local and API are available, prefer local for embeddings, classification, and link suggestions.")
                    .disabled(!useLocalAI)
            }

            Section("NLEmbedding Status") {
                ForEach(localAI.supportedLanguages, id: \.language.rawValue) { info in
                    HStack {
                        Text(languageLabel(info.language))
                            .font(Moros.fontBody)
                        Spacer()
                        HStack(spacing: Moros.spacing8) {
                            statusBadge("Sentence", available: info.hasSentence)
                            statusBadge("Word", available: info.hasWord)
                        }
                    }
                }

                Picker("Embedding Language", selection: $embeddingLanguage) {
                    Text("English").tag("en")
                    Text("Portuguese").tag("pt")
                    Text("Spanish").tag("es")
                    Text("French").tag("fr")
                    Text("German").tag("de")
                }
                .onChange(of: embeddingLanguage) { _, newValue in
                    let lang = nlLanguage(from: newValue)
                    localAI.setEmbeddingLanguage(lang)
                }
            }

            Section("Performance") {
                LabeledContent("Avg Embedding Time") {
                    Text(String(format: "%.1f ms", localAI.averageEmbeddingTimeMs))
                        .font(Moros.fontMono)
                        .foregroundStyle(Moros.oracle)
                }
                LabeledContent("Avg Classification Time") {
                    Text(String(format: "%.1f ms", localAI.averageClassificationTimeMs))
                        .font(Moros.fontMono)
                        .foregroundStyle(Moros.oracle)
                }
            }

            Section("Test") {
                Button(action: runTest) {
                    HStack {
                        if isTesting {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 14, height: 14)
                        }
                        Text(isTesting ? "Testing..." : "Test Local AI")
                    }
                }
                .disabled(isTesting || !useLocalAI)

                if let result = testResult {
                    Text(result)
                        .font(Moros.fontSmall)
                        .foregroundStyle(Moros.textSub)
                        .textSelection(.enabled)
                }
            }
        }
        .padding()
    }

    // MARK: - Helpers

    private func statusBadge(_ label: String, available: Bool) -> some View {
        HStack(spacing: 2) {
            Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(available ? Moros.verdit : Moros.signal)
                .font(.system(size: 10))
            Text(label)
                .font(Moros.fontCaption)
                .foregroundStyle(Moros.textDim)
        }
    }

    private func languageLabel(_ lang: NLLanguage) -> String {
        switch lang {
        case .english: return "English"
        case .portuguese: return "Portuguese"
        case .spanish: return "Spanish"
        case .french: return "French"
        case .german: return "German"
        default: return lang.rawValue
        }
    }

    private func nlLanguage(from code: String) -> NLLanguage {
        switch code {
        case "en": return .english
        case "pt": return .portuguese
        case "es": return .spanish
        case "fr": return .french
        case "de": return .german
        default: return .english
        }
    }

    private func runTest() {
        isTesting = true
        testResult = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let sampleText = "Knowledge management systems help organize information effectively. The Zettelkasten method creates a network of interconnected notes that facilitate creative thinking."

            var lines: [String] = []

            // Test embedding
            let embStart = CFAbsoluteTimeGetCurrent()
            if let embedding = localAI.generateEmbedding(text: sampleText) {
                let embTime = (CFAbsoluteTimeGetCurrent() - embStart) * 1000
                lines.append("Embedding: \(embedding.count)-dim vector in \(String(format: "%.1f", embTime))ms")
            } else {
                lines.append("Embedding: FAILED (no NLEmbedding available)")
            }

            // Test classification
            let clsStart = CFAbsoluteTimeGetCurrent()
            let result = localAI.classifyLocally(title: "Knowledge Management", content: sampleText)
            let clsTime = (CFAbsoluteTimeGetCurrent() - clsStart) * 1000
            lines.append("PARA: \(result.para_category), Type: \(result.note_type), CODE: \(result.code_stage) in \(String(format: "%.1f", clsTime))ms")

            // Test tags
            let tags = localAI.extractTags(from: sampleText, limit: 5)
            lines.append("Tags: \(tags.joined(separator: ", "))")

            // Test concepts
            let concepts = localAI.extractConcepts(from: sampleText, limit: 3)
            lines.append("Concepts: \(concepts.joined(separator: ", "))")

            // Test sentiment
            let sentiment = localAI.analyzeSentiment(text: sampleText)
            lines.append("Sentiment: \(String(format: "%.2f", sentiment))")

            // Test language
            if let lang = localAI.detectLanguage(text: sampleText) {
                lines.append("Language: \(lang)")
            }

            DispatchQueue.main.async {
                testResult = lines.joined(separator: "\n")
                isTesting = false
            }
        }
    }
}
