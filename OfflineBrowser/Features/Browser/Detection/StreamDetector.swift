import Foundation
import Combine

final class StreamDetector: ObservableObject {
    static let shared = StreamDetector()

    @Published private(set) var detectedStreams: [DetectedStream] = []

    private let hlsParser = HLSParser()
    private var processingURLs: Set<String> = []

    private init() {}

    // MARK: - Public Methods

    func addStream(url: String, type: StreamType) {
        // Avoid duplicates
        guard !detectedStreams.contains(where: { $0.url == url }) else { return }

        // Avoid processing the same URL multiple times
        guard !processingURLs.contains(url) else { return }

        var stream = DetectedStream(url: url, type: type)

        // For HLS streams, fetch and parse the manifest for additional info
        if type == .hls {
            processingURLs.insert(url)
            parseHLSManifest(url: url, stream: stream)
        } else {
            detectedStreams.append(stream)
        }
    }

    func clearStreams() {
        detectedStreams.removeAll()
        processingURLs.removeAll()
    }

    func removeStream(_ stream: DetectedStream) {
        detectedStreams.removeAll { $0.id == stream.id }
    }

    // MARK: - HLS Parsing

    private func parseHLSManifest(url: String, stream: DetectedStream) {
        guard let manifestURL = URL(string: url) else {
            processingURLs.remove(url)
            detectedStreams.append(stream)
            return
        }

        hlsParser.parse(url: manifestURL) { [weak self] result in
            DispatchQueue.main.async {
                self?.processingURLs.remove(url)

                switch result {
                case .success(let parsedInfo):
                    var updatedStream = stream
                    updatedStream.qualities = parsedInfo.qualities
                    updatedStream.isLive = parsedInfo.isLive
                    updatedStream.isDRMProtected = parsedInfo.isDRMProtected
                    updatedStream.hasSubtitles = parsedInfo.hasSubtitles

                    // Skip DRM-protected or live streams
                    if parsedInfo.isDRMProtected == true {
                        print("Skipping DRM-protected stream: \(url)")
                        return
                    }
                    if parsedInfo.isLive == true {
                        print("Skipping live stream: \(url)")
                        return
                    }

                    self?.detectedStreams.append(updatedStream)

                case .failure(let error):
                    print("Failed to parse HLS manifest: \(error)")
                    // Still add the stream, just without quality info
                    self?.detectedStreams.append(stream)
                }
            }
        }
    }
}
