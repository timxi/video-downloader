import Foundation

protocol HLSParserProtocol {
    func parse(url: URL, completion: @escaping (Result<HLSParsedInfo, HLSParser.ParseError>) -> Void)
    func parseManifest(content: String, baseURL: URL, completion: @escaping (Result<HLSParsedInfo, HLSParser.ParseError>) -> Void)
}

// MARK: - HLSParser Conformance

extension HLSParser: HLSParserProtocol {}
