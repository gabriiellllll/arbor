import DiskKit
import Foundation

/// A sidebar location.
struct Place: Equatable {
    enum Kind {
        case computer, iCloudDrive, oneDrive, volume
        /// A cataloged disk that is not plugged in.
        case offlineDisk
        /// A mounted network share.
        case share
        /// A remembered network share that is not mounted; `url` is the share's URL.
        case disconnectedShare
        /// A file server seen on the network; `url` is the server's URL.
        case server
    }

    /// A remote place: clicking it connects to the share or server instead of opening a folder.
    var isRemote: Bool {
        kind == .disconnectedShare || kind == .server
    }

    let url: URL
    let name: String
    let kind: Kind
}

/// The sidebar's Locations: this computer, cloud drives that exist, other mounted volumes,
/// then cataloged disks that are not plugged in. Its Shared section: network shares and servers.
enum Locations {
    static func all(home: URL = FileManager.default.homeDirectoryForCurrentUser, offline: [Place] = []) -> [Place] {
        let computer = Place(
            url: URL(fileURLWithPath: "/", isDirectory: true),
            name: Host.current().localizedName ?? String(localized: "Computer"),
            kind: .computer
        )
        let volumes = MountedVolumes.current().filter { !$0.isRoot && !$0.isNetwork }.map {
            Place(url: $0.url, name: $0.name, kind: .volume)
        }
        return [computer] + cloud(home: home) + volumes + offline
    }

    /// Mounted network shares, remembered shares that are not mounted (connected in one click),
    /// then servers seen on the network.
    static func shared(mounted: [Volume], remembered: [RememberedShare], servers: [NetworkServer]) -> [Place] {
        let mountedURLs = Set(mounted.compactMap(\.remountURL))
        return mounted.map { Place(url: $0.url, name: $0.name, kind: .share) }
            + remembered.filter { !mountedURLs.contains($0.url) }.map {
                Place(url: $0.url, name: $0.name, kind: .disconnectedShare)
            }
            + servers.map { Place(url: $0.url, name: $0.name, kind: .server) }
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
