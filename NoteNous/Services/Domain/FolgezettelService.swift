import CoreData
import os.log

/// Implements Luhmann's Folgezettel numbering with alternating alphanumeric branching.
///
/// Structure:
/// - `1` → first root note
/// - `1a` → continues note 1 (first continuation)
/// - `1b` → also continues note 1 (second continuation / sibling)
/// - `1a1` → branches from note 1a
/// - `1a1a` → continues that branch
///
/// Levels alternate: number → letter → number → letter → ...
final class FolgezettelService {
    private let context: NSManagedObjectContext
    private let logger = Logger(subsystem: "com.notenous.app", category: "FolgezettelService")

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    // MARK: - ID Generation

    /// Generates the next root-level Folgezettel ID ("1", "2", "3", ...).
    func generateNextRoot() -> String {
        let existingRoots = fetchRootIds()
        let maxRoot = existingRoots
            .compactMap { Int($0) }
            .max() ?? 0
        return String(maxRoot + 1)
    }

    /// Generates the next sibling continuation of a given ID.
    /// - `"1a"` → `"1b"`, `"1b"` → `"1c"`
    /// - `"1a1"` → `"1a2"`, `"1a2"` → `"1a3"`
    /// - `"1"` → `"2"` (root siblings)
    func generateContinuation(of zettelId: String) -> String {
        let parsed = parseId(zettelId)
        guard !parsed.isEmpty else { return "1" }

        var components = parsed
        let lastComponent = components.removeLast()

        switch lastComponent {
        case .number(let n):
            components.append(.number(n + 1))
        case .letter(let ch):
            if let scalar = Unicode.Scalar(ch.unicodeScalars.first!.value + 1) {
                components.append(.letter(String(Character(scalar))))
            } else {
                components.append(.letter(ch))
            }
        }

        return componentsToString(components)
    }

    /// Generates a new sub-level branch from the given ID.
    /// If the current level ends with a number, appends a letter: `"1"` → `"1a"`, `"1a1"` → `"1a1a"`
    /// If the current level ends with a letter, appends a number: `"1a"` → `"1a1"`, `"1a1a"` → `"1a1a1"`
    func generateBranch(from zettelId: String) -> String {
        let parsed = parseId(zettelId)
        guard !parsed.isEmpty else { return "1" }

        let existingChildren = fetchChildrenIds(of: zettelId)
        let lastComponent = parsed.last!

        switch lastComponent {
        case .number:
            // Next level is letter. Find the next available letter.
            let usedLetters = existingChildren.compactMap { childId -> String? in
                let childParsed = parseId(childId)
                guard childParsed.count == parsed.count + 1,
                      case .letter(let l) = childParsed.last else {
                    return nil
                }
                return l
            }
            let nextLetter = nextAvailableLetter(excluding: Set(usedLetters))
            return zettelId + nextLetter

        case .letter:
            // Next level is number. Find the next available number.
            let usedNumbers = existingChildren.compactMap { childId -> Int? in
                let childParsed = parseId(childId)
                guard childParsed.count == parsed.count + 1,
                      case .number(let n) = childParsed.last else {
                    return nil
                }
                return n
            }
            let nextNum = (usedNumbers.max() ?? 0) + 1
            return zettelId + String(nextNum)
        }
    }

    // MARK: - Tree Navigation

    /// Returns the parent ID of a given Zettel ID, or nil if it's a root note.
    func parentId(of zettelId: String) -> String? {
        let parsed = parseId(zettelId)
        guard parsed.count > 1 else { return nil }
        let parentComponents = Array(parsed.dropLast())
        return componentsToString(parentComponents)
    }

    /// Returns the IDs of all immediate children of the given Zettel ID.
    func childrenIds(of zettelId: String, in ctx: NSManagedObjectContext? = nil) -> [String] {
        let targetContext = ctx ?? context
        let allIds = fetchAllZettelIds(in: targetContext)
        let parsed = parseId(zettelId)
        let expectedDepth = parsed.count + 1

        return allIds
            .filter { childId in
                let childParsed = parseId(childId)
                guard childParsed.count == expectedDepth else { return false }
                // Verify the prefix matches
                return childId.hasPrefix(zettelId) && childId != zettelId
            }
            .sorted { sortZettelIds($0, $1) }
    }

    /// Returns an ordered depth-first traversal of the branch starting at the given ID.
    func sequenceFrom(id zettelId: String, in ctx: NSManagedObjectContext? = nil) -> [String] {
        let targetContext = ctx ?? context
        var result: [String] = []
        depthFirstTraversal(zettelId: zettelId, in: targetContext, result: &result)
        return result
    }

    /// Checks if `childId` is a descendant of `parentId` in the Folgezettel tree.
    func isDescendant(_ childId: String, of parentIdentifier: String) -> Bool {
        guard childId.count > parentIdentifier.count else { return false }
        return childId.hasPrefix(parentIdentifier)
    }

    /// Returns sibling IDs (notes sharing the same parent) in sorted order.
    func siblings(of zettelId: String) -> [String] {
        guard let parent = parentId(of: zettelId) else {
            // Root-level siblings
            return fetchRootIds().sorted { sortZettelIds($0, $1) }
        }
        return childrenIds(of: parent)
    }

