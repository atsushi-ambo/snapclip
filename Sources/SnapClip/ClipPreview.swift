import Foundation

/// Short, single-line labels for the menu bar picker.
enum ClipPreview {
    /// Keeps a history row narrow enough that the picker stays about half a screen.
    static let menuLimit = 28

    /// Long text keeps both the opening and the ending, so similar pastes stay distinct.
    static func menuLine(from text: String, limit: Int = menuLimit) -> String {
        let lines = meaningfulLines(text)
        guard let first = lines.first else { return "(empty)" }
        if lines.count == 1 { return headAndTail(first, limit: limit) }
        return openingAndClosing(first: first, last: lines[lines.count - 1], limit: limit)
    }

    /// Longer excerpt for the row tooltip. The menu title itself stays one short line.
    static func hoverText(from text: String, limit: Int = 160) -> String {
        let joined = meaningfulLines(text).joined(separator: " · ")
        if joined.isEmpty { return "(empty)" }
        guard joined.count > limit else { return joined }
        let end = joined.index(joined.startIndex, offsetBy: limit)
        return joined[..<end].trimmingCharacters(in: .whitespaces) + "…"
    }

    private static func meaningfulLines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines).compactMap { line in
            let collapsed = line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return collapsed.isEmpty ? nil : collapsed
        }
    }

    private static func headAndTail(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        guard text.count > limit else { return text }
        let tailCount = min(8, max(1, limit / 3))
        let headCount = limit - tailCount - 1
        guard headCount > 0 else { return String(text.prefix(limit)) }
        let head = String(text.prefix(headCount)).trimmingCharacters(in: .whitespaces)
        let tail = String(text.suffix(tailCount)).trimmingCharacters(in: .whitespaces)
        return head + "…" + tail
    }

    private static func openingAndClosing(first: String, last: String, limit: Int) -> String {
        if first.count + 1 + last.count <= limit {
            return first + "…" + last
        }
        let tailCount = min(8, last.count, max(1, limit - 2))
        let headCount = max(1, limit - tailCount - 1)
        let opening = String(first.prefix(headCount)).trimmingCharacters(in: .whitespaces)
        let closing = String(last.suffix(tailCount)).trimmingCharacters(in: .whitespaces)
        return opening + "…" + closing
    }
}
