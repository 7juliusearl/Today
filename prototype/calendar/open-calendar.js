// Reveal an invitation in Calendar. Never changes the event or submits an RSVP.
function run(argv) {
  const target = JSON.parse(argv[0]);
  const calendar = Application('Calendar');
  calendar.activate();
  if (target.uid) {
    for (const source of calendar.calendars.whose({name: target.calendar})()) {
      const matches = source.events.whose({uid: target.uid})();
      if (matches.length === 1) {
        calendar.show(matches[0]);
        return JSON.stringify({found: true});
      }
    }
  }
  calendar.viewCalendar({at: new Date(target.start)});
  return JSON.stringify({found: false});
}
