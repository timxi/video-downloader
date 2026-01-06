import Foundation
@testable import OfflineBrowser

final class MockFileManager: FileManagerProtocol {

    // MARK: - Tracking

    private(set) var createdDirectories: [URL] = []
    private(set) var removedItems: [URL] = []
    private(set) var movedItems: [(from: URL, to: URL)] = []
    private(set) var copiedItems: [(from: URL, to: URL)] = []
    private(set) var createdFiles: [(path: String, data: Data?)] = []

    // MARK: - Configurable State

    var existingPaths: Set<String> = []
    var directoryPaths: Set<String> = []
    var fileAttributes: [String: [FileAttributeKey: Any]] = [:]
    var directoryContents: [URL: [URL]] = [:]
    var documentsURL: URL = URL(fileURLWithPath: "/mock/documents")

    // MARK: - Error Simulation

    var shouldThrowOnCreateDirectory = false
    var shouldThrowOnMove = false
    var shouldThrowOnCopy = false
    var shouldThrowOnRemove = false

    // MARK: - File Existence

    func fileExists(atPath path: String) -> Bool {
        existingPaths.contains(path)
    }

    func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        let exists = existingPaths.contains(path)
        if let isDirectory = isDirectory {
            isDirectory.pointee = ObjCBool(directoryPaths.contains(path))
        }
        return exists
    }

    // MARK: - Directory Operations

    func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]?
    ) throws {
        if shouldThrowOnCreateDirectory {
            throw NSError(domain: "MockFileManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create directory"])
        }
        createdDirectories.append(url)
        existingPaths.insert(url.path)
        directoryPaths.insert(url.path)
    }

    func createDirectory(
        atPath path: String,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]?
    ) throws {
        try createDirectory(at: URL(fileURLWithPath: path), withIntermediateDirectories: createIntermediates, attributes: attributes)
    }

    func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions
    ) throws -> [URL] {
        directoryContents[url] ?? []
    }

    func contentsOfDirectory(atPath path: String) throws -> [String] {
        let url = URL(fileURLWithPath: path)
        return (directoryContents[url] ?? []).map { $0.lastPathComponent }
    }

    // MARK: - File Operations

    func moveItem(at srcURL: URL, to dstURL: URL) throws {
        if shouldThrowOnMove {
            throw NSError(domain: "MockFileManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to move item"])
        }
        movedItems.append((from: srcURL, to: dstURL))
        existingPaths.remove(srcURL.path)
        existingPaths.insert(dstURL.path)
    }

    func moveItem(atPath srcPath: String, toPath dstPath: String) throws {
        try moveItem(at: URL(fileURLWithPath: srcPath), to: URL(fileURLWithPath: dstPath))
    }

    func copyItem(at srcURL: URL, to dstURL: URL) throws {
        if shouldThrowOnCopy {
            throw NSError(domain: "MockFileManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to copy item"])
        }
        copiedItems.append((from: srcURL, to: dstURL))
        existingPaths.insert(dstURL.path)
    }

    func copyItem(atPath srcPath: String, toPath dstPath: String) throws {
        try copyItem(at: URL(fileURLWithPath: srcPath), to: URL(fileURLWithPath: dstPath))
    }

    func removeItem(at URL: URL) throws {
        if shouldThrowOnRemove {
            throw NSError(domain: "MockFileManager", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to remove item"])
        }
        removedItems.append(URL)
        existingPaths.remove(URL.path)
        directoryPaths.remove(URL.path)
    }

    func removeItem(atPath path: String) throws {
        try removeItem(at: URL(fileURLWithPath: path))
    }

    func createFile(atPath path: String, contents data: Data?, attributes attr: [FileAttributeKey: Any]?) -> Bool {
        createdFiles.append((path: path, data: data))
        existingPaths.insert(path)
        return true
    }

    // MARK: - File Attributes

    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        if let attributes = fileAttributes[path] {
            return attributes
        }
        throw NSError(domain: "MockFileManager", code: 5, userInfo: [NSLocalizedDescriptionKey: "No such file"])
    }

    // MARK: - URL Access

    func urls(for directory: FileManager.SearchPathDirectory, in domainMask: FileManager.SearchPathDomainMask) -> [URL] {
        [documentsURL]
    }

    // MARK: - Enumeration

    func enumerator(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions,
        errorHandler handler: ((URL, Error) -> Bool)?
    ) -> FileManager.DirectoryEnumerator? {
        // Return nil for mock - specific tests can override this behavior
        nil
    }

    // MARK: - Helpers

    func reset() {
        createdDirectories.removeAll()
        removedItems.removeAll()
        movedItems.removeAll()
        copiedItems.removeAll()
        createdFiles.removeAll()
        existingPaths.removeAll()
        directoryPaths.removeAll()
        fileAttributes.removeAll()
        directoryContents.removeAll()
        shouldThrowOnCreateDirectory = false
        shouldThrowOnMove = false
        shouldThrowOnCopy = false
        shouldThrowOnRemove = false
    }

    func addExistingFile(at path: String, size: Int64 = 0) {
        existingPaths.insert(path)
        fileAttributes[path] = [.size: size]
    }

    func addExistingDirectory(at path: String) {
        existingPaths.insert(path)
        directoryPaths.insert(path)
    }
}
