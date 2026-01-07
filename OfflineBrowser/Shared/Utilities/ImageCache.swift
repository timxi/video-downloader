import UIKit

final class ImageCache {
    static let shared = ImageCache()

    private let cache = NSCache<NSString, UIImage>()
    private let maxCacheSize = 50 // Maximum number of images

    private init() {
        cache.countLimit = maxCacheSize

        // Listen for memory warnings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clearCache),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func setImage(_ image: UIImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
    }

    @objc func clearCache() {
        cache.removeAllObjects()
        print("[ImageCache] Cache cleared")
    }
}
