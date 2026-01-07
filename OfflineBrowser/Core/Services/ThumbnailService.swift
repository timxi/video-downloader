import Foundation
import UIKit
import os.log

private let thumbnailLogger = Logger(subsystem: "com.offlinebrowser", category: "ThumbnailService")

final class ThumbnailService: ThumbnailServiceProtocol {
    static let shared = ThumbnailService()

    private let fileStorage: FileStorageManagerProtocol
    private let urlSession: URLSessionProtocol

    init(fileStorage: FileStorageManagerProtocol = FileStorageManager.shared,
         urlSession: URLSessionProtocol = URLSession.shared) {
        self.fileStorage = fileStorage
        self.urlSession = urlSession
    }

    // MARK: - ThumbnailServiceProtocol

    func downloadThumbnail(from urlString: String, completion: @escaping (URL?) -> Void) {
        guard let url = URL(string: urlString) else {
            thumbnailLogger.warning("Invalid thumbnail URL: \(urlString)")
            DispatchQueue.main.async { completion(nil) }
            return
        }

        thumbnailLogger.debug("Downloading thumbnail from: \(urlString)")

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        let task = urlSession.data(with: request) { [weak self] data, response, error in
            guard let self = self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            if let error = error {
                thumbnailLogger.error("Thumbnail download failed: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(nil) }
                return
            }

            guard let data = data, !data.isEmpty else {
                thumbnailLogger.warning("Empty response for thumbnail")
                DispatchQueue.main.async { completion(nil) }
                return
            }

            // Verify it's an image
            guard let image = UIImage(data: data) else {
                thumbnailLogger.warning("Response is not a valid image")
                DispatchQueue.main.async { completion(nil) }
                return
            }

            // Resize if needed and convert to JPEG
            let resizedImage = self.resizeImageIfNeeded(image, maxSize: 400)
            guard let jpegData = resizedImage.jpegData(compressionQuality: 0.8) else {
                thumbnailLogger.error("Failed to convert image to JPEG")
                DispatchQueue.main.async { completion(nil) }
                return
            }

            // Save to thumbnails directory
            let thumbnailURL = self.fileStorage.thumbnailsDirectory
                .appendingPathComponent("\(UUID().uuidString).jpg")

            do {
                try jpegData.write(to: thumbnailURL)
                thumbnailLogger.debug("Thumbnail saved to: \(thumbnailURL.path)")
                DispatchQueue.main.async { completion(thumbnailURL) }
            } catch {
                thumbnailLogger.error("Failed to save thumbnail: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(nil) }
            }
        }
        task.resume()
    }

    // MARK: - Private Methods

    private func resizeImageIfNeeded(_ image: UIImage, maxSize: CGFloat) -> UIImage {
        let size = image.size

        // No resize needed if already small enough
        if size.width <= maxSize && size.height <= maxSize {
            return image
        }

        // Calculate new size maintaining aspect ratio
        let aspectRatio = size.width / size.height
        let newSize: CGSize
        if aspectRatio > 1 {
            // Landscape
            newSize = CGSize(width: maxSize, height: maxSize / aspectRatio)
        } else {
            // Portrait or square
            newSize = CGSize(width: maxSize * aspectRatio, height: maxSize)
        }

        // Render resized image
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
