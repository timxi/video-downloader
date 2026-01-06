import Foundation

protocol FFmpegMuxerProtocol {
    func muxHLSSegments(
        directory: URL,
        outputURL: URL,
        encryptionKey: Data?,
        isFMP4: Bool,
        completion: @escaping (Result<URL, Error>) -> Void
    )
}

// MARK: - Default Parameter Values

extension FFmpegMuxerProtocol {
    func muxHLSSegments(
        directory: URL,
        outputURL: URL,
        encryptionKey: Data?,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        muxHLSSegments(directory: directory, outputURL: outputURL, encryptionKey: encryptionKey, isFMP4: false, completion: completion)
    }
}

// MARK: - FFmpegMuxer Conformance

extension FFmpegMuxer: FFmpegMuxerProtocol {}
