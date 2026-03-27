import Foundation
import CoreData
import SwiftUI

// MARK: - Force-Directed Graph Layout Engine

@Observable
final class ForceDirectedLayout {

    // MARK: - Data Structures

    struct Node: Identifiable {
        let id: UUID
        var position: CGPoint
        var velocity: CGPoint = .zero
        let note: NoteEntity
        var isFixed: Bool = false
        var radius: CGFloat = 20

        /// Visual-only: cached values for render without Core Data access on draw thread
        var cachedTitle: String = ""
        var cachedPARA: PARACategory = .inbox
        var cachedNoteType: NoteType = .fleeting
        var cachedCODEStage: CODEStage = .captured
        var cachedColorHex: String?
        var cachedLinkCount: Int = 0
        var cachedTags: [String] = []
    }

    struct Edge: Identifiable {
        let id: UUID
        let sourceId: UUID
        let targetId: UUID
        let linkType: LinkType
        let strength: Float
        let isAISuggested: Bool
        let isConfirmed: Bool
    }

    // MARK: - Physics Constants

    private let repulsionStrength: CGFloat = 500
    private let attractionStrength: CGFloat = 0.02
    private let restLength: CGFloat = 120
    private let centerGravity: CGFloat = 0.01
    private let damping: CGFloat = 0.85
    private let collisionPadding: CGFloat = 4
    private let kineticEnergyThreshold: CGFloat = 0.5
    private let maxVelocity: CGFloat = 50

    // MARK: - State

    var nodes: [Node] = []
    var edges: [Edge] = []
    var isRunning: Bool = false
    var centerPoint: CGPoint = CGPoint(x: 400, y: 300)

    /// Lookup for O(1) node index access
    private var nodeIndexMap: [UUID: Int] = [:]

    // MARK: - Display Link Timer

    private var displayLink: CVDisplayLink?
    private var lastTimestamp: CFTimeInterval = 0

    // MARK: - Simulation Step

    /// Performs one tick of the force-directed simulation.
    func step(dt: CGFloat) {
        guard !nodes.isEmpty else { return }

        let dt = min(dt, 0.033) // cap at ~30fps worth of physics
        let count = nodes.count

        // Pre-allocate force accumulators
        var forces = [CGPoint](repeating: .zero, count: count)

        // 1. Repulsion: all pairs (Barnes-Hut would be better for 1000+, but direct is fine for 500)
        for i in 0..<count {
            guard !nodes[i].isFixed else { continue }
            for j in (i + 1)..<count {
                let dx = nodes[i].position.x - nodes[j].position.x
                let dy = nodes[i].position.y - nodes[j].position.y
                let distSq = max(dx * dx + dy * dy, 1)
                let dist = sqrt(distSq)
                let force = repulsionStrength / distSq
                let fx = (dx / dist) * force
                let fy = (dy / dist) * force

                forces[i].x += fx
                forces[i].y += fy
                if !nodes[j].isFixed {
                    forces[j].x -= fx
                    forces[j].y -= fy
                }
            }
        }

        // 2. Attraction: linked pairs (spring force)
        for edge in edges {
            guard let si = nodeIndexMap[edge.sourceId],
                  let ti = nodeIndexMap[edge.targetId] else { continue }

            let dx = nodes[ti].position.x - nodes[si].position.x
            let dy = nodes[ti].position.y - nodes[si].position.y
            let dist = max(sqrt(dx * dx + dy * dy), 1)
            let displacement = dist - restLength
            let springForce = attractionStrength * displacement * CGFloat(max(edge.strength, 0.3))
            let fx = (dx / dist) * springForce
            let fy = (dy / dist) * springForce

            if !nodes[si].isFixed {
                forces[si].x += fx
                forces[si].y += fy
            }
            if !nodes[ti].isFixed {
                forces[ti].x -= fx
                forces[ti].y -= fy
            }
        }

        // 3. Center gravity
        for i in 0..<count {
            guard !nodes[i].isFixed else { continue }
            let dx = centerPoint.x - nodes[i].position.x
            let dy = centerPoint.y - nodes[i].position.y
            forces[i].x += dx * centerGravity
            forces[i].y += dy * centerGravity
        }

        // 4. Apply forces, velocity, damping, collision
        var totalKE: CGFloat = 0

        for i in 0..<count {
            guard !nodes[i].isFixed else { continue }

            // Integrate velocity
            nodes[i].velocity.x = (nodes[i].velocity.x + forces[i].x * dt) * damping
            nodes[i].velocity.y = (nodes[i].velocity.y + forces[i].y * dt) * damping

            // Clamp velocity
            let speed = sqrt(nodes[i].velocity.x * nodes[i].velocity.x + nodes[i].velocity.y * nodes[i].velocity.y)
            if speed > maxVelocity {
                let scale = maxVelocity / speed
                nodes[i].velocity.x *= scale
                nodes[i].velocity.y *= scale
            }

            // Integrate position
            nodes[i].position.x += nodes[i].velocity.x * dt
            nodes[i].position.y += nodes[i].velocity.y * dt

            totalKE += speed * speed
        }

        // 5. Simple collision resolution
        for i in 0..<count {
            for j in (i + 1)..<count {
                let dx = nodes[j].position.x - nodes[i].position.x
                let dy = nodes[j].position.y - nodes[i].position.y
                let dist = sqrt(dx * dx + dy * dy)
                let minDist = nodes[i].radius + nodes[j].radius + collisionPadding

                if dist < minDist && dist > 0.01 {
                    let overlap = (minDist - dist) / 2
                    let nx = dx / dist
                    let ny = dy / dist

                    if !nodes[i].isFixed {
                        nodes[i].position.x -= nx * overlap
                        nodes[i].position.y -= ny * overlap
                    }
                    if !nodes[j].isFixed {
                        nodes[j].position.x += nx * overlap
                        nodes[j].position.y += ny * overlap
                    }
                }
            }
        }

        // 6. Stop simulation when energy is low
        if totalKE < kineticEnergyThreshold {
            stopSimulation()
        }
    }

