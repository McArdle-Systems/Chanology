import Foundation
import SwiftUI

/// Converts 4chan HTML comment markup into an AttributedString suitable for SwiftUI Text.
///
/// 4chan HTML patterns handled:
///   <br>                              → newline
///   <wbr>                             → ignored (soft hyphen hint)
///   <span class="quote">…</span>      → greentext (green)
///   <span class="deadlink">…</span>   → dead quote link (strikethrough, muted)
///   <a class="quotelink" href="#pN">  → live quote link (accent color)
///   <b> / <strong>                    → bold
///   <i> / <em>                        → italic
///   <s>                               → spoiler (hidden, revealed on copy)
///   <pre>                             → monospaced
///   HTML entities                     → decoded
enum PostHTMLRenderer {

    // MARK: - Public

    /// Renders HTML with optional (You) markers on quotelinks that reference your posts.
    static func render(_ html: String, myPostNumbers: [Int] = []) -> AttributedString {
        let result = renderBase(html)
        guard !myPostNumbers.isEmpty else { return result }
        return appendYouMarkers(to: result, myPostNumbers: Set(myPostNumbers))
    }

    /// Appends " (You)" in orange after any quotelink whose target is one of myPostNumbers.
    private static func appendYouMarkers(to input: AttributedString, myPostNumbers: Set<Int>) -> AttributedString {
        var result = AttributedString()
        var index = input.startIndex

        while index < input.endIndex {
            let run = input.runs[index]
            let range = run.range

            // Check if this run has a link to one of our posts
            if let link = run.link,
               link.scheme == "chanology",
               link.host() == "post",
               let postNo = Int(link.lastPathComponent),
               myPostNumbers.contains(postNo) {
                // Append the original quotelink run
                result.append(input[range])
                // Append " (You)" marker
                var youMarker = AttributedString(" (You)")
                youMarker.foregroundColor = .orange
                youMarker.font = .caption2.bold()
                result.append(youMarker)
            } else {
                result.append(input[range])
            }

            index = run.range.upperBound
        }

        return result
    }

    private static func renderBase(_ html: String) -> AttributedString {
        // Strip <wbr> tags before parsing. 4chan inserts these as word-break hints
        // inside bare URLs (e.g. "https://example.com/long<wbr>path"), which splits
        // the URL into separate text nodes and breaks linkification.
        let html = html.replacingOccurrences(of: "<wbr>", with: "")

        var result = AttributedString()
        var styleStack: [Style] = [Style()]
        var index = html.startIndex

        while index < html.endIndex {
            if html[index] == "<" {
                guard let tagEnd = html[index...].range(of: ">") else { break }
                let raw = String(html[html.index(after: index)..<tagEnd.lowerBound])
                index = tagEnd.upperBound

                if raw.hasPrefix("!") || raw.hasPrefix("?") { continue }

                let isClose = raw.hasPrefix("/")
                let body = isClose ? String(raw.dropFirst()) : raw

                // Extract tag name
                let nameEnd = body.firstIndex(where: { $0 == " " || $0 == "\t" }) ?? body.endIndex
                let tagName = body[..<nameEnd].lowercased()

                if isClose {
                    switch tagName {
                    case "br", "wbr": break
                    default:
                        if styleStack.count > 1 { styleStack.removeLast() }
                    }
                } else {
                    let attrs = parseAttrs(String(body[nameEnd...]))
                    applyOpenTag(
                        name: String(tagName),
                        attrs: attrs,
                        into: &result,
                        stack: &styleStack
                    )
                }
            } else {
                let textEnd = html[index...].firstIndex(of: "<") ?? html.endIndex
                let raw = String(html[index..<textEnd])
                index = textEnd

                let decoded = decodeEntities(raw)
                let currentStyle = styleStack.last ?? Style()

                // If the current style already has a link (we're inside a quotelink <a> tag),
                // don't try to auto-detect URLs — just apply the style as-is.
                if currentStyle.link != nil {
                    var chunk = AttributedString(decoded)
                    applyStyle(currentStyle, to: &chunk)
                    result.append(chunk)
                } else {
                    // Auto-linkify bare URLs in plain text
                    result.append(linkifyURLs(in: decoded, style: currentStyle))
                }
            }
        }

        return result
    }

