import Foundation
import EventKit

struct CalendarEvent: Encodable {
    let id: String
    let title: String
    let start: String
    let end: String
    let allDay: Bool
    let location: String?
    let calendar: String
    let description: String?
    let meetingLink: String?
    let organizer: Person?
    let attendees: [Person]
    let attendeeCount: Int
    let myResponseStatus: String?
    let status: String
    let recurring: Bool
    let htmlLink: String?
    struct Person: Encodable {
        let name: String?
        let email: String?
        let responseStatus: String?
    }
}

func response(_ participant: EKParticipant?) -> String? {
    guard let participant else { return nil }
    switch participant.participantStatus {
    case .accepted: return "accepted"
    case .declined: return "declined"
    case .tentative: return "tentative"
    case .pending: return "needsAction"
    default: return nil
    }
}

func mappedEvent(_ event: EKEvent, primary: String?) -> CalendarEvent {
    let iso = ISO8601DateFormatter()
    func person(_ p: EKParticipant) -> CalendarEvent.Person {
        let url = p.url.absoluteString
        return .init(name: p.name, email: url.hasPrefix("mailto:") ? String(url.dropFirst(7)) : nil,
                     responseStatus: response(p))
    }
    let participants = (event.attendees ?? []).filter { $0.participantType != .room && $0.participantType != .resource }
    let me = event.attendees?.first(where: { $0.isCurrentUser })
    let notes = event.notes ?? ""
    let candidates = [event.url?.absoluteString ?? "", event.location ?? "", notes].joined(separator: "\n")
    let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    let links = detector?.matches(in: candidates, range: NSRange(candidates.startIndex..., in: candidates)).compactMap { $0.url } ?? []
    let meeting = links.first { url in
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "meet.google.com" || host == "zoom.us" || host.hasSuffix(".zoom.us") || host == "teams.microsoft.com"
    }
    let safeURL = event.url.flatMap { ["https", "http"].contains($0.scheme?.lowercased() ?? "") ? $0.absoluteString : nil }
    return CalendarEvent(
        id: (event.eventIdentifier ?? event.calendarItemIdentifier) + "@" + iso.string(from: event.startDate),
        title: event.title ?? "Untitled event", start: iso.string(from: event.startDate), end: iso.string(from: event.endDate),
        allDay: event.isAllDay, location: event.location, calendar: event.calendar.calendarIdentifier == primary ? "personal" : "team",
        description: String(notes.prefix(600)), meetingLink: meeting?.absoluteString,
        organizer: event.organizer.map(person), attendees: Array(participants.prefix(15)).map(person), attendeeCount: participants.count,
        myResponseStatus: event.organizer?.isCurrentUser == true ? "organizer" : response(me),
        // occurrenceDate can also be populated for one-off events; it is not a recurrence flag.
        status: event.status == .canceled ? "cancelled" : "confirmed", recurring: event.hasRecurrenceRules || event.isDetached,
        htmlLink: safeURL)
}

struct CalendarPayload: Encodable {
    struct Day: Encodable { let date: String; let events: [CalendarEvent] }
    let events: [CalendarEvent]
    let upcoming: [Day]
    let pendingInvites: [CalendarEvent]
}

func calendarPayload(_ events: [EKEvent], now: Date, primary: String?) -> CalendarPayload {
    let cal = Calendar.current
    let today = cal.startOfDay(for: now)
    let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
    let last = cal.date(byAdding: .day, value: 15, to: today)!
    let valid = events.filter {
        $0.status != .canceled && response($0.attendees?.first(where: { $0.isCurrentUser })) != "declined"
    }.sorted { $0.startDate < $1.startDate }
    func overlaps(_ event: EKEvent, _ start: Date, _ end: Date) -> Bool {
        event.startDate < end && (event.endDate > start || (event.startDate == event.endDate && event.startDate >= start))
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = cal.timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    var days: [CalendarPayload.Day] = []
    var date = tomorrow
    while date < last && days.count < 5 {
        let next = cal.date(byAdding: .day, value: 1, to: date)!
        let items = valid.filter { overlaps($0, date, next) }.map { mappedEvent($0, primary: primary) }
        if !items.isEmpty { days.append(.init(date: formatter.string(from: date), events: items)) }
        date = next
    }
    var seenSeries = Set<String>()
    let pending = valid.filter { event in
        guard event.endDate > now,
              response(event.attendees?.first(where: { $0.isCurrentUser })) == "needsAction" else { return false }
        // Present the nearest occurrence once for a repeating invitation.
        let key = event.calendar.calendarIdentifier + "|" + event.calendarItemIdentifier
        return seenSeries.insert(key).inserted
    }.map { mappedEvent($0, primary: primary) }
    return .init(events: valid.filter { overlaps($0, today, tomorrow) }.map { mappedEvent($0, primary: primary) },
                 upcoming: days, pendingInvites: Array(pending.prefix(30)))
}
