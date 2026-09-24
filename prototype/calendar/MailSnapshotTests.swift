import Foundation

@main struct MailSnapshotTests {
    static func main() throws {
        let readerResponse = Data(#"{"items":[]}"#.utf8)
        let empty = try JSONDecoder().decode(MailSnapshot.self, from: readerResponse)
        assert(empty.items.isEmpty && empty.stickyNotesEnabled == false)
        let noteResponse = Data(#"{"items":[{"id":"1","messageID":"one","subject":"sticky note","sender":"Sender","attachmentCount":0,"receivedAt":"2026-09-24T00:00:00Z","stickyBody":"Have a great day!"}]}"#.utf8)
        var notes = try JSONDecoder().decode(MailSnapshot.self, from: noteResponse)
        assert(notes.items.first?.stickyBody == "Have a great day!")
        notes.stickyNotesEnabled = true
        notes.stickyScope = "test"
        let roundTrip = try JSONDecoder().decode(MailSnapshot.self, from: JSONEncoder().encode(notes))
        assert(roundTrip.stickyNotesEnabled && roundTrip.stickyScope == "test")
        print("PASS reader snapshots decode without app-only settings and retain note data")
    }
}
