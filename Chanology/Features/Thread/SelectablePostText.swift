import SwiftUI
import UIKit

/// A UITextView-backed post comment renderer that adds a "Quote" item to the
/// text selection menu. Selecting text and tapping Quote fires `onQuote` with
/// the selected plain text, which the parent can inject into the composer.
struct SelectablePostText: UIViewRepresentable {
    let html: String
    let myPostNumbers: [Int]
    var opNo: Int? = nil
    var searchQuery: String? = nil
    var onSelectionChange: ((String?) -> Void)?
    var onQuote: ((String) -> Void)?
    var onLinkTap: ((URL) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onLinkTap: onLinkTap)
    }

    func makeUIView(context: Context) -> QuotableTextView {
        let tv = QuotableTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.delegate = context.coordinator
        return tv
    }

    func updateUIView(_ uiView: QuotableTextView, context: Context) {
        let tint = uiView.tintColor ?? .systemBlue
        let base = PostHTMLRenderer.renderNSAttributedString(html, myPostNumbers: myPostNumbers, opNo: opNo, tintColor: tint)
        let rendered: NSAttributedString
        if let query = searchQuery, !query.isEmpty {
            let mutable = NSMutableAttributedString(attributedString: base)
            let text = mutable.string as NSString
            var searchRange = NSRange(location: 0, length: text.length)
            while searchRange.location < text.length {
                let found = text.range(of: query, options: .caseInsensitive, range: searchRange)
                if found.location == NSNotFound { break }
                mutable.addAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.5), range: found)
                let next = found.location + max(1, found.length)
                searchRange = NSRange(location: next, length: text.length - next)
            }
            rendered = mutable
        } else {
            rendered = base
        }
        if uiView.attributedText != rendered {
            uiView.attributedText = rendered
        }
        uiView.onQuote = onQuote
        context.coordinator.onLinkTap = onLinkTap
        context.coordinator.onSelectionChange = onSelectionChange
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: QuotableTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(size.height))
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UITextViewDelegate {
        var onLinkTap: ((URL) -> Void)?
        var onSelectionChange: ((String?) -> Void)?

        init(onLinkTap: ((URL) -> Void)?) {
            self.onLinkTap = onLinkTap
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard let range = textView.selectedTextRange,
                  !range.isEmpty,
                  let text = textView.text(in: range),
                  !text.isEmpty else {
                onSelectionChange?(nil)
                return
            }
            onSelectionChange?(text)
        }

        func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
            if case .link(let url) = textItem.content {
                return UIAction { [weak self] _ in self?.onLinkTap?(url) }
            }
            return defaultAction
        }
    }
}

// MARK: - QuotableTextView

class QuotableTextView: UITextView {
    var onQuote: ((String) -> Void)?

    /// Injects a "Quote" action at the top of the text selection menu (iOS 16+).
    override func editMenu(for textRange: UITextRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        var actions = suggestedActions
        if let selected = text(in: textRange), !selected.isEmpty {
            let quote = UIAction(title: "Quote", image: UIImage(systemName: "quote.opening")) { [weak self] _ in
                self?.onQuote?(selected)
            }
            actions.insert(quote, at: 0)
        }
        return UIMenu(children: actions)
    }
}
