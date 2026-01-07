import Foundation

protocol DASHParserProtocol {
    func parse(url: URL, completion: @escaping (Result<DASHParsedInfo, DASHParser.ParseError>) -> Void)
    func parseManifest(content: String, baseURL: URL, completion: @escaping (Result<DASHParsedInfo, DASHParser.ParseError>) -> Void)
}

extension DASHParser: DASHParserProtocol {}
