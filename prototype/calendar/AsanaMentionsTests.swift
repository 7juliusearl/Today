import Foundation
@main struct AsanaMentionsTests {
    static func main() throws {
        let users = [["id":"123", "name":"Alex Morgan"]]
        let text = "👋 @Alex Morgan <hello> & bye"
        let html = try asanaMentionHTML(text, mentions:[["id":"123","start":3,"length":12]], users:users)
        assert(html == "<body>👋 <a data-asana-gid=\"123\"/> &lt;hello&gt; &amp; bye</body>")
        for mention: [String: Any] in [["id":"999","start":3,"length":12], ["id":"123","start":0,"length":12], ["id":"123","start":3,"length":Int.max]] {
            do { _ = try asanaMentionHTML(text, mentions:[mention], users:users); fatalError("Invalid tag accepted") } catch {}
        }
        print("PASS: Unicode ranges, escaped plain text, unknown users and invalid ranges.")
    }
}
