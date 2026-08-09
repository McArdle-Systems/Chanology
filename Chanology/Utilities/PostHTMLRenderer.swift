import Foundation
import UIKit

enum PostHTMLRenderer {

    /// Marks decorative " (OP)"/" (You)" reference-marker runs appended by
    /// `appendReferenceMarkersNS` so callers can exclude them when deriving
    /// plain text from a rendered attributed string (e.g. for quoting).
    static let referenceMarkerAttributeKey = NSAttributedString.Key("chanology.referenceMarker")

    /// Plain text for `range` in `attributed`, skipping any reference-marker
    /// runs so quoted/copied text doesn't pick up UI-only " (OP)"/" (You)" tags.
    static func plainText(from attributed: NSAttributedString, in range: NSRange) -> String {
        guard range.length > 0, range.location != NSNotFound, NSMaxRange(range) <= attributed.length else { return "" }
        let sub = attributed.attributedSubstring(from: range)
        var out = ""
        sub.enumerateAttribute(referenceMarkerAttributeKey, in: NSRange(location: 0, length: sub.length)) { value, subRange, _ in
            guard value == nil else { return }
            out += (sub.string as NSString).substring(with: subRange)
        }
        return out
    }

    // MARK: - Public

    /// Plain text with entities decoded — used for catalog previews and notifications.
    static func plainText(_ html: String) -> String {
        let noTags = html
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<wbr>", with: "")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return decodeEntities(noTags).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Bare URL linkification

    private static let urlDetector: NSDataDetector? = {
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    }()

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

    // MARK: - UIKit rendering (for UITextView-based selection)

    static func renderNSAttributedString(_ html: String, myPostNumbers: [Int] = [], opNo: Int? = nil, tintColor: UIColor = .systemBlue) -> NSAttributedString {
        let html = html.replacingOccurrences(of: "<wbr>", with: "")
        let result = NSMutableAttributedString()
        var styleStack: [UIKitStyle] = [UIKitStyle()]
        var index = html.startIndex
        var externalLinkHref: String? = nil
        var skipInnerText = false
        var pendingOverflow: String? = nil

        while index < html.endIndex {
            if html[index] == "<" {
                guard let tagEnd = html[index...].range(of: ">") else { break }
                let raw = String(html[html.index(after: index)..<tagEnd.lowerBound])
                index = tagEnd.upperBound
                if raw.hasPrefix("!") || raw.hasPrefix("?") { continue }

                let isClose = raw.hasPrefix("/")
                let body = isClose ? String(raw.dropFirst()) : raw
                let nameEnd = body.firstIndex(where: { $0 == " " || $0 == "\t" }) ?? body.endIndex
                let tagName = String(body[..<nameEnd].lowercased())

                if isClose {
                    switch tagName {
                    case "a":
                        if let href = externalLinkHref, let url = URL(string: href) {
                            var attrs = styleStack.last?.attributes ?? [:]
                            attrs[.link] = url
                            attrs[.foregroundColor] = tintColor
                            result.append(NSAttributedString(string: href, attributes: attrs))
                            externalLinkHref = nil
                            skipInnerText = false
                        }
                        if styleStack.count > 1 { styleStack.removeLast() }
                    default:
                        if styleStack.count > 1 { styleStack.removeLast() }
                    }
                } else {
                    let attrs = parseAttrs(String(body[nameEnd...]))
                    if tagName == "br" {
                        result.append(NSAttributedString(string: "\n", attributes: styleStack.last?.attributes ?? [:]))
                    }
                    applyOpenTagUIKit(name: tagName, attrs: attrs, stack: &styleStack, tintColor: tintColor)
                    if tagName == "a", attrs["class"] != "quotelink",
                       let href = attrs["href"],
                       let url = URL(string: href),
                       url.scheme == "http" || url.scheme == "https" {
                        externalLinkHref = href
                        skipInnerText = true
                    }
                }
            } else {
                let textEnd = html[index...].firstIndex(of: "<") ?? html.endIndex
                let raw = String(html[index..<textEnd])
                index = textEnd
                let decoded = decodeEntities(raw)

                if skipInnerText, let href = externalLinkHref {
                    if href.hasPrefix(decoded) {
                        pendingOverflow = String(href.dropFirst(decoded.count))
                        if pendingOverflow?.isEmpty == true { pendingOverflow = nil }
                    }
                    continue
                }

                if let overflow = pendingOverflow {
                    pendingOverflow = nil
                    if decoded.hasPrefix(overflow) {
                        let remaining = String(decoded.dropFirst(overflow.count))
                        if !remaining.isEmpty {
                            let s = styleStack.last ?? UIKitStyle()
                            result.append(linkifyURLsNS(in: remaining, style: s, tintColor: tintColor))
                        }
                        continue
                    }
                }

                let currentStyle = styleStack.last ?? UIKitStyle()
                if currentStyle.link != nil {
                    result.append(NSAttributedString(string: decoded, attributes: currentStyle.attributes))
                } else {
                    result.append(linkifyURLsNS(in: decoded, style: currentStyle, tintColor: tintColor))
                }
            }
        }

        if !myPostNumbers.isEmpty || opNo != nil {
            appendReferenceMarkersNS(to: result, myPostNumbers: Set(myPostNumbers), opNo: opNo)
        }

        return result
    }

    private static func applyOpenTagUIKit(name: String, attrs: [String: String], stack: inout [UIKitStyle], tintColor: UIColor) {
        switch name {
        case "br", "wbr": return
        case "span":
            var s = stack.last ?? UIKitStyle()
            switch attrs["class"] {
            case "quote":    s.color = UIColor(red: 0.45, green: 0.60, blue: 0.27, alpha: 1)
            case "deadlink": s.color = .secondaryLabel; s.strikethrough = true
            default: break
            }
            stack.append(s)
        case "a":
            var s = stack.last ?? UIKitStyle()
            if attrs["class"] == "quotelink", let href = attrs["href"], let url = resolveQuoteLink(href) {
                s.link = url; s.color = tintColor
            }
            stack.append(s)
        case "b", "strong": var s = stack.last ?? UIKitStyle(); s.isBold = true;      stack.append(s)
        case "i", "em":     var s = stack.last ?? UIKitStyle(); s.isItalic = true;    stack.append(s)
        case "s":           var s = stack.last ?? UIKitStyle(); s.isSpoiler = true;   stack.append(s)
        case "pre", "code": var s = stack.last ?? UIKitStyle(); s.isMonospace = true; stack.append(s)
        default: stack.append(stack.last ?? UIKitStyle())
        }
    }

    /// Inserts " (OP)" and/or " (You)" after quotelinks (`>>N`) that reference the thread's
    /// OP post or one of the user's own posts, mirroring the website's reply markers.
    private static func appendReferenceMarkersNS(to result: NSMutableAttributedString, myPostNumbers: Set<Int>, opNo: Int?) {
        var insertions: [(Int, NSAttributedString)] = []
        let font = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .caption2).pointSize, weight: .bold)
        result.enumerateAttribute(.link, in: NSRange(location: 0, length: result.length)) { value, range, _ in
            guard let url = value as? URL,
                  url.scheme == "chanology", url.host() == "post",
                  let postNo = Int(url.lastPathComponent) else { return }

            let combined = NSMutableAttributedString()
            if let opNo, postNo == opNo {
                combined.append(NSAttributedString(string: " (OP)", attributes: [
                    .foregroundColor: PostMarkerColor.op,
                    .font: font,
                    referenceMarkerAttributeKey: true
                ]))
            }
            if myPostNumbers.contains(postNo) {
                combined.append(NSAttributedString(string: " (You)", attributes: [
                    .foregroundColor: PostMarkerColor.you,
                    .font: font,
                    referenceMarkerAttributeKey: true
                ]))
            }
            guard combined.length > 0 else { return }
            insertions.append((range.upperBound, combined))
        }
        for (location, str) in insertions.reversed() {
            result.insert(str, at: location)
        }
    }

    private static func linkifyURLsNS(in text: String, style: UIKitStyle, tintColor: UIColor) -> NSAttributedString {
        guard let detector = urlDetector else {
            return NSAttributedString(string: text, attributes: style.attributes)
        }
        let nsText = text as NSString
        let matches = detector.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else {
            return NSAttributedString(string: text, attributes: style.attributes)
        }

        let result = NSMutableAttributedString()
        var cursor = text.startIndex

        for match in matches {
            guard let range = Range(match.range, in: text), let url = match.url else { continue }

            if cursor < range.lowerBound {
                result.append(NSAttributedString(string: String(text[cursor..<range.lowerBound]), attributes: style.attributes))
            }

            var linkAttrs = style.attributes
            linkAttrs[.link] = url
            linkAttrs[.foregroundColor] = tintColor
            result.append(NSAttributedString(string: String(text[range]), attributes: linkAttrs))

            cursor = range.upperBound
        }

        if cursor < text.endIndex {
            result.append(NSAttributedString(string: String(text[cursor...]), attributes: style.attributes))
        }

        return result
    }

    private struct UIKitStyle {
        var color: UIColor?
        var isBold = false
        var isItalic = false
        var isMonospace = false
        var isSpoiler = false
        var strikethrough = false
        var link: URL?

        var resolvedFont: UIFont {
            let size = UIFont.preferredFont(forTextStyle: .body).pointSize
            if isMonospace { return .monospacedSystemFont(ofSize: size, weight: .regular) }
            if isBold && isItalic,
               let desc = UIFont.systemFont(ofSize: size, weight: .bold).fontDescriptor.withSymbolicTraits(.traitItalic) {
                return UIFont(descriptor: desc, size: size)
            }
            if isBold   { return .systemFont(ofSize: size, weight: .bold) }
            if isItalic { return .italicSystemFont(ofSize: size) }
            return .preferredFont(forTextStyle: .body)
        }

        var attributes: [NSAttributedString.Key: Any] {
            var attrs: [NSAttributedString.Key: Any] = [.font: resolvedFont]
            if isSpoiler {
                let c = UIColor(white: 0.15, alpha: 1)
                attrs[.foregroundColor] = c
                attrs[.backgroundColor] = c
                return attrs
            }
            if let link  { attrs[.link] = link }
            attrs[.foregroundColor] = color ?? .label
            if strikethrough { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            return attrs
        }
    }
}
