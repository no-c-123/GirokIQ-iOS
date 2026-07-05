import Foundation
import Network
import Combine

/// Lightweight reachability + interface-type monitor used to respect "Wi‑Fi only" sync.
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var isConnected: Bool = true
    @Published private(set) var isOnWiFi: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let connected = path.status == .satisfied
            let wifi = path.usesInterfaceType(.wifi)
            DispatchQueue.main.async {
                self.isConnected = connected
                self.isOnWiFi = wifi
            }
        }
        monitor.start(queue: queue)
    }
}

