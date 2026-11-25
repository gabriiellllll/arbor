import Foundation
import Network

/// A file server seen on the local network.
public struct NetworkServer: Equatable, Sendable {
    public let name: String
    /// The server's SMB URL, by its Bonjour name: NetFS resolves it and shows the share picker.
    public let url: URL

    public init(name: String) {
        self.name = name
        let host = name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? name
        url = URL(string: "smb://\(host)._smb._tcp.local")!
    }
}

// ponytail: SMB only. AFP is deprecated and NFS servers rarely advertise; browse
// `_afpovertcp._tcp` / `_nfs._tcp` too if users ask for them.

/// Lists the SMB servers advertised on the local network (Bonjour). macOS asks the user for
/// Local Network access the first time.
@MainActor
public final class ServerBrowser {
    public private(set) var servers: [NetworkServer] = []
    public var onChange: (() -> Void)?
    private var browser: NWBrowser?

    public init() {}

    public func start() {
        let browser = NWBrowser(for: .bonjour(type: "_smb._tcp", domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated { self?.update(results) }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    public func stop() {
        browser?.cancel()
        browser = nil
    }

    private func update(_ results: Set<NWBrowser.Result>) {
        let names = results.compactMap { result -> String? in
            if case let .service(name, _, _, _) = result.endpoint {
                return name
            }
            return nil
        }
        servers = Self.servers(named: names)
        onChange?()
    }

    /// One server per name (it may be seen on several interfaces), sorted.
    nonisolated static func servers(named names: [String]) -> [NetworkServer] {
        Set(names).sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map(NetworkServer.init)
    }
}
