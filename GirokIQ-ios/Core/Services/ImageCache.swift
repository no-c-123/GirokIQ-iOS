import UIKit

final class ImageCache {
    static let shared = ImageCache()
    private var cache: [String: UIImage] = [:]
    private let lock = NSLock()
    private init() {}

    func store(_ image: UIImage, for key: String) {
        lock.lock(); defer { lock.unlock() }
        cache[key] = image
    }

    func retrieve(for key: String) -> UIImage? {
        lock.lock(); defer { lock.unlock() }
        return cache[key]
    }

    func remove(for key: String) {
        lock.lock(); defer { lock.unlock() }
        cache.removeValue(forKey: key)
    }
}
