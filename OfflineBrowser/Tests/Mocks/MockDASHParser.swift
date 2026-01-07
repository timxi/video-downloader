import Foundation
@testable import OfflineBrowser

final class MockDASHParser: DASHParserProtocol {

    // MARK: - Call Tracking

    private(set) var parseURLCalls: [URL] = []
    private(set) var parseManifestCalls: [(content: String, baseURL: URL)] = []

    // MARK: - Configurable Responses

    var parseURLHandler: ((URL) -> Result<DASHParsedInfo, DASHParser.ParseError>)?
    var parseManifestHandler: ((String, URL) -> Result<DASHParsedInfo, DASHParser.ParseError>)?

    // MARK: - DASHParserProtocol

    func parse(url: URL, completion: @escaping (Result<DASHParsedInfo, DASHParser.ParseError>) -> Void) {
        parseURLCalls.append(url)

        if let handler = parseURLHandler {
            completion(handler(url))
        } else {
            completion(.success(Self.makeDefaultInfo()))
        }
    }

    func parseManifest(content: String, baseURL: URL, completion: @escaping (Result<DASHParsedInfo, DASHParser.ParseError>) -> Void) {
        parseManifestCalls.append((content, baseURL))

        if let handler = parseManifestHandler {
            completion(handler(content, baseURL))
        } else {
            completion(.success(Self.makeDefaultInfo()))
        }
    }

    // MARK: - Factory Methods

    static func makeDefaultInfo() -> DASHParsedInfo {
        DASHParsedInfo(
            qualities: [
                StreamQuality(
                    id: UUID(),
                    resolution: "1080p",
                    bandwidth: 5_000_000,
                    url: "https://example.com/video/1080p/init.mp4",
                    codecs: "avc1.640028"
                ),
                StreamQuality(
                    id: UUID(),
                    resolution: "720p",
                    bandwidth: 2_500_000,
                    url: "https://example.com/video/720p/init.mp4",
                    codecs: "avc1.64001f"
                )
            ],
            isLive: false,
            isDRMProtected: false,
            hasSubtitles: false,
            totalDuration: 3600,
            audioTracks: nil,
            minBufferTime: 2.0
        )
    }

    static func makeInfoWithQualities(_ qualities: [StreamQuality], duration: TimeInterval? = 3600) -> DASHParsedInfo {
        DASHParsedInfo(
            qualities: qualities,
            isLive: false,
            isDRMProtected: false,
            hasSubtitles: false,
            totalDuration: duration,
            audioTracks: nil,
            minBufferTime: 2.0
        )
    }

    static func makeDRMProtectedInfo() -> DASHParsedInfo {
        var info = makeDefaultInfo()
        info.isDRMProtected = true
        return info
    }

    static func makeLiveInfo() -> DASHParsedInfo {
        var info = makeDefaultInfo()
        info.isLive = true
        info.totalDuration = nil
        return info
    }

    static func makeInfoWithSubtitles() -> DASHParsedInfo {
        var info = makeDefaultInfo()
        info.hasSubtitles = true
        return info
    }

    static func makeInfoWithAudioTracks() -> DASHParsedInfo {
        var info = makeDefaultInfo()
        info.audioTracks = [
            DASHAudioTrack(id: UUID(), language: "en", label: "English", codecs: "mp4a.40.2", bandwidth: 128000),
            DASHAudioTrack(id: UUID(), language: "es", label: "Spanish", codecs: "mp4a.40.2", bandwidth: 128000)
        ]
        return info
    }

    // MARK: - Helpers

    func reset() {
        parseURLCalls.removeAll()
        parseManifestCalls.removeAll()
        parseURLHandler = nil
        parseManifestHandler = nil
    }
}
