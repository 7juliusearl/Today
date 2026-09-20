import Foundation
import EventKit

@main struct CalendarDataTests {
    static func main() throws {
        let store = EKEventStore()
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = "Test calendar"
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func day(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: today)! }
        func event(_ title: String, _ start: Date, _ end: Date, allDay: Bool = false) -> EKEvent {
            let e = EKEvent(eventStore: store)
            e.calendar = calendar; e.title = title; e.startDate = start; e.endDate = end; e.isAllDay = allDay
            return e
        }
        let overnight = event("Overnight", day(-1).addingTimeInterval(23*3600), today.addingTimeInterval(3600))
        let allDay = event("All day", day(1), day(2), allDay: true)
        let ended = event("Already ended", day(-1), today)
        let meeting = event("Meeting", today.addingTimeInterval(12*3600), today.addingTimeInterval(13*3600))
        meeting.notes = "Join https://meet.google.com/abc-defg-hij"
        meeting.url = URL(string: "javascript:alert(1)")
        assert(!mappedEvent(meeting, primary: nil).recurring, "A one-off event must not be labeled recurring")
        let weekly = event("Weekly meeting", today, today.addingTimeInterval(3600))
        weekly.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil))
        assert(mappedEvent(weekly, primary: nil).recurring, "A weekly series must be labeled recurring")
        let payload = calendarPayload([allDay, ended, meeting, overnight], now: today, primary: calendar.calendarIdentifier)
        assert(payload.events.map(\.title) == ["Overnight", "Meeting"], "Overlap and exclusive end dates")
        assert(payload.upcoming.count == 1 && payload.upcoming[0].events[0].allDay, "All-day event belongs on one day")
        assert(payload.events[1].meetingLink == "https://meet.google.com/abc-defg-hij", "Extract meeting from notes")
        assert(payload.events[1].htmlLink == nil, "Reject unsafe event URLs")
        let many = (1...14).map { event("Day \($0)", day($0), day($0+1), allDay: true) }
        assert(calendarPayload(many, now: today, primary: nil).upcoming.count == 5, "Limit upcoming to five dates")
        let recurring = event("Occurrence", day(1), day(1).addingTimeInterval(3600))
        let next = event("Occurrence", day(2), day(2).addingTimeInterval(3600))
        assert(mappedEvent(recurring, primary: nil).id != mappedEvent(next, primary: nil).id, "Occurrences have distinct IDs")
        let encoded = try JSONEncoder().encode(payload)
        _ = try JSONSerialization.jsonObject(with: encoded)
        print("Passed calendar mapping checks: one-off/weekly recurrence, overlap, all-day boundaries, meeting links, unsafe URLs, upcoming limit, occurrence IDs, JSON output.")
    }
}
