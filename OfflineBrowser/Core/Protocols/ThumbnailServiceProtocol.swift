import Foundation

protocol ThumbnailServiceProtocol {
    func downloadThumbnail(from urlString: String, completion: @escaping (URL?) -> Void)
}
