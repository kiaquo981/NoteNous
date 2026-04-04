import SwiftUI

struct KeyboardCommands: Commands {
    @ObservedObject var appState: AppState

    var body: some Commands {
        // Replace default New Item
        CommandGroup(replacing: .newItem) {
            Button("New Zettel") {
                appState.isZettelCreationVisible = true
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Quick Capture") {
                appState.isQuickCaptureVisible = true
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        // View menu
        CommandMenu("View") {
            Button("Desk") { appState.selectedView = .desk }
                .keyboardShortcut("1", modifiers: .command)
            Button("Stack") { appState.selectedView = .stack }
                .keyboardShortcut("2", modifiers: .command)
            Button("Graph") { appState.selectedView = .graph }
                .keyboardShortcut("3", modifiers: .command)

            Divider()

            Button("Command Palette") { appState.isCommandPaletteVisible.toggle() }
                .keyboardShortcut("k", modifiers: .command)

            Button("Quick Switcher") { appState.isQuickSwitcherVisible.toggle() }
                .keyboardShortcut("o", modifiers: .command)

            Divider()

            Button("Toggle Sidebar") { appState.isSidebarVisible.toggle() }
                .keyboardShortcut(".", modifiers: .command)

            Button("Focus Search") { appState.isSearchFocused = true }
                .keyboardShortcut("f", modifiers: [.command, .shift])

            Button("Semantic Search") { appState.isSemanticSearchVisible.toggle() }
                .keyboardShortcut("f", modifiers: [.command, .option])

            Divider()

            Button("Toggle AI Chat") { appState.isAIChatVisible.toggle() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
        }

        // Notes menu
        CommandMenu("Notes") {
            Button("Create Link") { appState.isLinkCreationVisible = true }
                .keyboardShortcut("l", modifiers: .command)

            Button("Toggle Backlinks") { appState.isBacklinksVisible.toggle() }
                .keyboardShortcut("b", modifiers: .command)

            Button("Toggle Local Graph") { appState.isLocalGraphVisible.toggle() }
                .keyboardShortcut("g", modifiers: .command)

            Button("Open Full Graph") { appState.selectedView = .graph }
                .keyboardShortcut("g", modifiers: [.command, .shift])

            Divider()

            Button("Today's Daily Note") { appState.shouldOpenDailyNote = true }
                .keyboardShortcut("d", modifiers: .command)

            Button("AI Classify") { appState.shouldClassifyNote = true }
                .keyboardShortcut("i", modifiers: .command)

            Divider()

            Button("Import Obsidian Vault") { appState.isImportVisible = true }
                .keyboardShortcut("i", modifiers: [.command, .shift])

            Button("Export All Notes") { appState.isExportVisible = true }
                .keyboardShortcut("e", modifiers: [.command, .shift])

            Button("New Call Note") {
                appState.activeCallNote = nil
                appState.isCallNoteVisible = true
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
        }

        // Navigate menu
        CommandMenu("Navigate") {
            Button("Back") { appState.shouldNavigateBack = true }
                .keyboardShortcut("[", modifiers: .command)

            Button("Forward") { appState.shouldNavigateForward = true }
                .keyboardShortcut("]", modifiers: .command)

            Divider()

            Button("Folgezettel Parent") { appState.navigateFolgezettel = .parent }
                .keyboardShortcut(.upArrow, modifiers: .command)

            Button("Folgezettel Child") { appState.navigateFolgezettel = .child }
                .keyboardShortcut(.downArrow, modifiers: .command)

            Button("Folgezettel Previous") { appState.navigateFolgezettel = .previousSibling }
                .keyboardShortcut(.leftArrow, modifiers: .command)

            Button("Folgezettel Next") { appState.navigateFolgezettel = .nextSibling }
                .keyboardShortcut(.rightArrow, modifiers: .command)
        }
    }
}
