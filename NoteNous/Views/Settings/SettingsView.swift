import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
            AISettingsView()
                .tabItem { Label("AI", systemImage: "brain") }
        }
        .frame(width: 450, height: 300)
    }
}

struct GeneralSettingsView: View {
    var body: some View {
        Form {
            Text("General settings coming soon")
        }
        .padding()
    }
}

struct AISettingsView: View {
    @AppStorage("openRouterAPIKey") private var apiKey = ""
    @AppStorage("aiDailyBudget") private var dailyBudget = 0.50

    var body: some View {
        Form {
            SecureField("OpenRouter API Key", text: $apiKey)
            TextField("Daily Budget (USD)", value: $dailyBudget, format: .currency(code: "USD"))
        }
        .padding()
    }
}
