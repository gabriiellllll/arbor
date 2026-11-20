import Foundation
import IndexKit

/// What a search panel looks for, as its filter controls show it. Saved with the workspace;
/// dates are relative ("past week") so a restored search stays current.
struct SearchSpec: Codable, Equatable {
    enum KindFilter: String, Codable, CaseIterable {
        case folders, files, images, documents, audio, video, archives, code
    }

    enum Age: String, Codable, CaseIterable {
        case day, week, month, year
    }

    static let minSizes: [Int64] = [1_000_000, 100_000_000, 1_000_000_000]

    var text = ""
    var kind: KindFilter?
    var minSize: Int64?
    var age: Age?
    var tag: String?
    var rootID: Int64?

    func query(now: Date = Date()) -> SearchQuery {
        var query = SearchQuery(text: text, minSize: minSize, tag: tag, rootID: rootID)
        switch kind {
        case .folders: query.kind = .folders
        case .files: query.kind = .files
        case let kind?: query.category = FileCategory(rawValue: kind.rawValue)
        case nil: break
        }
        if let age {
            let component: Calendar.Component = switch age {
            case .day: .day
            case .week: .weekOfYear
            case .month: .month
            case .year: .year
            }
            query.modifiedAfter = Calendar.current.date(byAdding: component, value: -1, to: now)
        }
        return query
    }

    /// Panel title: the words searched, or the tag when searching by tag alone.
    var title: String {
        if text.isEmpty, let tag {
            return String(localized: "Tag: \(tag)")
        }
        return String(localized: "Search: \(text)")
    }
}
