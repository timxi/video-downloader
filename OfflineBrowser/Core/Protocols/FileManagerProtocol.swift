import Foundation

protocol FileManagerProtocol {
    // MARK: - File Existence
    func fileExists(atPath path: String) -> Bool
    func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool

    // MARK: - Directory Operations
    func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]?
    ) throws

    func createDirectory(
        atPath path: String,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]?
    ) throws

    func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions
    ) throws -> [URL]

    func contentsOfDirectory(atPath path: String) throws -> [String]

    // MARK: - File Operations
    func moveItem(at srcURL: URL, to dstURL: URL) throws
    func moveItem(atPath srcPath: String, toPath dstPath: String) throws

    func copyItem(at srcURL: URL, to dstURL: URL) throws
    func copyItem(atPath srcPath: String, toPath dstPath: String) throws

    func removeItem(at URL: URL) throws
    func removeItem(atPath path: String) throws

    func createFile(atPath path: String, contents data: Data?, attributes attr: [FileAttributeKey: Any]?) -> Bool

    // MARK: - File Attributes
    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any]

    // MARK: - URL Access
    func urls(for directory: FileManager.SearchPathDirectory, in domainMask: FileManager.SearchPathDomainMask) -> [URL]

    // MARK: - Enumeration
    func enumerator(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions,
        errorHandler handler: ((URL, Error) -> Bool)?
    ) -> FileManager.DirectoryEnumerator?
}

// MARK: - Default Implementation

extension FileManagerProtocol {
    func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool
    ) throws {
        try createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: nil)
    }

    func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?) throws -> [URL] {
        try contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [])
    }

    func enumerator(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions
    ) -> FileManager.DirectoryEnumerator? {
        enumerator(at: url, includingPropertiesForKeys: keys, options: mask, errorHandler: nil)
    }
}

// MARK: - FileManager Conformance

extension FileManager: FileManagerProtocol {}
