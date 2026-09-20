// EXAMPLE — copy this to dashboard.js to see the dashboard populated before
// your own scheduled task has run for the first time. The real dashboard.js
// is gitignored and rewritten automatically every weekday morning.
window.DASHBOARD_DATA = {
  generatedAt: "2026-01-05T06:30:00-05:00",
  userFirstName: "Alex",
  calendar: {
    events: [
      {
        id: "example-1",
        title: "Team standup",
        start: "2026-01-05T09:00:00-05:00",
        end: "2026-01-05T09:15:00-05:00",
        allDay: false,
        location: "Conference Room A",
        calendar: "personal",
        description: "Quick daily sync.",
        meetingLink: "https://meet.google.com/example",
        organizer: { name: "Jordan Lee", email: "jordan@example.com" },
        attendees: [
          { name: "Jordan Lee", email: "jordan@example.com", responseStatus: "accepted" },
          { name: "Sam Rivera", email: "sam@example.com", responseStatus: "needsAction" }
        ],
        attendeeCount: 2,
        myResponseStatus: "accepted",
        status: "confirmed",
        recurring: true,
        htmlLink: "https://calendar.google.com/calendar/event?eid=example"
      }
    ],
    upcoming: [
      {
        date: "2026-01-08",
        events: [
          {
            id: "example-2",
            title: "Quarterly planning",
            start: "2026-01-08T00:00:00-05:00",
            end: "2026-01-09T00:00:00-05:00",
            allDay: true,
            location: null,
            calendar: "team",
            description: null,
            meetingLink: null,
            organizer: { name: "Team Calendar", email: "team@example.com" },
            attendees: [],
            attendeeCount: 0,
            myResponseStatus: null,
            status: "confirmed",
            recurring: false,
            htmlLink: "https://calendar.google.com/calendar/event?eid=example2"
          }
        ]
      }
    ],
    pendingInvites: [
      {
        id: "example-3",
        title: "Design review",
        start: "2026-01-09T14:00:00-05:00",
        end: "2026-01-09T15:00:00-05:00",
        allDay: false,
        location: null,
        calendar: "personal",
        description: null,
        meetingLink: "https://meet.google.com/example2",
        organizer: { name: "Jordan Lee", email: "jordan@example.com" },
        attendees: [
          { name: "Jordan Lee", email: "jordan@example.com", responseStatus: "accepted" }
        ],
        attendeeCount: 1,
        myResponseStatus: "needsAction",
        status: "confirmed",
        recurring: false,
        htmlLink: "https://calendar.google.com/calendar/event?eid=example3"
      }
    ]
  },
  slack: {
    connected: true,
    items: [
      {
        channel: "#general",
        preview: "Reminder: the office is closed on Monday for the holiday!",
        unreadCount: 3,
        permalink: "https://example.slack.com/archives/C0EXAMPLE/p1234567890000100"
      }
    ]
  },
  stickyNotes: [
    {
      text: "Hey! Just wanted to say you're doing an awesome job settling in.",
      from: "Jordan",
      ts: "2026-01-05T09:00:00-05:00"
    },
    {
      text: "Loved your idea in standup today — let's talk more tomorrow!",
      from: "Sam",
      ts: "2026-01-05T10:30:00-05:00"
    }
  ],
  verse: {
    text: "I can do all things through Christ who strengthens me.",
    reference: "Philippians 4:13",
    version: "NKJV"
  }
};
