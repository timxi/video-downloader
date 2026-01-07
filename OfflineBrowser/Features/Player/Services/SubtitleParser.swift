import Foundation

struct SubtitleCue: Identifiable {
    let id = UUID()
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
}

protocol SubtitleParserProtocol {
    func parse(fileURL: URL) throws -> [SubtitleCue]
}

enum SubtitleParserError: Error {
    case fileNotFound
    case invalidFormat
    case readError(Error)
}

final class WebVTTParser: SubtitleParserProtocol {

    func parse(fileURL: URL) throws -> [SubtitleCue] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw SubtitleParserError.fileNotFound
        }

        let content: String
        do {
            content = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            throw SubtitleParserError.readError(error)
        }

        return parseContent(content)
    }

    func parseContent(_ content: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        let lines = content.components(separatedBy: .newlines)

        var index = 0

        // Skip WEBVTT header if present
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("WEBVTT") || line.isEmpty || line.hasPrefix("NOTE") {
                index += 1
                continue
            }
            break
        }

        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)

            // Skip empty lines and cue identifiers (numeric or text identifiers)
            if line.isEmpty {
                index += 1
                continue
            }

            // Check if this line is a timestamp line
            if line.contains("-->") {
                if let cue = parseCueBlock(lines: lines, timestampIndex: index) {
                    cues.append(cue)
                    // Skip past the text lines
                    index += 1
                    while index < lines.count && !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                        index += 1
                    }
                } else {
                    index += 1
                }
            } else {
                index += 1
            }
        }

        return cues.sorted { $0.startTime < $1.startTime }
    }

    private func parseCueBlock(lines: [String], timestampIndex: Int) -> SubtitleCue? {
        let timestampLine = lines[timestampIndex]

        guard let (startTime, endTime) = parseTimestamp(timestampLine) else {
            return nil
        }

        // Collect text lines until empty line or end of file
        var textLines: [String] = []
        var textIndex = timestampIndex + 1

        while textIndex < lines.count {
            let textLine = lines[textIndex]
            if textLine.trimmingCharacters(in: .whitespaces).isEmpty {
                break
            }
            textLines.append(textLine)
            textIndex += 1
        }

        guard !textLines.isEmpty else { return nil }

        let text = textLines.joined(separator: "\n")
        let cleanText = stripHTMLTags(text)

        return SubtitleCue(startTime: startTime, endTime: endTime, text: cleanText)
    }

    private func parseTimestamp(_ line: String) -> (TimeInterval, TimeInterval)? {
        // Format: "00:00:00.000 --> 00:00:05.000" or "00:00.000 --> 00:05.000"
        // May also have positioning info after timestamp: "00:00.000 --> 00:05.000 align:middle"
        let components = line.components(separatedBy: "-->")
        guard components.count >= 2 else { return nil }

        let startStr = components[0].trimmingCharacters(in: .whitespaces)
        // Remove any positioning info from end timestamp
        let endPart = components[1].trimmingCharacters(in: .whitespaces)
        let endStr = endPart.components(separatedBy: .whitespaces).first ?? endPart

        guard let start = parseTime(startStr),
              let end = parseTime(endStr) else {
            return nil
        }

        return (start, end)
    }

    private func parseTime(_ timeString: String) -> TimeInterval? {
        // Supports:
        // - HH:MM:SS.mmm
        // - MM:SS.mmm
        // - HH:MM:SS,mmm (SRT format comma)
        let normalized = timeString.replacingOccurrences(of: ",", with: ".")
        let components = normalized.components(separatedBy: ":")

        switch components.count {
        case 2:
            // MM:SS.mmm
            guard let minutes = Double(components[0]),
                  let seconds = parseSeconds(components[1]) else {
                return nil
            }
            return minutes * 60 + seconds

        case 3:
            // HH:MM:SS.mmm
            guard let hours = Double(components[0]),
                  let minutes = Double(components[1]),
                  let seconds = parseSeconds(components[2]) else {
                return nil
            }
            return hours * 3600 + minutes * 60 + seconds

        default:
            return nil
        }
    }

    private func parseSeconds(_ str: String) -> Double? {
        // Handle "SS.mmm" or just "SS"
        return Double(str)
    }

    private func stripHTMLTags(_ text: String) -> String {
        // Remove common WebVTT/HTML tags like <b>, <i>, <u>, <c.classname>, etc.
        var result = text

        // Remove tags with attributes: <tag attr="value">
        let tagPattern = "<[^>]+>"
        if let regex = try? NSRegularExpression(pattern: tagPattern, options: []) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }

        // Decode common HTML entities
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&#39;", with: "'")

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
