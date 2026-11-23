import DiskArbitration
import Foundation
import IOKit

/// What is known about the disk holding a volume. Codable so a catalog keeps it for disks
/// that are not plugged in.
public struct DiskDetails: Codable, Equatable, Sendable {
    public var name: String
    public var volumeUUID: String?
    public var vendor: String?
    public var model: String?
    public var serialNumber: String?
    /// How the disk is attached: USB, Thunderbolt, SATA, PCI-Express, Apple Fabric…
    public var connection: String?
    public var isInternal: Bool
    public var capacity: Int64?
    public var fileSystem: String?

    public init(
        name: String, volumeUUID: String? = nil, vendor: String? = nil, model: String? = nil,
        serialNumber: String? = nil, connection: String? = nil, isInternal: Bool = false, capacity: Int64? = nil,
        fileSystem: String? = nil
    ) {
        self.name = name
        self.volumeUUID = volumeUUID
        self.vendor = vendor
        self.model = model
        self.serialNumber = serialNumber
        self.connection = connection
        self.isInternal = isInternal
        self.capacity = capacity
        self.fileSystem = fileSystem
    }

    /// Details of the mounted volume at `url` (its mount point), from Disk Arbitration and the
    /// I/O Registry. Nil when nothing is mounted there.
    public static func of(volume url: URL) -> DiskDetails? {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey, .volumeUUIDStringKey, .volumeTotalCapacityKey, .volumeLocalizedFormatDescriptionKey,
            .volumeIsInternalKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys), let name = values.volumeName else { return nil }
        var details = DiskDetails(
            name: name, volumeUUID: values.volumeUUIDString, isInternal: values.volumeIsInternal ?? false,
            capacity: values.volumeTotalCapacity.map(Int64.init), fileSystem: values.volumeLocalizedFormatDescription
        )
        guard let session = DASessionCreate(nil),
              let disk = DADiskCreateFromVolumePath(nil, session, url as CFURL),
              let description = DADiskCopyDescription(disk) as? [String: Any]
        else { return details }
        let text = { (key: CFString) in clean(description[key as String] as? String) }
        details.vendor = text(kDADiskDescriptionDeviceVendorKey)
        details.model = text(kDADiskDescriptionDeviceModelKey)
        details.connection = text(kDADiskDescriptionDeviceProtocolKey)
        details.fileSystem = details.fileSystem ?? text(kDADiskDescriptionVolumeKindKey)
        let media = DADiskCopyIOMedia(disk)
        defer { IOObjectRelease(media) }
        details.serialNumber = serialNumber(of: media)
        return details
    }

    /// USB disks carry their serial on the USB device; others in the storage device's
    /// characteristics. Both are found by walking up from the volume's media.
    private static func serialNumber(of media: io_service_t) -> String? {
        let search = { (key: String) in
            IORegistryEntrySearchCFProperty(
                media, kIOServicePlane, key as CFString, nil,
                IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
            )
        }
        let characteristics = search("Device Characteristics") as? [String: Any]
        return clean(search("USB Serial Number") as? String)
            ?? clean(characteristics?["Serial Number"] as? String)
            ?? clean(search("Serial Number") as? String)
    }

    /// Device strings are often padded with spaces, and empty when unknown.
    private static func clean(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