    /// Returns the previous sibling in sequence, or nil.
    func previousSibling(of zettelId: String) -> String? {
        let sibs = siblings(of: zettelId)
        guard let index = sibs.firstIndex(of: zettelId), index > 0 else { return nil }
        return sibs[index - 1]
    }

    /// Returns the next sibling in sequence, or nil.
    func nextSibling(of zettelId: String) -> String? {
        let sibs = siblings(of: zettelId)
        guard let index = sibs.firstIndex(of: zettelId), index < sibs.count - 1 else { return nil }
        return sibs[index + 1]
    }

    /// Returns the first child of the given note, or nil.
    func firstChild(of zettelId: String) -> String? {
        childrenIds(of: zettelId).first
    }

    // MARK: - Fetch NoteEntity by Folgezettel ID

    func findNote(byFolgezettelId fzId: String, in ctx: NSManagedObjectContext? = nil) -> NoteEntity? {
        let targetContext = ctx ?? context
        let request = NoteEntity.fetchRequest() as! NSFetchRequest<NoteEntity>
        request.predicate = NSPredicate(format: "zettelId == %@", fzId)
        request.fetchLimit = 1
        return try? targetContext.fetch(request).first
    }

    // MARK: - Depth Calculation

    /// Returns the depth level of a Folgezettel ID (root = 1).
    func depth(of zettelId: String) -> Int {
        parseId(zettelId).count
    }

    // MARK: - Private: Parsing

    private enum IdComponent: Equatable {
        case number(Int)
        case letter(String)
    }

    /// Parses a Folgezettel ID into alternating components.
    /// `"1a2b"` → `[.number(1), .letter("a"), .number(2), .letter("b")]`
    private func parseId(_ zettelId: String) -> [IdComponent] {
        var components: [IdComponent] = []
        var currentNumber = ""
        var currentLetters = ""

        for char in zettelId {
            if char.isNumber {
                if !currentLetters.isEmpty {
                    // Each letter is a separate component? No -- consecutive letters form one segment.
                    // Actually in Folgezettel, each level is a single letter or multi-digit number.
                    // "1a" = [1, a], "1ab" shouldn't happen, but "1a10" = [1, a, 10]
                    components.append(.letter(currentLetters))
                    currentLetters = ""
                }
                currentNumber.append(char)
            } else if char.isLetter {
                if !currentNumber.isEmpty {
                    if let n = Int(currentNumber) {
                        components.append(.number(n))
                    }
                    currentNumber = ""
                }
                currentLetters.append(char)
            }
        }

        // Flush remaining
        if !currentNumber.isEmpty, let n = Int(currentNumber) {
            components.append(.number(n))
        }
        if !currentLetters.isEmpty {
            components.append(.letter(currentLetters))
        }

        return components
    }

    private func componentsToString(_ components: [IdComponent]) -> String {
        components.map { component in
            switch component {
            case .number(let n): String(n)
            case .letter(let l): l
            }
        }.joined()
    }

    // MARK: - Private: Sorting

    /// Sorts two Folgezettel IDs in natural order.
    private func sortZettelIds(_ a: String, _ b: String) -> Bool {
        let parsedA = parseId(a)
        let parsedB = parseId(b)

        for i in 0..<min(parsedA.count, parsedB.count) {
            switch (parsedA[i], parsedB[i]) {
            case (.number(let na), .number(let nb)):
                if na != nb { return na < nb }
            case (.letter(let la), .letter(let lb)):
                if la != lb { return la < lb }
            case (.number, .letter):
                return true
            case (.letter, .number):
                return false
            }
        }

        return parsedA.count < parsedB.count
    }

    // MARK: - Private: Traversal

    private func depthFirstTraversal(zettelId: String, in ctx: NSManagedObjectContext, result: inout [String]) {
        result.append(zettelId)
        let children = childrenIds(of: zettelId, in: ctx)
        for child in children {
            depthFirstTraversal(zettelId: child, in: ctx, result: &result)
        }
    }

    // MARK: - Private: Fetching

    private func fetchAllZettelIds(in ctx: NSManagedObjectContext? = nil) -> [String] {
        let targetContext = ctx ?? context
        let request = NoteEntity.fetchRequest() as! NSFetchRequest<NoteEntity>
        request.propertiesToFetch = ["zettelId"]
        request.resultType = .managedObjectResultType

        do {
            let notes = try targetContext.fetch(request)
            return notes.compactMap { $0.zettelId }
        } catch {
            logger.error("Failed to fetch zettel IDs: \(error.localizedDescription)")
            return []
        }
    }

    private func fetchRootIds() -> [String] {
        let allIds = fetchAllZettelIds()
        return allIds.filter { id in
            let parsed = parseId(id)
            return parsed.count == 1 && {
                if case .number = parsed.first { return true }
                return false
            }()
        }
    }

    private func fetchChildrenIds(of zettelId: String) -> [String] {
        childrenIds(of: zettelId)
    }

    private func nextAvailableLetter(excluding used: Set<String>) -> String {
        let alphabet = "abcdefghijklmnopqrstuvwxyz"
        for char in alphabet {
            let s = String(char)
            if !used.contains(s) { return s }
        }
        // Fallback: should not happen in practice
        return "a"
    }
}
