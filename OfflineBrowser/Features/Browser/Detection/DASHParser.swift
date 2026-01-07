import Foundation
import os.log

private let dashLogger = Logger(subsystem: "com.offlinebrowser", category: "DASHParser")

// MARK: - Parsed Info

struct DASHParsedInfo {
    var qualities: [StreamQuality]
    var isLive: Bool
    var isDRMProtected: Bool
    var hasSubtitles: Bool
    var totalDuration: TimeInterval?
    var audioTracks: [DASHAudioTrack]?
    var minBufferTime: TimeInterval?
}

struct DASHAudioTrack: Identifiable, Equatable {
    let id: UUID
    let language: String?
    let label: String?
    let codecs: String?
    let bandwidth: Int
}

// MARK: - DASHParser

final class DASHParser {

    enum ParseError: Error {
        case invalidURL
        case networkError(Error)
        case invalidManifest
        case noContent
        case xmlParsingError(Error)
    }

    private let urlSession: URLSessionProtocol

    init(urlSession: URLSessionProtocol = URLSession.shared) {
        self.urlSession = urlSession
    }

    // MARK: - Public Methods

    func parse(url: URL, completion: @escaping (Result<DASHParsedInfo, ParseError>) -> Void) {
        dashLogger.debug("Parsing DASH manifest: \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        // Add cookies
        if let cookies = HTTPCookieStorage.shared.cookies(for: url) {
            let headers = HTTPCookie.requestHeaderFields(with: cookies)
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        let task = urlSession.data(with: request) { [weak self] data, response, error in
            if let error = error {
                dashLogger.error("Network error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(.failure(.networkError(error)))
                }
                return
            }

            guard let data = data, !data.isEmpty else {
                dashLogger.error("No content received")
                DispatchQueue.main.async {
                    completion(.failure(.noContent))
                }
                return
            }

            guard let content = String(data: data, encoding: .utf8) else {
                dashLogger.error("Failed to decode response as UTF-8")
                DispatchQueue.main.async {
                    completion(.failure(.invalidManifest))
                }
                return
            }

            self?.parseManifest(content: content, baseURL: url, completion: completion)
        }
        task.resume()
    }

    func parseManifest(content: String, baseURL: URL, completion: @escaping (Result<DASHParsedInfo, ParseError>) -> Void) {
        guard !content.isEmpty else {
            DispatchQueue.main.async {
                completion(.failure(.noContent))
            }
            return
        }

        // Basic validation - should contain MPD tag
        guard content.contains("<MPD") || content.contains("<mpd") else {
            dashLogger.error("Invalid manifest: no MPD tag found")
            DispatchQueue.main.async {
                completion(.failure(.invalidManifest))
            }
            return
        }

        guard let data = content.data(using: .utf8) else {
            DispatchQueue.main.async {
                completion(.failure(.invalidManifest))
            }
            return
        }

        let parserDelegate = MPDParserDelegate(baseURL: baseURL)
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parserDelegate

        if xmlParser.parse() {
            DispatchQueue.main.async {
                completion(.success(parserDelegate.result))
            }
        } else {
            let error = xmlParser.parserError ?? NSError(domain: "DASHParser", code: -1, userInfo: nil)
            dashLogger.error("XML parsing error: \(error.localizedDescription)")
            DispatchQueue.main.async {
                completion(.failure(.xmlParsingError(error)))
            }
        }
    }

    // MARK: - ISO 8601 Duration Parsing

    static func parseISO8601Duration(_ duration: String) -> TimeInterval? {
        // Pattern: PT[nH][nM][n.nS]
        // Examples: PT1H30M45.5S, PT30M, PT45S, PT1H, PT2H15M30S
        var total: TimeInterval = 0

        let pattern = #"PT(?:(\d+)H)?(?:(\d+)M)?(?:([\d.]+)S)?"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: duration, options: [], range: NSRange(duration.startIndex..., in: duration)) else {
            return nil
        }

        if let hoursRange = Range(match.range(at: 1), in: duration),
           let hours = Double(duration[hoursRange]) {
            total += hours * 3600
        }

        if let minutesRange = Range(match.range(at: 2), in: duration),
           let minutes = Double(duration[minutesRange]) {
            total += minutes * 60
        }

        if let secondsRange = Range(match.range(at: 3), in: duration),
           let seconds = Double(duration[secondsRange]) {
            total += seconds
        }

        return total > 0 ? total : nil
    }
}

// MARK: - XML Parser Delegate

private class MPDParserDelegate: NSObject, XMLParserDelegate {

    let baseURL: URL
    var result: DASHParsedInfo

    // Parsing context
    private var currentElement = ""
    private var currentAdaptationSet: AdaptationSetContext?
    private var currentRepresentation: RepresentationContext?
    private var currentBaseURL: String?
    private var characterBuffer = ""

    // Track all adaptation sets for final processing
    private var videoAdaptationSets: [AdaptationSetContext] = []
    private var audioAdaptationSets: [AdaptationSetContext] = []

    // MARK: - Context Structs

