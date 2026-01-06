import Foundation
@testable import OfflineBrowser

final class MockHLSParser: HLSParserProtocol {

    // MARK: - Tracking

    private(set) var parseURLCalls: [URL] = []
    private(set) var parseManifestCalls: [(content: String, baseURL: URL)] = []

    // MARK: - Configured Responses

    var parseResult: Result<HLSParsedInfo, HLSParser.ParseError> = .success(HLSParsedInfo(
        qualities: [],
        isLive: false,
        isDRMProtected: false,
        hasSubtitles: false,
        segments: nil,
        encryptionKeyURL: nil,
        totalDuration: nil
    ))

    // Handler for custom responses per URL
    var parseURLHandler: ((URL) -> Result<HLSParsedInfo, HLSParser.ParseError>)?
    var parseManifestHandler: ((String, URL) -> Result<HLSParsedInfo, HLSParser.ParseError>)?

    // MARK: - HLSParserProtocol

    func parse(url: URL, completion: @escaping (Result<HLSParsedInfo, HLSParser.ParseError>) -> Void) {
        parseURLCalls.append(url)

        let result: Result<HLSParsedInfo, HLSParser.ParseError>
        if let handler = parseURLHandler {
            result = handler(url)
        } else {
            result = parseResult
        }

        // Simulate async behavior
        DispatchQueue.main.async {
            completion(result)
        }
    }

    func parseManifest(content: String, baseURL: URL, completion: @escaping (Result<HLSParsedInfo, HLSParser.ParseError>) -> Void) {
        parseManifestCalls.append((content: content, baseURL: baseURL))

        let result: Result<HLSParsedInfo, HLSParser.ParseError>
        if let handler = parseManifestHandler {
            result = handler(content, baseURL)
        } else {
            result = parseResult
        }

        // Simulate async behavior
        DispatchQueue.main.async {
            completion(result)
        }
    }

    // MARK: - Helpers

    func reset() {
        parseURLCalls.removeAll()
        parseManifestCalls.removeAll()
        parseResult = .success(HLSParsedInfo(
            qualities: [],
            isLive: false,
            isDRMProtected: false,
            hasSubtitles: false,
            segments: nil,
            encryptionKeyURL: nil,
            totalDuration: nil
        ))
        parseURLHandler = nil
        parseManifestHandler = nil
    }

    // MARK: - Factory Methods for Common Responses

    static func makeMasterPlaylistInfo(qualities: [StreamQuality]) -> HLSParsedInfo {
        HLSParsedInfo(
            qualities: qualities,
            isLive: false,
            isDRMProtected: false,
            hasSubtitles: false,
            segments: nil,
            encryptionKeyURL: nil,
            totalDuration: nil
        )
    }

    static func makeMediaPlaylistInfo(
        segments: [HLSSegment],
        duration: TimeInterval? = nil,
        isLive: Bool = false,
        isFMP4: Bool = false,
        initSegmentURL: String? = nil
    ) -> HLSParsedInfo {
        HLSParsedInfo(
            qualities: [],
            isLive: isLive,
            isDRMProtected: false,
            hasSubtitles: false,
            segments: segments,
            encryptionKeyURL: nil,
            totalDuration: duration ?? segments.reduce(0) { $0 + $1.duration },
            initSegmentURL: initSegmentURL,
            isFMP4: isFMP4
        )
    }

    static func makeDRMProtectedInfo() -> HLSParsedInfo {
        HLSParsedInfo(
            qualities: [],
            isLive: false,
            isDRMProtected: true,
            hasSubtitles: false,
            segments: nil,
            encryptionKeyURL: nil,
            totalDuration: nil
        )
    }

    static func makeLiveStreamInfo() -> HLSParsedInfo {
        HLSParsedInfo(
            qualities: [],
            isLive: true,
            isDRMProtected: false,
            hasSubtitles: false,
            segments: nil,
            encryptionKeyURL: nil,
            totalDuration: nil
        )
    }
}