    /// Plain text with entities decoded — used for catalog previews and notifications.
    static func plainText(_ html: String) -> String {
        let noTags = html
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<wbr>", with: "")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return decodeEntities(noTags).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Private: tag handling

    private static func applyOpenTag(
        name: String,
        attrs: [String: String],
        into result: inout AttributedString,
        stack: inout [Style]
    ) {
        switch name {
        case "br":
            result.append(AttributedString("\n"))
        case "wbr":
            break
        case "span":
            var s = stack.last ?? Style()
            switch attrs["class"] {
            case "quote":    s.color = .init(red: 0.45, green: 0.60, blue: 0.27)
            case "deadlink": s.color = .secondary; s.strikethrough = true
            default: break
            }
            stack.append(s)
        case "a":
            var s = stack.last ?? Style()
            if attrs["class"] == "quotelink", let href = attrs["href"] {
                s.color = .accentColor
                s.link = Self.resolveQuoteLink(href)
            } else if let href = attrs["href"], let url = URL(string: href),
                      url.scheme == "http" || url.scheme == "https" {
                // External link (YouTube, Twitter, etc.)
                s.color = .accentColor
                s.link = url
            }
            stack.append(s)
        case "b", "strong":
            var s = stack.last ?? Style(); s.bold = true; stack.append(s)
        case "i", "em":
            var s = stack.last ?? Style(); s.italic = true; stack.append(s)
        case "s":
            var s = stack.last ?? Style(); s.spoiler = true; stack.append(s)
        case "pre", "code":
            var s = stack.last ?? Style(); s.monospace = true; stack.append(s)
        default:
            stack.append(stack.last ?? Style())
        }
    }

    private static func applyStyle(_ style: Style, to chunk: inout AttributedString) {
        if style.spoiler {
            // Spoiler: text same color as background — standard chan convention
            chunk.foregroundColor = .init(white: 0.15)
            chunk.backgroundColor = .init(white: 0.15)
            return
        }
        if let link = style.link {
            chunk.link = link
            chunk.foregroundColor = .accentColor
        } else if let color = style.color {
            chunk.foregroundColor = color
        }
        if style.strikethrough { chunk.strikethroughStyle = .single }

        switch (style.bold, style.italic, style.monospace) {
        case (true,  true,  _):     chunk.font = .body.bold().italic()
        case (true,  false, _):     chunk.font = .body.bold()
        case (false, true,  _):     chunk.font = .body.italic()
        case (false, false, true):  chunk.font = .system(.body, design: .monospaced)
        default: break
        }
    }

    // MARK: - Bare URL linkification

    /// Detects bare http(s) URLs in text and makes them tappable links.
    private static let urlDetector: NSDataDetector? = {
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    }()

    private static func linkifyURLs(in text: String, style: Style) -> AttributedString {
        guard let detector = urlDetector else {
            var chunk = AttributedString(text)
            applyStyle(style, to: &chunk)
            return chunk
        }

        let nsText = text as NSString
        let matches = detector.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        guard !matches.isEmpty else {
            var chunk = AttributedString(text)
            applyStyle(style, to: &chunk)
            return chunk
        }

        var result = AttributedString()
        var cursor = text.startIndex

        for match in matches {
            guard let range = Range(match.range, in: text), let url = match.url else { continue }

            // Append text before this URL
            if cursor < range.lowerBound {
                var before = AttributedString(text[cursor..<range.lowerBound])
                applyStyle(style, to: &before)
                result.append(before)
            }

            // Append the URL as a tappable link
            var linkChunk = AttributedString(text[range])
            var linkStyle = style
            linkStyle.link = url
            linkStyle.color = .accentColor
            applyStyle(linkStyle, to: &linkChunk)
            result.append(linkChunk)

            cursor = range.upperBound
        }

        // Append any remaining text after the last URL
        if cursor < text.endIndex {
            var after = AttributedString(text[cursor...])
            applyStyle(style, to: &after)
            result.append(after)
        }

        return result
    }

    // MARK: - Link resolution

    /// Converts an href from a quotelink into a chanology:// URL.
    ///
    /// Patterns:
    ///   #p123456                           → chanology://post/123456        (same-thread)
    ///   /g/                                → chanology://board/g            (cross-board)
    ///   /g/thread/123456                   → chanology://thread/g/123456    (cross-board thread)
    ///   /g/thread/123456#p789              → chanology://thread/g/123456    (cross-board post in thread)
    private static func resolveQuoteLink(_ href: String) -> URL? {
        // Same-thread post reference: #p123456
        if href.hasPrefix("#p"), let postNo = Int(href.dropFirst(2)) {
            return URL(string: "chanology://post/\(postNo)")
        }

        // Cross-board patterns: /board/ or /board/thread/N or /board/thread/N#pN
        let cleaned = href.components(separatedBy: "#").first ?? href
        let parts = cleaned.split(separator: "/", omittingEmptySubsequences: true)

        if parts.count == 1 {
            // /g/ → board link
            return URL(string: "chanology://board/\(parts[0])")
        }
        if parts.count >= 3, parts[1] == "thread", let threadNo = Int(parts[2]) {
            // /g/thread/123456
            return URL(string: "chanology://thread/\(parts[0])/\(threadNo)")
        }

        return nil
    }

    // MARK: - Private: attribute parser

    /// Minimalist attr parser: class="foo" href="#pN"
    private static func parseAttrs(_ raw: String) -> [String: String] {
        var result: [String: String] = [:]
        let pattern = #/(\w[\w-]*)(?:\s*=\s*(?:"([^"]*)"|\S+))?/#
        for match in raw.matches(of: pattern) {
            let key = String(match.output.1)
            let value = match.output.2.map(String.init) ?? ""
            result[key] = value
        }
        return result
    }

    // MARK: - Private: entity decoder

    static func decodeEntities(_ input: String) -> String {
        guard input.contains("&") else { return input }

        var out = ""
        out.reserveCapacity(input.count)
        var i = input.startIndex

        while i < input.endIndex {
            guard input[i] == "&" else {
                out.append(input[i])
                i = input.index(after: i)
                continue
            }

            guard let semi = input[i...].firstIndex(of: ";"),
                  input.distance(from: i, to: semi) <= 10 else {
                // No semicolon nearby — treat as literal ampersand
                out.append("&")
                i = input.index(after: i)
                continue
            }

            let entity = String(input[i...semi])
            i = input.index(after: semi)

            if let ch = namedEntity(entity) {
                out.append(ch)
            } else if entity.hasPrefix("&#x") || entity.hasPrefix("&#X") {
                let hex = entity.dropFirst(3).dropLast()
                if let code = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(code) {
                    out.append(Character(scalar))
                } else { out.append(contentsOf: entity) }
            } else if entity.hasPrefix("&#") {
                let dec = entity.dropFirst(2).dropLast()
                if let code = UInt32(dec), let scalar = Unicode.Scalar(code) {
                    out.append(Character(scalar))
                } else { out.append(contentsOf: entity) }
            } else {
                out.append(contentsOf: entity)
            }
        }

        return out
    }

    private static func namedEntity(_ e: String) -> Character? {
        switch e {
        case "&amp;":           return "&"
        case "&lt;":            return "<"
        case "&gt;":            return ">"
        case "&quot;":          return "\""
        case "&#039;", "&#39;", "&apos;": return "'"
        case "&nbsp;":          return "\u{00A0}"
        case "&mdash;":         return "\u{2014}"
        case "&ndash;":         return "\u{2013}"
        case "&lsquo;":         return "\u{2018}"
        case "&rsquo;":         return "\u{2019}"
        case "&ldquo;":         return "\u{201C}"
        case "&rdquo;":         return "\u{201D}"
        case "&hellip;":        return "\u{2026}"
        default:                return nil
        }
    }

    // MARK: - Style state

    private struct Style {
        var color: Color? = nil
        var bold = false
        var italic = false
        var spoiler = false
        var strikethrough = false
        var monospace = false
        var link: URL? = nil
    }
}