    struct AdaptationSetContext {
        var contentType: String?
        var mimeType: String?
        var lang: String?
        var label: String?
        var representations: [RepresentationContext] = []
        var hasContentProtection: Bool = false
        var segmentTemplate: SegmentTemplateContext?
        var baseURL: String?
    }

    struct RepresentationContext {
        var id: String?
        var bandwidth: Int = 0
        var width: Int?
        var height: Int?
        var codecs: String?
        var baseURL: String?
        var segmentTemplate: SegmentTemplateContext?
    }

    struct SegmentTemplateContext {
        var initialization: String?
        var media: String?
        var timescale: Int = 1
        var duration: Int?
        var startNumber: Int = 1
    }

    // MARK: - Initialization

    init(baseURL: URL) {
        self.baseURL = baseURL
        self.result = DASHParsedInfo(
            qualities: [],
            isLive: false,
            isDRMProtected: false,
            hasSubtitles: false,
            totalDuration: nil,
            audioTracks: nil,
            minBufferTime: nil
        )
        super.init()
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        characterBuffer = ""

        switch elementName.lowercased() {
        case "mpd":
            parseMPDElement(attributes: attributeDict)

        case "adaptationset":
            parseAdaptationSetElement(attributes: attributeDict)

        case "contentprotection":
            // Any ContentProtection element means DRM
            currentAdaptationSet?.hasContentProtection = true
            result.isDRMProtected = true

        case "representation":
            parseRepresentationElement(attributes: attributeDict)

        case "segmenttemplate":
            parseSegmentTemplateElement(attributes: attributeDict)

        case "baseurl":
            // Will capture in characters and process in didEndElement
            break

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        characterBuffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName.lowercased() {
        case "baseurl":
            let url = characterBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if currentRepresentation != nil {
                currentRepresentation?.baseURL = url
            } else if currentAdaptationSet != nil {
                currentAdaptationSet?.baseURL = url
            } else {
                currentBaseURL = url
            }

        case "representation":
            if var rep = currentRepresentation, currentAdaptationSet != nil {
                // Inherit segment template from AdaptationSet if not set
                if rep.segmentTemplate == nil {
                    rep.segmentTemplate = currentAdaptationSet?.segmentTemplate
                }
                currentAdaptationSet?.representations.append(rep)
            }
            currentRepresentation = nil

        case "adaptationset":
            if let adaptationSet = currentAdaptationSet {
                categorizeAdaptationSet(adaptationSet)
            }
            currentAdaptationSet = nil

        default:
            break
        }

        characterBuffer = ""
    }

    func parserDidEndDocument(_ parser: XMLParser) {
        buildQualities()
        buildAudioTracks()
    }

    // MARK: - Element Parsing

    private func parseMPDElement(attributes: [String: String]) {
        // type="static" (VOD) or "dynamic" (live)
        result.isLive = attributes["type"]?.lowercased() == "dynamic"

        // mediaPresentationDuration="PT1H30M45.5S"
        if let duration = attributes["mediaPresentationDuration"] {
            result.totalDuration = DASHParser.parseISO8601Duration(duration)
        }

        // minBufferTime="PT2S"
        if let bufferTime = attributes["minBufferTime"] {
            result.minBufferTime = DASHParser.parseISO8601Duration(bufferTime)
        }
    }

    private func parseAdaptationSetElement(attributes: [String: String]) {
        var context = AdaptationSetContext()
        context.contentType = attributes["contentType"]
        context.mimeType = attributes["mimeType"]
        context.lang = attributes["lang"]
        context.label = attributes["label"]

        // Detect subtitles
        let contentType = context.contentType?.lowercased() ?? ""
        let mimeType = context.mimeType?.lowercased() ?? ""

        if contentType == "text" ||
           mimeType.contains("text") ||
           mimeType.contains("ttml") ||
           mimeType.contains("vtt") ||
           mimeType.contains("subtitle") {
            result.hasSubtitles = true
        }

        currentAdaptationSet = context
    }

    private func parseRepresentationElement(attributes: [String: String]) {
        var context = RepresentationContext()
        context.id = attributes["id"]
        context.bandwidth = Int(attributes["bandwidth"] ?? "0") ?? 0
        context.width = Int(attributes["width"] ?? "")
        context.height = Int(attributes["height"] ?? "")
        context.codecs = attributes["codecs"]

        currentRepresentation = context
    }

    private func parseSegmentTemplateElement(attributes: [String: String]) {
        let template = SegmentTemplateContext(
            initialization: attributes["initialization"],
            media: attributes["media"],
            timescale: Int(attributes["timescale"] ?? "1") ?? 1,
            duration: Int(attributes["duration"] ?? ""),
            startNumber: Int(attributes["startNumber"] ?? "1") ?? 1
        )

        // Can be at AdaptationSet or Representation level
        if currentRepresentation != nil {
            currentRepresentation?.segmentTemplate = template
        } else if currentAdaptationSet != nil {
            currentAdaptationSet?.segmentTemplate = template
        }
    }

    // MARK: - Categorization

    private func categorizeAdaptationSet(_ adaptationSet: AdaptationSetContext) {
        let contentType = adaptationSet.contentType?.lowercased() ?? ""
        let mimeType = adaptationSet.mimeType?.lowercased() ?? ""

        if contentType == "video" || mimeType.contains("video") {
            videoAdaptationSets.append(adaptationSet)
        } else if contentType == "audio" || mimeType.contains("audio") {
            audioAdaptationSets.append(adaptationSet)
        }
        // Text/subtitle adaptation sets are already handled for hasSubtitles flag
    }

    // MARK: - Building Results

    private func buildQualities() {
        for adaptationSet in videoAdaptationSets {
            // Check if this adaptation set has DRM
            if adaptationSet.hasContentProtection {
                result.isDRMProtected = true
            }

            for rep in adaptationSet.representations {
                let resolution = formatResolution(width: rep.width, height: rep.height)
                let url = buildRepresentationURL(rep, adaptationSet: adaptationSet)

                let quality = StreamQuality(
                    id: UUID(),
                    resolution: resolution,
                    bandwidth: rep.bandwidth,
                    url: url,
                    codecs: rep.codecs
                )
                result.qualities.append(quality)
            }
        }

        // Sort by bandwidth descending
        result.qualities.sort { $0.bandwidth > $1.bandwidth }
    }

    private func buildAudioTracks() {
        var tracks: [DASHAudioTrack] = []

        for adaptationSet in audioAdaptationSets {
            // Use the highest bandwidth representation for this track
            if let rep = adaptationSet.representations.max(by: { $0.bandwidth < $1.bandwidth }) {
                let track = DASHAudioTrack(
                    id: UUID(),
                    language: adaptationSet.lang,
                    label: adaptationSet.label,
                    codecs: rep.codecs,
                    bandwidth: rep.bandwidth
                )
                tracks.append(track)
            }
        }

        if !tracks.isEmpty {
            result.audioTracks = tracks
        }
    }

    // MARK: - URL Building

    private func buildRepresentationURL(_ rep: RepresentationContext, adaptationSet: AdaptationSetContext) -> String {
        // Priority: Representation BaseURL > AdaptationSet BaseURL > MPD BaseURL > manifest URL

        if let baseURL = rep.baseURL {
            return resolveURL(baseURL)
        }

        if let template = rep.segmentTemplate ?? adaptationSet.segmentTemplate {
            if let initURL = template.initialization {
                let resolved = resolveTemplateURL(initURL, representationID: rep.id ?? "", bandwidth: rep.bandwidth)
                return resolveURL(resolved, additionalBase: adaptationSet.baseURL)
            }
        }

        if let baseURL = adaptationSet.baseURL {
            return resolveURL(baseURL)
        }

        // Fallback to manifest URL
        return baseURL.absoluteString
    }

    private func resolveTemplateURL(_ template: String, representationID: String, bandwidth: Int) -> String {
        var url = template
        url = url.replacingOccurrences(of: "$RepresentationID$", with: representationID)
        url = url.replacingOccurrences(of: "$Bandwidth$", with: String(bandwidth))
        // $Number$ and $Time$ are runtime values, use placeholders for now
        url = url.replacingOccurrences(of: "$Number$", with: "1")
        url = url.replacingOccurrences(of: "$Time$", with: "0")
        // Handle format specifiers like $Number%05d$
        let formatPattern = #"\$(\w+)%\d+d\$"#
        if let regex = try? NSRegularExpression(pattern: formatPattern) {
            url = regex.stringByReplacingMatches(in: url, range: NSRange(url.startIndex..., in: url), withTemplate: "1")
        }
        return url
    }

    private func resolveURL(_ urlString: String, additionalBase: String? = nil) -> String {
        // Absolute URL
        if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") {
            return urlString
        }

        var effectiveBase = baseURL

        // Apply additional base URL if present
        if let additionalBase = additionalBase {
            if additionalBase.hasPrefix("http://") || additionalBase.hasPrefix("https://") {
                effectiveBase = URL(string: additionalBase) ?? baseURL
            } else if additionalBase.hasPrefix("/") {
                if let scheme = baseURL.scheme, let host = baseURL.host {
                    effectiveBase = URL(string: "\(scheme)://\(host)\(additionalBase)") ?? baseURL
                }
            } else {
                effectiveBase = baseURL.deletingLastPathComponent().appendingPathComponent(additionalBase)
            }
        }

        // Absolute path
        if urlString.hasPrefix("/") {
            if let scheme = effectiveBase.scheme, let host = effectiveBase.host {
                return "\(scheme)://\(host)\(urlString)"
            }
        }

        // Relative path
        return effectiveBase.deletingLastPathComponent().appendingPathComponent(urlString).absoluteString
    }

    private func formatResolution(width: Int?, height: Int?) -> String {
        if let height = height {
            return "\(height)p"
        }
        if let width = width {
            // Estimate height from common aspect ratios
            let estimatedHeight = Int(Double(width) / 16.0 * 9.0)
            return "\(estimatedHeight)p"
        }
        return "Unknown"
    }
}
