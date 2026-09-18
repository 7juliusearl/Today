// EXAMPLE — optional. Copy to schedule.js and fill in your own weekly rhythm
// to populate the "Work Schedule" card and the header's "Today's Rhythm" widget.
// Hand-maintained; the daily refresh task never touches this file.
window.WORK_SCHEDULE = {
  officeHours: "In-office Monday–Thursday, 9 AM–5 PM",
  editingRhythm: "",
  week: [
    {
      day: "Monday",
      items: [
        { time: "9:00 AM", title: "Team sync", note: "Weekly planning" }
      ],
    },
    { day: "Tuesday", items: [] },
    { day: "Wednesday", items: [] },
    { day: "Thursday", items: [] },
    {
      day: "Friday",
      items: [],
      short: "Focus day — no meetings",
      note: "Focus day — no meetings scheduled.",
    },
    { day: "Saturday", items: [] },
    { day: "Sunday", items: [] },
  ],
};
