import Foundation
import JavaScriptCore

@main struct HappeningNowTests {
    static func main() throws {
        let context = JSContext()!
        var errors: [String] = []
        context.exceptionHandler = { _, error in errors.append(error?.toString() ?? "JavaScript error") }
        let source = try String(contentsOfFile: "app.js", encoding: .utf8)
        let start = source.range(of: "function happeningNowState(")!.lowerBound
        let end = source.range(of: "function renderHappeningNow(")!.lowerBound
        context.evaluateScript(String(source[start..<end]))
        context.evaluateScript("""
        function check(condition, message) { if (!condition) throw Error(message); }
        const now = new Date('2026-09-20T14:00:00Z');
        const event = (id, start, end, extra = {}) => ({id, start, end, ...extra});
        const active = event('active', '2026-09-20T13:30:00Z', '2026-09-20T14:30:00Z');
        const begins = event('begins', '2026-09-20T14:00:00Z', '2026-09-20T14:15:00Z');
        const ended = event('ended', '2026-09-20T13:00:00Z', '2026-09-20T14:00:00Z');
        const next = event('next', '2026-09-20T15:00:00Z', '2026-09-20T16:00:00Z');
        const state = happeningNowState([active, begins, ended, next,
          {...active, id: 'all-day', allDay: true},
          {...active, id: 'declined', myResponseStatus: 'declined'},
          {...active, id: 'cancelled', status: 'cancelled'},
          {...active, id: 'invalid', end: 'invalid'},
          {...active, id: 'zero', end: active.start}], now);
        check(state.active.map(e => e.id).join(',') === 'begins,active', 'Include overlapping events, inclusive start and exclusive end');
        check(state.next.id === 'next', 'Select the next timed event');
        check(state.soon.length === 1 && state.soon[0].id === 'next', 'An event enters the buffer at exactly one hour, alongside active events');
        check(happeningNowState([next], new Date(now.getTime() - 1)).soon.length === 0, 'Do not show countdown before one hour');
        const inMinutes = minutes => new Date(now.getTime() + minutes * 60000).toISOString();
        check(eventCountdown(inMinutes(60), now) === 'Happening in 60 mins', 'Start at 60');
        check(eventCountdown(inMinutes(55.1), now) === 'Happening in 56 mins', 'Round partial minutes up');
        check(eventCountdown(inMinutes(55), now) === 'Happening in 55 mins', 'Step to 55');
        check(eventCountdown(inMinutes(10), now) === 'Happening in 10 mins', 'Step to 10');
        check(eventCountdown(inMinutes(5), now) === 'Happening in 5 mins', 'Five actual minutes');
        check(eventCountdown(inMinutes(1), now) === 'Happening in 1 min', 'Singular minute before start');
        check(eventCountdown(inMinutes(4), now) === 'Happening in 4 mins', 'Count every minute');
        check(eventCountdown(inMinutes(0.2), now) === 'Happening in 1 min', 'Do not show zero before start');
        check(eventCountdown(inMinutes(0), now) === null, 'Countdown ends at start');
        check(eventCountdown(inMinutes(61), now) === null, 'No countdown outside the buffer');
        const started = happeningNowState([next], new Date(next.start));
        check(started.soon.length === 0 && started.active.length === 1, 'Move from soon to active without duplicates');
        check(happeningNowState([active], new Date(active.end)).active.length === 0, 'Remove events when they end');
        check(happeningNowState([], now).active.length === 0, 'Handle an empty calendar');
        """)
        context.setObject(source, forKeyedSubscript: "source" as NSString)
        context.evaluateScript("new Function(source)")
        context.evaluateScript("""
        eval(source.slice(source.indexOf('function scheduleEventEnded'), source.indexOf('function updateScheduleTime')));
        check(scheduleEventEnded(ended, now), 'Fade at exact end time');
        check(!scheduleEventEnded(active, now), 'Keep active events visible');
        check(!scheduleEventEnded(next, now), 'Keep future events visible');
        check(!scheduleEventEnded({...ended, allDay:true}, now), 'Keep all-day items visible');
        check(!scheduleEventEnded({...ended, end:null}, now), 'Do not guess missing end times');
        check(!scheduleEventEnded({...ended, end:'invalid'}, now), 'Do not fade invalid end times');
        """)

        assert(errors.isEmpty, errors.joined(separator: "\n"))
        print("PASS: one-hour buffer, one-minute countdown steps, soon-to-active transition, overlapping meetings, start/end boundaries, exclusions, JavaScript syntax.")
    }
}
