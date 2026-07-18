import Foundation

extension String {
    /// Decodes the small set of HTML entities LDBWS occasionally embeds in
    /// otherwise-plain text fields (operator names, station names, etc.).
    /// Not a full HTML parser — only handles `&amp;`, `&lt;`, `&gt;`,
    /// `&quot;`, `&#39;`, `&nbsp;`, which is what Darwin returns.
    func decodingHTMLEntities() -> String {
        var s = self
        // `&amp;` must run last so we don't double-decode entities like
        // `&amp;lt;`. Replace it after the others.
        s = s
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
        return s
    }
}
