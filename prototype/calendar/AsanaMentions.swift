import Foundation

// Ranges use UTF-16, matching textarea selection offsets. Never accept caller HTML.
func asanaMentionHTML(_ text: String, mentions: [[String: Any]], users: [[String: String]]) throws -> String {
    func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
    let source = text as NSString
    var end = 0, result = "<body>"
    for mention in mentions.sorted(by: { ($0["start"] as? Int ?? -1) < ($1["start"] as? Int ?? -1) }) {
        guard let id = mention["id"] as? String, !id.isEmpty, id.allSatisfy({ $0.isASCII && $0.isNumber }),
              let name = users.first(where: { $0["id"] == id })?["name"],
              let start = mention["start"] as? Int, let length = mention["length"] as? Int,
              start >= end, length > 0, start <= source.length, length <= source.length - start,
              source.substring(with: NSRange(location: start, length: length)) == "@" + name else {
            throw NSError(domain: "AsanaMentions", code: 1, userInfo: [NSLocalizedDescriptionKey: "A tagged name changed. Select that person again before posting."])
        }
        result += escape(source.substring(with: NSRange(location: end, length: start - end)))
        result += "<a data-asana-gid=\"\(id)\"/>"
        end = start + length
    }
    result += escape(source.substring(from: end)) + "</body>"
    return result
}
