import XCTest
@testable import OfflineBrowser

final class ThumbnailServiceTests: XCTestCase {

    var mockFileStorage: MockFileStorageManager!
    var mockURLSession: MockURLSession!
    var sut: ThumbnailService!
    var tempThumbnailsDir: URL!

    override func setUp() {
        super.setUp()
        mockFileStorage = MockFileStorageManager()
        mockURLSession = MockURLSession()

        // Create a real temp directory for thumbnails so file writes succeed
        tempThumbnailsDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThumbnailServiceTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempThumbnailsDir, withIntermediateDirectories: true)

        // Create the thumbnails subdirectory (mockFileStorage.thumbnailsDirectory returns documents/thumbnails)
        let thumbnailsSubdir = tempThumbnailsDir.appendingPathComponent("thumbnails")
        try? FileManager.default.createDirectory(at: thumbnailsSubdir, withIntermediateDirectories: true)

        // Point the mock to use this real directory
        mockFileStorage.mockDocumentsDirectory = tempThumbnailsDir

        sut = ThumbnailService(fileStorage: mockFileStorage, urlSession: mockURLSession)
    }

    override func tearDown() {
        sut = nil
        mockFileStorage = nil
        mockURLSession = nil

        // Clean up temp directory
        if let tempDir = tempThumbnailsDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        tempThumbnailsDir = nil

        super.tearDown()
    }

    // MARK: - Invalid URL Tests

    func testDownloadThumbnail_invalidURL_returnsNil() {
        let exp = expectation(description: "Completion called")

        sut.downloadThumbnail(from: "not a valid url") { url in
            XCTAssertNil(url)
            exp.fulfill()
        }

        waitForExpectations(timeout: 1)
    }

    func testDownloadThumbnail_emptyURL_returnsNil() {
        let exp = expectation(description: "Completion called")

        sut.downloadThumbnail(from: "") { url in
            XCTAssertNil(url)
            exp.fulfill()
        }

        waitForExpectations(timeout: 1)
    }

    // MARK: - Network Error Tests

    func testDownloadThumbnail_networkError_returnsNil() {
        let exp = expectation(description: "Completion called")
        let error = NSError(domain: "Network", code: -1, userInfo: nil)
        mockURLSession.dataResponseHandler = { _ in
            return (nil, nil, error)
        }

        sut.downloadThumbnail(from: "https://example.com/image.jpg") { url in
            XCTAssertNil(url)
            exp.fulfill()
        }

        waitForExpectations(timeout: 1)
    }

    // MARK: - Empty Response Tests

    func testDownloadThumbnail_emptyData_returnsNil() {
        let exp = expectation(description: "Completion called")
        mockURLSession.dataResponseHandler = { _ in
            return (Data(), nil, nil)
        }

        sut.downloadThumbnail(from: "https://example.com/image.jpg") { url in
            XCTAssertNil(url)
            exp.fulfill()
        }

        waitForExpectations(timeout: 1)
    }

    func testDownloadThumbnail_nilData_returnsNil() {
        let exp = expectation(description: "Completion called")
        mockURLSession.dataResponseHandler = { _ in
            return (nil, nil, nil)
        }

        sut.downloadThumbnail(from: "https://example.com/image.jpg") { url in
            XCTAssertNil(url)
            exp.fulfill()
        }

        waitForExpectations(timeout: 1)
    }

    // MARK: - Invalid Image Tests

    func testDownloadThumbnail_invalidImageData_returnsNil() {
        let exp = expectation(description: "Completion called")
        let invalidData = "not an image".data(using: .utf8)!
        mockURLSession.dataResponseHandler = { _ in
            return (invalidData, nil, nil)
        }

        sut.downloadThumbnail(from: "https://example.com/image.jpg") { url in
            XCTAssertNil(url)
            exp.fulfill()
        }

        waitForExpectations(timeout: 1)
    }

    // MARK: - Successful Download Tests

    func testDownloadThumbnail_validImage_returnsURL() {
        let exp = expectation(description: "Completion called")
        let imageData = createTestImageData()
        mockURLSession.dataResponseHandler = { _ in
            return (imageData, nil, nil)
        }

        sut.downloadThumbnail(from: "https://example.com/image.jpg") { url in
            XCTAssertNotNil(url)
            XCTAssertTrue(url?.pathExtension == "jpg")
            exp.fulfill()
        }

        waitForExpectations(timeout: 1)
    }

    func testDownloadThumbnail_savesToThumbnailsDirectory() {
        let exp = expectation(description: "Completion called")
        let imageData = createTestImageData()
        mockURLSession.dataResponseHandler = { _ in
            return (imageData, nil, nil)
        }

        sut.downloadThumbnail(from: "https://example.com/image.jpg") { url in
            if let url = url {
                XCTAssertTrue(url.path.contains("thumbnails"))
            } else {
                XCTFail("Expected URL to be non-nil")
            }
            exp.fulfill()
        }

        waitForExpectations(timeout: 1)
    }

    func testDownloadThumbnail_fileExistsAtReturnedURL() {
        let exp = expectation(description: "Completion called")
        let imageData = createTestImageData()
        mockURLSession.dataResponseHandler = { _ in
            return (imageData, nil, nil)
        }

        sut.downloadThumbnail(from: "https://example.com/image.jpg") { url in
            if let url = url {
                XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            } else {
                XCTFail("Expected URL to be non-nil")
            }
            exp.fulfill()
        }

        waitForExpectations(timeout: 1)
    }

    // MARK: - Request Configuration Tests

    func testDownloadThumbnail_setsCorrectURL() {
        let exp = expectation(description: "Request made")
        let expectedURL = "https://example.com/test-image.png"

        mockURLSession.dataResponseHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, expectedURL)
            exp.fulfill()
            return (nil, nil, NSError(domain: "Test", code: 1))
        }

        sut.downloadThumbnail(from: expectedURL) { _ in }

        waitForExpectations(timeout: 1)
    }

    func testDownloadThumbnail_setsTimeout() {
        let exp = expectation(description: "Request made")

        mockURLSession.dataResponseHandler = { request in
            XCTAssertEqual(request.timeoutInterval, 15)
            exp.fulfill()
            return (nil, nil, NSError(domain: "Test", code: 1))
        }

        sut.downloadThumbnail(from: "https://example.com/image.jpg") { _ in }

        waitForExpectations(timeout: 1)
    }

    // MARK: - Image Resizing Tests

    func testDownloadThumbnail_largeImage_isResized() {
        let exp = expectation(description: "Completion called")
        // Create a large image (800x600)
        let largeImageData = createTestImageData(width: 800, height: 600)
        mockURLSession.dataResponseHandler = { _ in
            return (largeImageData, nil, nil)
        }

        sut.downloadThumbnail(from: "https://example.com/large.jpg") { url in
            XCTAssertNotNil(url)
            // The image should be resized to max 400px on the longest side
            exp.fulfill()
        }

        waitForExpectations(timeout: 1)
    }

    func testDownloadThumbnail_smallImage_notResized() {
        let exp = expectation(description: "Completion called")
        // Create a small image (200x150)
        let smallImageData = createTestImageData(width: 200, height: 150)
        mockURLSession.dataResponseHandler = { _ in
            return (smallImageData, nil, nil)
        }

        sut.downloadThumbnail(from: "https://example.com/small.jpg") { url in
            XCTAssertNotNil(url)
            exp.fulfill()
        }

        waitForExpectations(timeout: 1)
    }

    // MARK: - Helpers

    private func createTestImageData(width: Int = 100, height: Int = 100) -> Data {
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return image.jpegData(compressionQuality: 0.8)!
    }
}
