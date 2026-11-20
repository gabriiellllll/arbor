import DiskKit
import Foundation

/// A sidebar location.
struct Place: Equatable {
    enum Kind {
        case computer, iCloudDrive, oneDrive, volume
    }

    let url: URL
    let name: String
    let kind: Kind
}

/// The sidebar's Locations: this computer, cloud drives that exist, other mounted volumes.
enum Locations {
    static func all(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [Place] {
        let computer = Place(
            url: URL(fileURLWithPath: "/", isDirectory: true),
            name: Host.current().localizedName ?? String(localized: "Computer"),
            kind: .computer
        )
        let volumes = MountedVolumes.current().filter { !$0.isRoot }.map {
            Place(url: $0.url, name: $0.name, kind: .volume)
        }
        return [computer] + cloud(home: home) + volumes
    }

    /// iCloud Drive and OneDrive folders, when present in `home`.
    static func cloud(home: URL) -> [Place] {
        let manager = FileManager.default
        var places: [Place] = []
        let iCloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        if manager.fileExists(atPath: iCloud.path) {
            places.append(Place(url: iCloud, name: String(localized: "iCloud Drive"), kind: .iCloudDrive))
        }
        let storage = home.appendingPathComponent("Library/CloudStorage", isDirectory: true)
        let oneDrives = ((try? manager.contentsOfDirectory(atPath: storage.path)) ?? [])
            .filter { $0.hasPrefix("OneDrive") }
            .sorted()
        for folder in oneDrives {
            let url = storage.appendingPathComponent(folder, isDirectory: true)
            places.append(Place(url: url, name: manager.displayName(atPath: url.path), kind: .oneDrive))
        }
        return places
    }
}
