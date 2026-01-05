import Foundation

final class BackgroundSessionManager: NSObject {
    static let shared = BackgroundSessionManager()

    private let sessionIdentifier = "com.offlinebrowser.background"
    private var backgroundSession: URLSession!
    private var completionHandlers: [String: (URL?, URLResponse?, Error?) -> Void] = [:]

    private override init() {
        super.init()
        setupSession()
    }

    private func setupSession() {
        let config = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.allowsCellularAccess = PreferenceRepository.shared.allowCellularDownload

        backgroundSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    // MARK: - Public Methods

    func download(url: URL, completion: @escaping (URL?, URLResponse?, Error?) -> Void) -> URLSessionDownloadTask {
        let task = backgroundSession.downloadTask(with: url)
        completionHandlers["\(task.taskIdentifier)"] = completion
        task.resume()
        return task
    }

    func downloadWithCookies(url: URL, cookies: [HTTPCookie], completion: @escaping (URL?, URLResponse?, Error?) -> Void) -> URLSessionDownloadTask {
        var request = URLRequest(url: url)

        let cookieHeaders = HTTPCookie.requestHeaderFields(with: cookies)
        for (key, value) in cookieHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let task = backgroundSession.downloadTask(with: request)
        completionHandlers["\(task.taskIdentifier)"] = completion
        task.resume()
        return task
    }

    func handleBackgroundSessionEvents(identifier: String) {
        if identifier == sessionIdentifier {
            // Session events will be delivered through delegate methods
        }
    }

    func updateCellularAccess() {
        backgroundSession.configuration.allowsCellularAccess = PreferenceRepository.shared.allowCellularDownload
    }
}

// MARK: - URLSessionDownloadDelegate

extension BackgroundSessionManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let key = "\(downloadTask.taskIdentifier)"
        if let completion = completionHandlers[key] {
            completion(location, downloadTask.response, nil)
            completionHandlers.removeValue(forKey: key)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let key = "\(task.taskIdentifier)"
        if let error = error, let completion = completionHandlers[key] {
            completion(nil, task.response, error)
            completionHandlers.removeValue(forKey: key)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        // Progress tracking - can be used for UI updates
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        NotificationCenter.default.post(
            name: .downloadProgressUpdated,
            object: nil,
            userInfo: [
                "taskIdentifier": downloadTask.taskIdentifier,
                "progress": progress,
                "bytesWritten": totalBytesWritten,
                "totalBytes": totalBytesExpectedToWrite
            ]
        )
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            if let appDelegate = UIApplication.shared.delegate as? AppDelegate,
               let completionHandler = appDelegate.backgroundSessionCompletionHandler {
                appDelegate.backgroundSessionCompletionHandler = nil
                completionHandler()
            }
        }
    }
}

// MARK: - URLSessionDelegate

extension BackgroundSessionManager: URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didBecomeInvalidWithError error: Error?
    ) {
        if let error = error {
            print("Session became invalid with error: \(error)")
        }
        setupSession()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let downloadProgressUpdated = Notification.Name("downloadProgressUpdated")
}

import UIKit
