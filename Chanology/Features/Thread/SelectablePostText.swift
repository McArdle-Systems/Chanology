import SwiftUI
import UIKit

/// A UITextView-backed post comment renderer that adds a "Quote" item to the
/// text selection menu. Selecting text and tapping Quote fires `onQuote` with
/// the selected plain text, which the parent can inject into the composer.
struct SelectablePostText: UIViewRepresentable {
    let html: String
    let myPostNumbers: [Int]
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
        let rendered = PostHTMLRenderer.renderNSAttributedString(html, myPostNumbers: myPostNumbers, tintColor: tint)
        if uiView.attributedText != rendered {
            uiView.attributedText = rendered
        }
        uiView.onQuote = onQuote
        context.coordinator.onLinkTap = onLinkTap
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: QuotableTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(size.height))
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UITextViewDelegate {
        var onLinkTap: ((URL) -> Void)?

        init(onLinkTap: ((URL) -> Void)?) {
            self.onLinkTap = onLinkTap
        }

        func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
            onLinkTap?(URL)
            return false  // Prevent UITextView's default link handling
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