    // MARK: - Simulation Control

    func startSimulation() {
        guard !isRunning else { return }
        isRunning = true
    }

    func stopSimulation() {
        isRunning = false
    }

    func toggleSimulation() {
        if isRunning {
            stopSimulation()
        } else {
            startSimulation()
        }
    }

    func resetLayout() {
        let count = CGFloat(nodes.count)
        let radius = max(count * 12, 200)
        for i in 0..<nodes.count {
            let angle = (CGFloat(i) / count) * 2 * .pi
            nodes[i].position = CGPoint(
                x: centerPoint.x + cos(angle) * radius,
                y: centerPoint.y + sin(angle) * radius
            )
            nodes[i].velocity = .zero
            nodes[i].isFixed = false
        }
        rebuildIndexMap()
        startSimulation()
    }

    // MARK: - Data Loading

    /// Load the full graph from Core Data.
    func loadFromContext(_ context: NSManagedObjectContext, centerNote: NoteEntity?, depth: Int) {
        let notesToInclude: [NoteEntity]

        if let center = centerNote {
            notesToInclude = gatherNeighborhood(center: center, depth: depth, context: context)
        } else {
            let request = NSFetchRequest<NoteEntity>(entityName: "NoteEntity")
            request.predicate = NSPredicate(format: "isArchived == NO")
            notesToInclude = (try? context.fetch(request)) ?? []
        }

        buildGraph(from: notesToInclude, centerNote: centerNote)
    }

    /// BFS to gather notes within `depth` hops of center.
    private func gatherNeighborhood(center: NoteEntity, depth: Int, context: NSManagedObjectContext) -> [NoteEntity] {
        var visited = Set<UUID>()
        var queue: [(NoteEntity, Int)] = [(center, 0)]
        var result: [NoteEntity] = []

        if let cid = center.id {
            visited.insert(cid)
        }

        while !queue.isEmpty {
            let (note, currentDepth) = queue.removeFirst()
            result.append(note)

            if currentDepth < depth {
                let neighbors = note.outgoingLinksArray.compactMap(\.targetNote)
                    + note.incomingLinksArray.compactMap(\.sourceNote)

                for neighbor in neighbors {
                    guard let nid = neighbor.id, !visited.contains(nid) else { continue }
                    visited.insert(nid)
                    queue.append((neighbor, currentDepth + 1))
                }
            }
        }

        return result
    }

