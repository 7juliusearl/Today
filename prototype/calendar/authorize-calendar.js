// Read-only permission check; never creates events or submits an RSVP.
function run() {
    Application('Calendar').calendars.name();
    return JSON.stringify({allowed: true});
}
