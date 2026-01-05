import Foundation
import AVFoundation
import ffmpegkit

final class FFmpegMuxer {
    static let shared = FFmpegMuxer()

    private init() {}

    enum MuxerError: Error, LocalizedError {
        case noSegments
        case muxingFailed(String)
        case outputNotCreated
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .noSegments: return "No segments found"
            case .muxingFailed(let msg): return "Muxing failed: \(msg)"
            case .outputNotCreated: return "Output file not created"
            case .exportFailed(let msg): return "Export failed: \(msg)"
            }
        }
    }

    // MARK: - Public Methods

    func muxHLSSegments(
        directory: URL,
        outputURL: URL,
        encryptionKey: Data?,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let result = try self?.performMuxing(
                    directory: directory,
                    outputURL: outputURL,
                    encryptionKey: encryptionKey
                )

                guard let finalURL = result else {
                    DispatchQueue.main.async {
                        completion(.failure(MuxerError.outputNotCreated))
                    }
                    return
                }

                DispatchQueue.main.async {
                    completion(.success(finalURL))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - Private Methods

    private func performMuxing(
        directory: URL,
        outputURL: URL,
        encryptionKey: Data?
    ) throws -> URL {
        let fileManager = FileManager.default

        NSLog("[FFmpegMuxer] Looking for segments in: %@", directory.path)

        // Get all segment files sorted by index number
        let segmentFiles = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
            .filter { $0.pathExtension == "ts" }
            .sorted { file1, file2 in
                let num1 = extractSegmentNumber(from: file1.lastPathComponent)
                let num2 = extractSegmentNumber(from: file2.lastPathComponent)
                return num1 < num2
            }

        NSLog("[FFmpegMuxer] Found %d segment files", segmentFiles.count)

        guard !segmentFiles.isEmpty else {
            throw MuxerError.noSegments
        }

        // Log segment info
        var totalSize: Int64 = 0
        for (index, file) in segmentFiles.enumerated() {
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            totalSize += Int64(size)
            if index < 3 || index == segmentFiles.count - 1 {
                NSLog("[FFmpegMuxer] Segment %d: %@ - %d bytes", index, file.lastPathComponent, size)
            }
        }
        NSLog("[FFmpegMuxer] Total segments size: %lld bytes (%.2f MB)", totalSize, Double(totalSize) / 1_000_000)

        // Create concat file for FFmpeg
        let concatListURL = directory.appendingPathComponent("concat.txt")
        let concatContent = segmentFiles.map { "file '\($0.path)'" }.joined(separator: "\n")
        try concatContent.write(to: concatListURL, atomically: true, encoding: .utf8)

        NSLog("[FFmpegMuxer] Created concat file at: %@", concatListURL.path)

        // Output MP4 file
        let mp4OutputURL = outputURL.deletingPathExtension().appendingPathExtension("mp4")

        // Remove output file if exists
        if fileManager.fileExists(atPath: mp4OutputURL.path) {
            try fileManager.removeItem(at: mp4OutputURL)
        }

        // Build FFmpeg command
        // -f concat: use concat demuxer
        // -safe 0: allow absolute paths
        // -i: input concat file
        // -c copy: copy streams without re-encoding (fast)
        // -bsf:a aac_adtstoasc: convert AAC from ADTS to ASC format for MP4 container
        let command = "-f concat -safe 0 -i \"\(concatListURL.path)\" -c copy -bsf:a aac_adtstoasc \"\(mp4OutputURL.path)\""

        NSLog("[FFmpegMuxer] Executing FFmpeg command: %@", command)

        // Execute FFmpeg command synchronously
        let session = FFmpegKit.execute(command)

        let returnCode = session?.getReturnCode()
        let state = session?.getState()

        NSLog("[FFmpegMuxer] FFmpeg state: %d, return code: %d", state?.rawValue ?? -1, returnCode?.getValue() ?? -1)

        // Clean up concat file
        try? fileManager.removeItem(at: concatListURL)

        if ReturnCode.isSuccess(returnCode) {
            // Verify output file exists
            guard fileManager.fileExists(atPath: mp4OutputURL.path) else {
                NSLog("[FFmpegMuxer] ERROR: Output file not created")
                throw MuxerError.outputNotCreated
            }

            let outputSize = (try? fileManager.attributesOfItem(atPath: mp4OutputURL.path)[.size] as? Int64) ?? 0
            NSLog("[FFmpegMuxer] FFmpeg muxing succeeded - output size: %lld bytes", outputSize)

            return mp4OutputURL
        } else {
            // Log FFmpeg output for debugging
            if let logs = session?.getAllLogsAsString() {
                let logSuffix = String(logs.suffix(500))
                NSLog("[FFmpegMuxer] FFmpeg logs: %@", logSuffix)
            }

            NSLog("[FFmpegMuxer] FFmpeg muxing failed, trying fallback...")

            // Fallback to simple TS concatenation
            let tsOutputURL = outputURL.deletingPathExtension().appendingPathExtension("ts")
            try concatenateSegments(files: segmentFiles, outputURL: tsOutputURL)

            return tsOutputURL
        }
    }

    private func concatenateSegments(files: [URL], outputURL: URL) throws {
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }

        fileManager.createFile(atPath: outputURL.path, contents: nil)
        let writeHandle = try FileHandle(forWritingTo: outputURL)
        defer { try? writeHandle.close() }

        for (index, file) in files.enumerated() {
            autoreleasepool {
                do {
                    let data = try Data(contentsOf: file, options: .mappedIfSafe)
                    writeHandle.write(data)
                    if index % 50 == 0 {
                        NSLog("[FFmpegMuxer] Concatenated %d/%d segments", index + 1, files.count)
                    }
                } catch {
                    NSLog("[FFmpegMuxer] Error reading segment %d: %@", index, error.localizedDescription)
                }
            }
        }

        NSLog("[FFmpegMuxer] Finished concatenating %d segments", files.count)
    }

    private func extractSegmentNumber(from filename: String) -> Int {
        let pattern = "_(\\d+)\\.ts$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: filename, options: [], range: NSRange(filename.startIndex..., in: filename)),
              let range = Range(match.range(at: 1), in: filename) else {
            return 0
        }
        return Int(filename[range]) ?? 0
    }
}
