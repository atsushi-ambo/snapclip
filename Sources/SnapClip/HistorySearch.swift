import Foundation

enum HistorySearch {
    /// Search full text rather than the shortened menu preview. Images match their
    /// description (dimensions); no OCR or network service is involved.
    static func filter(_ items: [ClipItem], query: String, kind: ClipKind?) -> [ClipItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            guard kind == nil || item.kind == kind else { return false }
            if needle.isEmpty { return true }
            if item.preview.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                return true
            }
            guard item.kind == .text, HistoryStore.isPathInsideSupportDir(item.absolutePath),
                  let text = try? String(contentsOf: item.absolutePath, encoding: .utf8) else { return false }
            return text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
    static func excerpt(for item: ClipItem, query: String) -> String {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty, item.kind == .text,
              HistoryStore.isPathInsideSupportDir(item.absolutePath),
              let text = try? String(contentsOf: item.absolutePath, encoding: .utf8),
              let match = text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return item.preview
        }
        let start = text.index(match.lowerBound, offsetBy: -30, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(match.upperBound, offsetBy: 60, limitedBy: text.endIndex) ?? text.endIndex
        return (start > text.startIndex ? "…" : "") +
            text[start..<end].replacingOccurrences(of: "\n", with: "⏎").replacingOccurrences(of: "\r", with: "") +
            (end < text.endIndex ? "…" : "")
    }

}
