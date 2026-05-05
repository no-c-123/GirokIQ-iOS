import UIKit

final class ImageCache {
    static let shared = ImageCache()

    // NSCache automatically evicts entries under memory pressure and is
    // thread-safe by default — no manual locking required.
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        // Cap at 50 images or 200 MB, whichever comes first.
        // On memory warning the OS will evict below these limits automatically.
        cache.countLimit = 50
        cache.totalCostLimit = 200 * 1024 * 1024
    }

    func store(_ image: UIImage, for key: String) {
        // Use the image's in-memory byte size as the cost so totalCostLimit
        // reflects actual RAM usage rather than just entry count.
        let cost = imageCost(image)
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }

    func retrieve(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func remove(for key: String) {
        cache.removeObject(forKey: key as NSString)
    }

    func removeAll() {
        cache.removeAllObjects()
    }

    // MARK: - Private

    private func imageCost(_ image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 1 }
        // bytes per row × height gives the actual decoded bitmap size in memory
        return cgImage.bytesPerRow * cgImage.height
    }
}
