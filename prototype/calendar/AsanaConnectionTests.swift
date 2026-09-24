import Foundation

@main struct AsanaConnectionTests {
    @MainActor static func main() throws {
        let state = try AsanaAuth.random()
        assert(state.count == 43)
        assert(tryCode("today-asana://oauth?code=abc&state=\(state)", state) == "abc")
        assert(tryCode("today-asana://oauth?code=abc&state=wrong", state) == nil)
        assert(tryCode("https://example.com?code=abc&state=\(state)", state) == nil)
        assert(tryCode("today-asana://oauth?code=abc&code=other&state=\(state)", state) == nil)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: -4 * 3600)!
        let now = ISO8601DateFormatter().date(from: "2026-09-24T12:00:00Z")!
        func record(_ id: String, _ date: String?, _ time: String? = nil, done: Bool = false) -> AsanaAssignedTask {
            .init(gid: id, name: "Task", completed: done, due_on: date, due_at: time, notes: nil, permalink_url: nil)
        }
        let records = [record("1", "2026-09-24"), record("1", "2026-09-24"), record("2", nil), record("3", "2026-09-24", done: true), record("4", "2026-09-25", "2026-09-25T01:00:00.000Z"), record("5", "2026-10-09"), record("6", "2026-09-23")]
        let tasks = assignedAsanaTasks(records, now: now, calendar: calendar)
        assert(tasks.count == 2)
        assert(tasks.allSatisfy { $0.dueDate == "2026-09-24" })
        assert(tasks.first?.id == "asana:1")
        print("PASS: callback state/destination checks; assigned-task dates, timezone, completion, deduplication and date window.")
    }
    @MainActor static func tryCode(_ text: String, _ state: String) -> String? { try? AsanaAuth.callbackCode(URL(string: text)!, state: state) }
}
