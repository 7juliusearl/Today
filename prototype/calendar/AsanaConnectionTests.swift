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
        assert(tasks.count == 3)
        assert(!tasks.contains { $0.dueDate.isEmpty || $0.dueDate == "2026-10-09" }, "Only dated tasks this week")
        let boundaries = assignedAsanaTasks([record("sun", "2026-09-20"), record("mon", "2026-09-21"), record("end", "2026-09-27"), record("next", "2026-09-28")], now: now, calendar: calendar)
        assert(boundaries.map(\.id) == ["asana:mon", "asana:end"])
        assert(tasks.first?.id == "asana:6", "Overdue tasks included first")
        let nested = try JSONDecoder().decode(AsanaAssignedTask.self, from: Data(#"{"gid":"9","name":"Edit","completed":false,"due_on":"2026-09-24","parent":{"gid":"10","name":"Promo"},"projects":[{"gid":"11","name":"Creative"}]}"#.utf8))
        let mapped = assignedAsanaTasks([nested], now: now)
        assert(mapped.first?.parent?.name == "Promo" && mapped.first?.project?.name == "Creative")
        print("PASS: callback state/destination checks; assigned-task dates, timezone, completion, Monday–Sunday boundaries, deduplication and parent/project grouping metadata.")
    }
    @MainActor static func tryCode(_ text: String, _ state: String) -> String? { try? AsanaAuth.callbackCode(URL(string: text)!, state: state) }
}
