import Foundation
@testable import OfflineBrowser

// MARK: - Mock Data Task

final class MockURLSessionDataTask: URLSessionDataTaskProtocol {
    private let onResume: () -> Void
    var cancelCalled = false

    init(onResume: @escaping () -> Void = {}) {
        self.onResume = onResume
    }

    func resume() {
        onResume()
    }

    func cancel() {
        cancelCalled = true
    }
}

// MARK: - Mock Download Task

final class MockURLSessionDownloadTask: URLSessionDownloadTaskProtocol {
    private let onResume: () -> Void
    var cancelCalled = false

    init(onResume: @escaping () -> Void = {}) {
        self.onResume = onResume
    }

    func resume() {
        onResume()
    }

    func cancel() {
        cancelCalled = true
    }
}

// MARK: - Mock URL Session

final class MockURLSession: URLSessionProtocol {

    // MARK: - Recorded Requests

    private(set) var dataRequests: [URLRequest] = []
    private(set) var downloadRequests: [URLRequest] = []

    // MARK: - Configured Responses

    var dataResponse: (Data?, URLResponse?, Error?) = (nil, nil, nil)
    var downloadResponse: (URL?, URLResponse?, Error?) = (nil, nil, nil)

    // Can be set to provide custom responses per URL
    var dataResponseHandler: ((URLRequest) -> (Data?, URLResponse?, Error?))?
    var downloadResponseHandler: ((URLRequest) -> (URL?, URLResponse?, Error?))?

    // MARK: - Control

    var shouldCompleteImmediately = true

    // MARK: - URLSessionProtocol

    func data(
        with request: URLRequest,
        completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void
    ) -> URLSessionDataTaskProtocol {
        dataRequests.append(request)

        let task = MockURLSessionDataTask { [weak self] in
            guard let self = self, self.shouldCompleteImmediately else { return }

            let response: (Data?, URLResponse?, Error?)
            if let handler = self.dataResponseHandler {
                response = handler(request)
            } else {
                response = self.dataResponse
            }

            completionHandler(response.0, response.1, response.2)
        }

        return task
    }

    func data(
        with url: URL,
        completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void
    ) -> URLSessionDataTaskProtocol {
        let request = URLRequest(url: url)
        return data(with: request, completionHandler: completionHandler)
    }

    func download(
        with request: URLRequest,
        completionHandler: @escaping (URL?, URLResponse?, Error?) -> Void
    ) -> URLSessionDownloadTaskProtocol {
        downloadRequests.append(request)

        let task = MockURLSessionDownloadTask { [weak self] in
            guard let self = self, self.shouldCompleteImmediately else { return }

            let response: (URL?, URLResponse?, Error?)
            if let handler = self.downloadResponseHandler {
                response = handler(request)
            } else {
                response = self.downloadResponse
            }

            completionHandler(response.0, response.1, response.2)
        }

        return task
    }

    func download(
        with url: URL,
        completionHandler: @escaping (URL?, URLResponse?, Error?) -> Void
    ) -> URLSessionDownloadTaskProtocol {
        let request = URLRequest(url: url)
        return download(with: request, completionHandler: completionHandler)
    }

    // MARK: - Helpers

    func reset() {
        dataRequests.removeAll()
        downloadRequests.removeAll()
        dataResponse = (nil, nil, nil)
        downloadResponse = (nil, nil, nil)
        dataResponseHandler = nil
        downloadResponseHandler = nil
        shouldCompleteImmediately = true
    }

    func makeSuccessResponse(for url: URL, statusCode: Int = 200) -> URLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
    }
}
