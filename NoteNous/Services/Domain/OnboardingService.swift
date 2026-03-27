import CoreData
import os.log

struct OnboardingService {
    private static let hasOnboardedKey = "com.notenous.hasOnboarded"
    private static let logger = Logger(subsystem: "com.notenous.app", category: "OnboardingService")

    static func runIfNeeded(context: NSManagedObjectContext) {
        guard !UserDefaults.standard.bool(forKey: hasOnboardedKey) else { return }

        logger.info("First launch detected — creating onboarding notes")
        createWelcomeNotes(context: context)
        UserDefaults.standard.set(true, forKey: hasOnboardedKey)
    }

    // MARK: - Private

    private static func createWelcomeNotes(context: NSManagedObjectContext) {
        let noteService = NoteService(context: context)
        let linkService = LinkService(context: context)
        let tagService = TagService(context: context)

        // Note 1 — Welcome to NoteNous (permanent, area)
        let note1 = noteService.createNote(
            title: "Welcome to NoteNous",
            content: """
            NoteNous is your Zettelkasten — a thinking tool, not a filing cabinet.

            Every note here is atomic: one idea, clearly titled, densely linked.

            The three note types:
            - **Fleeting**: Quick captures. Process within days or discard.
            - **Literature**: From a source, in your own words.
            - **Permanent**: A developed idea, ready to connect.

            Start by pressing \u{2318}N to capture a thought.
            """,
            paraCategory: .area
        )
        note1.noteType = .permanent

        // Note 2 — The power of [[wikilinks]] (permanent, resource)
        let note2 = noteService.createNote(
            title: "The power of [[wikilinks]]",
            content: """
            Type [[ to link to any note. Links are bidirectional — every connection is visible from both sides.

            Links have types:
            - **Reference**: neutral connection
            - **Supports**: this idea reinforces the target
            - **Contradicts**: this idea conflicts with the target
            - **Extends**: this idea builds upon the target
            - **Example**: this illustrates the target concept

            The backlinks panel below every note shows who links HERE.
            """,
            paraCategory: .resource
        )
        note2.noteType = .permanent

        // Note 3 — Folgezettel: Luhmann's numbering (permanent, resource)
        let note3 = noteService.createNote(
            title: "Folgezettel: Luhmann's numbering",
            content: """
            Notes are numbered in branching sequences: 1 → 1a → 1a1 → 1a1a

            - Numbers and letters alternate at each level
            - A continuation (sibling) increments: 1a → 1b
            - A branch (child) adds a new level: 1a → 1a1

            This is NOT a filing system. Place notes where the THOUGHT continues, not where the TOPIC belongs.

            Use the sequence navigator (arrows above the editor) to traverse branches.
            """,
            paraCategory: .resource
        )
        note3.noteType = .permanent

        // Note 4 — The Graph reveals connections (fleeting, inbox)
        let note4 = noteService.createNote(
            title: "The Graph reveals connections",
            content: """
            Press \u{2318}3 to open the Graph View. Every node is a note, every line is a link.

            The force-directed layout positions connected ideas close together. Clusters emerge naturally.

            The local graph (toggle in the editor) shows only YOUR note's neighborhood.
            """,
            paraCategory: .inbox
        )
        note4.noteType = .fleeting

        // Note 5 — Process your fleeting notes (fleeting, inbox)
        let note5 = noteService.createNote(
            title: "Process your fleeting notes",
            content: """
            This is a fleeting note. It belongs in the inbox until you PROCESS it.

            Go to Workflow → Fleeting Queue to see all unprocessed notes.

            The rule: capture fast, process later. Never let fleeting notes accumulate beyond a week.
            """,
            paraCategory: .inbox
        )
        note5.noteType = .fleeting

        // Links
        linkService.createLink(from: note2, to: note1, type: .reference)
        linkService.createLink(from: note3, to: note1, type: .extends)
        linkService.createLink(from: note4, to: note2, type: .reference)

        // Tag all with "notenous-guide"
        let guideTag = tagService.findOrCreate(name: "notenous-guide")
        tagService.addTag(guideTag, to: note1)
        tagService.addTag(guideTag, to: note2)
        tagService.addTag(guideTag, to: note3)
        tagService.addTag(guideTag, to: note4)
        tagService.addTag(guideTag, to: note5)

        try? context.save()
        logger.info("Onboarding complete — 5 welcome notes created")
    }
}
