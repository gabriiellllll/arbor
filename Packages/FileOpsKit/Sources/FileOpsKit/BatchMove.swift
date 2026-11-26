import Foundation

/// Moves items through a temporary name in their folder, so they can take each other's names
/// (swaps, chains, case-only changes). All or nothing: on failure or cancel, every item goes
/// back where it was.
enum BatchMove {
    struct Move {
        let source: URL
        let destination: URL
    }

    private struct Parked {
        let temp: URL
        let move: Move
    }

    static func isValid(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains(":")
    }

    /// `checkpoint` throws to cancel; `advance` is called for each item in place.
    static func perform(
        _ moves: [Move], checkpoint: () throws -> Void, advance: () -> Void
    ) throws -> [Change] {
        let fileManager = FileManager.default
        var parked: [Parked] = []
        var placed = 0
        do {
            for move in moves {
                try checkpoint()
                let temp = move.source.deletingLastPathComponent()
                    .appendingPathComponent("Arbor renaming \(UUID().uuidString) \(move.source.lastPathComponent)")
                try fileManager.moveItem(at: move.source, to: temp)
                parked.append(Parked(temp: temp, move: move))
            }
            for item in parked {
                try checkpoint()
                if fileManager.fileExists(atPath: item.move.destination.path) {
                    throw FileOperationRunner.Failure.nameTaken(item.move.destination.lastPathComponent)
                }
                try fileManager.moveItem(at: item.temp, to: item.move.destination)
                placed += 1
                advance()
            }
        } catch {
            for item in parked[..<placed] {
                try? fileManager.moveItem(at: item.move.destination, to: item.temp)
            }
            for item in parked {
                try? fileManager.moveItem(at: item.temp, to: item.move.source)
            }
            throw error
        }
        return moves.map { Change(kind: .moved(from: $0.source), url: $0.destination) }
    }
}