    private func buildGraph(from notes: [NoteEntity], centerNote: NoteEntity?) {
        let noteIds = Set(notes.compactMap(\.id))

        // Build nodes with cached render data
        var newNodes: [Node] = []
        for (index, note) in notes.enumerated() {
            guard let noteId = note.id else { continue }

            let linkCount = note.totalLinkCount
            let radius = radiusForLinkCount(linkCount)

            let count = CGFloat(notes.count)
            let baseRadius = max(count * 10, 150)
            let angle = (CGFloat(index) / max(count, 1)) * 2 * .pi

            let isCenterNode = (centerNote?.id == noteId)
            let position: CGPoint
            if isCenterNode {
                position = centerPoint
            } else if note.positionX != 0 || note.positionY != 0 {
                position = CGPoint(x: note.positionX, y: note.positionY)
            } else {
                position = CGPoint(
                    x: centerPoint.x + cos(angle) * baseRadius + CGFloat.random(in: -20...20),
                    y: centerPoint.y + sin(angle) * baseRadius + CGFloat.random(in: -20...20)
                )
            }

            var node = Node(
                id: noteId,
                position: position,
                note: note,
                isFixed: isCenterNode,
                radius: radius
            )
            node.cachedTitle = note.title
            node.cachedPARA = note.paraCategory
            node.cachedNoteType = note.noteType
            node.cachedCODEStage = note.codeStage
            node.cachedColorHex = note.colorHex
            node.cachedLinkCount = linkCount
            node.cachedTags = note.tagsArray.compactMap(\.name)

            newNodes.append(node)
        }

        // Build edges (only between nodes present in the graph)
        var newEdges: [Edge] = []
        var seenEdges = Set<UUID>()

        for note in notes {
            for link in note.outgoingLinksArray {
                guard let linkId = link.id,
                      let sourceId = link.sourceNote?.id,
                      let targetId = link.targetNote?.id,
                      noteIds.contains(sourceId),
                      noteIds.contains(targetId),
                      !seenEdges.contains(linkId) else { continue }

                seenEdges.insert(linkId)
                newEdges.append(Edge(
                    id: linkId,
                    sourceId: sourceId,
                    targetId: targetId,
                    linkType: link.linkType,
                    strength: link.strength,
                    isAISuggested: link.isAISuggested,
                    isConfirmed: link.isConfirmed
                ))
            }
        }

        nodes = newNodes
        edges = newEdges
        rebuildIndexMap()
        startSimulation()
    }

    // MARK: - Helpers

    private func rebuildIndexMap() {
        nodeIndexMap.removeAll(keepingCapacity: true)
        for (index, node) in nodes.enumerated() {
            nodeIndexMap[node.id] = index
        }
    }

    /// Maps link count to node radius (15pt - 40pt).
    private func radiusForLinkCount(_ count: Int) -> CGFloat {
        let minR: CGFloat = 15
        let maxR: CGFloat = 40
        let clamped = min(CGFloat(count), 20)
        return minR + (maxR - minR) * (clamped / 20)
    }

    // MARK: - Node Interaction

    func nodeAt(point: CGPoint, zoom: CGFloat, offset: CGPoint) -> Node? {
        let worldPoint = CGPoint(
            x: (point.x - offset.x) / zoom,
            y: (point.y - offset.y) / zoom
        )
        return nodes.first { node in
            let dx = worldPoint.x - node.position.x
            let dy = worldPoint.y - node.position.y
            return sqrt(dx * dx + dy * dy) <= node.radius + 5
        }
    }

    func moveNode(id: UUID, to position: CGPoint) {
        guard let index = nodeIndexMap[id] else { return }
        nodes[index].position = position
        nodes[index].velocity = .zero
    }

    func pinNode(id: UUID, pinned: Bool) {
        guard let index = nodeIndexMap[id] else { return }
        nodes[index].isFixed = pinned
    }

    func nodeIndex(for id: UUID) -> Int? {
        nodeIndexMap[id]
    }
}
