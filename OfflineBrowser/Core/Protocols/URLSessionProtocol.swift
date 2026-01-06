import Foundation

// MARK: - URLSession Task Protocols

protocol URLSessionDataTaskProtocol {
    func resume()
    func cancel()
}

protocol URLSessionDownloadTaskProtocol {
    func resume()
    func cancel()
}

// MARK: - URLSession Protocol

protocol URLSessionProtocol {
    func data(
        with request: URLRequest,
        completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void
    ) -> URLSessionDataTaskProtocol

    func data(
        with url: URL,
        completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void
    ) -> URLSessionDataTaskProtocol

    func download(
        with request: URLRequest,
        completionHandler: @escaping (URL?, URLResponse?, Error?) -> Void
    ) -> URLSessionDownloadTaskProtocol

    func download(
        with url: URL,
        completionHandler: @escaping (URL?, URLResponse?, Error?) -> Void
    ) -> URLSessionDownloadTaskProtocol
}

// MARK: - URLSession Conformance

extension URLSessionDataTask: URLSessionDataTaskProtocol {}
extension URLSessionDownloadTask: URLSessionDownloadTaskProtocol {}

extension URLSession: URLSessionProtocol {
    func data(
        with request: URLRequest,
        completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void
    ) -> URLSessionDataTaskProtocol {
        dataTask(with: request, completionHandler: completionHandler)
    }

    func data(
        with url: URL,
        completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void
    ) -> URLSessionDataTaskProtocol {
        dataTask(with: url, completionHandler: completionHandler)
    }

    func download(
        with request: URLRequest,
        completionHandler: @escaping (URL?, URLResponse?, Error?) -> Void
    ) -> URLSessionDownloadTaskProtocol {
        downloadTask(with: request, completionHandler: completionHandler)
    }

    func download(
        with url: URL,
        completionHandler: @escaping (URL?, URLResponse?, Error?) -> Void
    ) -> URLSessionDownloadTaskProtocol {
        downloadTask(with: url, completionHandler: completionHandler)
    }
}
