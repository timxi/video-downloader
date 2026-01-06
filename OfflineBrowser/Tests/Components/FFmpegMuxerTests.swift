import XCTest
@testable import OfflineBrowser

final class FFmpegMuxerTests: XCTestCase {

    // Note: FFmpegMuxer uses FFmpegKit which is difficult to mock.
    // These tests focus on the pure functions that can be tested without FFmpegKit.
    // Integration tests with actual muxing would require real files.

    var sut: FFmpegMuxer!

    override func setUp() {
        super.setUp()
        sut = FFmpegMuxer.shared
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Segment Number Extraction Tests

    // Note: extractSegmentNumber is private, so we test it indirectly through file ordering
    // or expose it for testing. For now, we test the error cases.

    // MARK: - Muxer Error Description Tests

    func testMuxerError_noSegments_hasDescription() {
        let error = FFmpegMuxer.MuxerError.noSegments
        XCTAssertEqual(error.errorDescription, "No segments found")
    }

    func testMuxerError_muxingFailed_includesMessage() {
        let error = FFmpegMuxer.MuxerError.muxingFailed("FFmpeg exit code -1")
        XCTAssertEqual(error.errorDescription, "Muxing failed: FFmpeg exit code -1")
    }

    func testMuxerError_outputNotCreated_hasDescription() {
        let error = FFmpegMuxer.MuxerError.outputNotCreated
        XCTAssertEqual(error.errorDescription, "Output file not created")
    }

    func testMuxerError_exportFailed_includesMessage() {
        let error = FFmpegMuxer.MuxerError.exportFailed("AVAssetExportSession failed")
        XCTAssertEqual(error.errorDescription, "Export failed: AVAssetExportSession failed")
    }

    // MARK: - Protocol Conformance Tests

    func testShared_conformsToFFmpegMuxerProtocol() {
        let muxer: FFmpegMuxerProtocol = FFmpegMuxer.shared
        XCTAssertNotNil(muxer)
    }

    // MARK: - Mock Muxer Tests

    func testMockMuxer_recordsCalls() {
        let mockMuxer = MockFFmpegMuxer()
        let directory = URL(fileURLWithPath: "/segments")
        let output = URL(fileURLWithPath: "/output.mp4")
        let expectation = expectation(description: "Mux completes")

        mockMuxer.muxHLSSegments(
            directory: directory,
            outputURL: output,
            encryptionKey: nil,
            isFMP4: true
        ) { _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(mockMuxer.muxCalls.count, 1)
        XCTAssertEqual(mockMuxer.muxCalls.first?.directory, directory)
        XCTAssertEqual(mockMuxer.muxCalls.first?.outputURL, output)
        XCTAssertTrue(mockMuxer.muxCalls.first?.isFMP4 ?? false)
    }

    func testMockMuxer_returnsConfiguredResult() {
        let mockMuxer = MockFFmpegMuxer()
        let expectedURL = URL(fileURLWithPath: "/custom/output.mp4")
        mockMuxer.muxResult = .success(expectedURL)
        let expectation = expectation(description: "Mux completes")

        var resultURL: URL?
        mockMuxer.muxHLSSegments(
            directory: URL(fileURLWithPath: "/segments"),
            outputURL: URL(fileURLWithPath: "/output.mp4"),
            encryptionKey: nil,
            isFMP4: false
        ) { result in
            if case .success(let url) = result {
                resultURL = url
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(resultURL, expectedURL)
    }

    func testMockMuxer_returnsConfiguredError() {
        let mockMuxer = MockFFmpegMuxer()
        mockMuxer.muxResult = MockFFmpegMuxer.makeNoSegmentsError()
        let expectation = expectation(description: "Mux completes")

        var resultError: Error?
        mockMuxer.muxHLSSegments(
            directory: URL(fileURLWithPath: "/segments"),
            outputURL: URL(fileURLWithPath: "/output.mp4"),
            encryptionKey: nil,
            isFMP4: false
        ) { result in
            if case .failure(let error) = result {
                resultError = error
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        XCTAssertNotNil(resultError)
        XCTAssertTrue(resultError is FFmpegMuxer.MuxerError)
    }

    func testMockMuxer_usesCustomHandler() {
        let mockMuxer = MockFFmpegMuxer()
        let customURL = URL(fileURLWithPath: "/handler/output.mp4")
        mockMuxer.muxHandler = { _, _, _, isFMP4 in
            if isFMP4 {
                return .success(customURL)
            } else {
                return .failure(FFmpegMuxer.MuxerError.noSegments)
            }
        }

        let expectation1 = expectation(description: "Mux fMP4 completes")
        let expectation2 = expectation(description: "Mux TS completes")

        var fmp4URL: URL?
        var tsError: Error?

        mockMuxer.muxHLSSegments(
            directory: URL(fileURLWithPath: "/segments"),
            outputURL: URL(fileURLWithPath: "/output.mp4"),
            encryptionKey: nil,
            isFMP4: true
        ) { result in
            if case .success(let url) = result {
                fmp4URL = url
            }
            expectation1.fulfill()
        }

        mockMuxer.muxHLSSegments(
            directory: URL(fileURLWithPath: "/segments"),
            outputURL: URL(fileURLWithPath: "/output.mp4"),
            encryptionKey: nil,
            isFMP4: false
        ) { result in
            if case .failure(let error) = result {
                tsError = error
            }
            expectation2.fulfill()
        }

        wait(for: [expectation1, expectation2], timeout: 1.0)

        XCTAssertEqual(fmp4URL, customURL)
        XCTAssertNotNil(tsError)
    }

    // MARK: - Factory Method Tests

    func testMakeSuccessResult_createsSuccessWithPath() {
        let result = MockFFmpegMuxer.makeSuccessResult(outputPath: "/test/video.mp4")

        switch result {
        case .success(let url):
            XCTAssertEqual(url.path, "/test/video.mp4")
        case .failure:
            XCTFail("Should be success")
        }
    }

    func testMakeFailureResult_createsFailureWithMessage() {
        let result = MockFFmpegMuxer.makeFailureResult(message: "Test error")

        switch result {
        case .success:
            XCTFail("Should be failure")
        case .failure(let error):
            XCTAssertTrue(error.localizedDescription.contains("Test error"))
        }
    }

    func testMakeNoSegmentsError_createsNoSegmentsError() {
        let result = MockFFmpegMuxer.makeNoSegmentsError()

        switch result {
        case .success:
            XCTFail("Should be failure")
        case .failure(let error):
            if let muxerError = error as? FFmpegMuxer.MuxerError {
                XCTAssertEqual(muxerError.errorDescription, "No segments found")
            } else {
                XCTFail("Should be MuxerError")
            }
        }
    }
}
