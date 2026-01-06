import Foundation
@testable import OfflineBrowser

final class MockFFmpegMuxer: FFmpegMuxerProtocol {

    // MARK: - Tracking

    private(set) var muxCalls: [(directory: URL, outputURL: URL, encryptionKey: Data?, isFMP4: Bool)] = []

    // MARK: - Configured Responses

    var muxResult: Result<URL, Error> = .success(URL(fileURLWithPath: "/mock/output.mp4"))

    // Handler for custom responses
    var muxHandler: ((URL, URL, Data?, Bool) -> Result<URL, Error>)?

    // MARK: - Control

    var shouldCompleteAsync = true
    var asyncDelay: TimeInterval = 0.01

    // MARK: - FFmpegMuxerProtocol

    func muxHLSSegments(
        directory: URL,
        outputURL: URL,
        encryptionKey: Data?,
        isFMP4: Bool,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        muxCalls.append((directory: directory, outputURL: outputURL, encryptionKey: encryptionKey, isFMP4: isFMP4))

        let result: Result<URL, Error>
        if let handler = muxHandler {
            result = handler(directory, outputURL, encryptionKey, isFMP4)
        } else {
            result = muxResult
        }

        if shouldCompleteAsync {
            DispatchQueue.main.asyncAfter(deadline: .now() + asyncDelay) {
                completion(result)
            }
        } else {
            completion(result)
        }
    }

    // MARK: - Helpers

    func reset() {
        muxCalls.removeAll()
        muxResult = .success(URL(fileURLWithPath: "/mock/output.mp4"))
        muxHandler = nil
        shouldCompleteAsync = true
        asyncDelay = 0.01
    }

    // MARK: - Factory Methods for Common Responses

    static func makeSuccessResult(outputPath: String = "/mock/output.mp4") -> Result<URL, Error> {
        .success(URL(fileURLWithPath: outputPath))
    }

    static func makeFailureResult(message: String = "Muxing failed") -> Result<URL, Error> {
        .failure(FFmpegMuxer.MuxerError.muxingFailed(message))
    }

    static func makeNoSegmentsError() -> Result<URL, Error> {
        .failure(FFmpegMuxer.MuxerError.noSegments)
    }
}
