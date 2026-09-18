const DATA = window.DASHBOARD_DATA || { calendar: { events: [], upcoming: [], pendingInvites: [] }, slack: { connected: false, items: [] }, stickyNote: null };

const WEATHER_CODES = {
  0: "Clear sky", 1: "Mostly clear", 2: "Partly cloudy", 3: "Overcast",
  45: "Foggy", 48: "Foggy",
  51: "Light drizzle", 53: "Drizzle", 55: "Heavy drizzle",
  61: "Light rain", 63: "Rain", 65: "Heavy rain",
  66: "Freezing rain", 67: "Freezing rain",
  71: "Light snow", 73: "Snow", 75: "Heavy snow", 77: "Snow grains",
  80: "Light showers", 81: "Showers", 82: "Heavy showers",
  85: "Snow showers", 86: "Snow showers",
  95: "Thunderstorm", 96: "Thunderstorm", 99: "Thunderstorm",
};

function firstName() {
  return (DATA.userFirstName || "there");
}

const GREETINGS = {
  lateNight: ["Still up,", "Night owl mode,", "We're still up,", "Burning the midnight oil,"],
  morning: ["Let's lock in,", "New day, let's cook,", "Rise and grind,", "Big day energy,"],
  afternoon: ["Keep the momentum,", "Stay locked in,", "Still cooking,", "Let's keep it pushin',"],
  evening: ["Finish strong,", "Close it out strong,", "Wrap it up big,"],
};

function dayOfYear(date) {
  const start = new Date(date.getFullYear(), 0, 0);
  return Math.floor((date - start) / 86400000);
}

function timeGreeting(hour, seed) {
  let bucket;
  if (hour < 5) bucket = GREETINGS.lateNight;
  else if (hour < 12) bucket = GREETINGS.morning;
  else if (hour < 17) bucket = GREETINGS.afternoon;
  else bucket = GREETINGS.evening;
  return bucket[seed % bucket.length];
}

function renderGreetingAndClock() {
  const now = new Date();
  document.getElementById("greeting").textContent =
    `${timeGreeting(now.getHours(), dayOfYear(now))} ${firstName()}.`;

  const dateFmt = new Intl.DateTimeFormat("en-US", {
    weekday: "long", month: "long", day: "numeric",
  }).format(now);
  document.getElementById("eyebrow-date").textContent = dateFmt.toUpperCase();

  function tick() {
    const t = new Date();
    let h = t.getHours();
    const ampm = h >= 12 ? "PM" : "AM";
    h = h % 12 || 12;
    const m = String(t.getMinutes()).padStart(2, "0");
    document.getElementById("clock").textContent = `${h}:${m} ${ampm}`;
  }
  tick();
  setInterval(tick, 1000 * 15);
}

function formatEventTime(iso, allDay) {
  if (allDay) return "All day";
  const d = new Date(iso);
  return new Intl.DateTimeFormat("en-US", { hour: "numeric", minute: "2-digit" }).format(d);
}

function formatTimeRange(ev) {
  if (ev.allDay) return "All day";
  const start = formatEventTime(ev.start, false);
  if (!ev.end) return start;
  const end = formatEventTime(ev.end, false);
  return end && end !== start ? `${start} – ${end}` : start;
}

const RESPONSE_LABELS = {
  accepted: "Accepted",
  declined: "Declined",
  tentative: "Tentative",
  needsAction: "Awaiting response",
  organizer: "You're organizing",
};

function attendeeDotClass(status) {
  if (status === "accepted") return "is-accepted";
  if (status === "declined") return "is-declined";
  if (status === "tentative") return "is-tentative";
  return "is-pending";
}

function renderAttendees(ev) {
  const attendees = ev.attendees || [];
  if (attendees.length === 0) return "";

  const shown = attendees.slice(0, 6);
  const extra = (ev.attendeeCount || attendees.length) - shown.length;

  const items = shown.map((a) => `
    <li class="attendee">
      <span class="attendee-dot ${attendeeDotClass(a.responseStatus)}"></span>
      <span>${escapeHtml(a.name || a.email || "")}</span>
    </li>`).join("");

  return `
    <div class="event-detail-block">
      <p class="event-detail-label">Attendees${ev.attendeeCount ? ` (${ev.attendeeCount})` : ""}</p>
      <ul class="attendee-list">${items}</ul>
      ${extra > 0 ? `<p class="attendee-more">+${extra} more</p>` : ""}
    </div>`;
}

function eventTags(ev) {
  const tags = [];
  if (ev.calendar === "team") tags.push("Team");
  if (ev.recurring) tags.push("Recurring");
  if (ev.status === "tentative") tags.push("Tentative");
  if (ev.status === "cancelled") tags.push("Cancelled");
  return tags.map((t) => `<span class="event-tag">${t}</span>`).join("");
}

function hasExpandableDetails(ev) {
  return Boolean(
    ev.description || ev.meetingLink || ev.organizer ||
    (ev.attendees && ev.attendees.length > 0) || ev.htmlLink
  );
}

function renderEventDetailsBody(ev) {
  const parts = [];

  if (ev.description) {
    parts.push(`<div class="event-detail-block"><p class="event-description">${escapeHtml(ev.description).replace(/\n/g, "<br>")}</p></div>`);
  }

  if (ev.organizer) {
    parts.push(`<div class="event-detail-block"><p class="event-detail-label">Organizer</p><p class="event-detail-value">${escapeHtml(ev.organizer.name || ev.organizer.email)}</p></div>`);
  }

  if (ev.myResponseStatus && RESPONSE_LABELS[ev.myResponseStatus]) {
    parts.push(`<div class="event-detail-block"><p class="event-detail-label">Your RSVP</p><p class="event-detail-value">${RESPONSE_LABELS[ev.myResponseStatus]}</p></div>`);
  }

  parts.push(renderAttendees(ev));

  const links = [];
  if (ev.meetingLink) links.push(`<a class="event-link" href="${escapeHtml(ev.meetingLink)}" target="_blank" rel="noopener">Join meeting ↗</a>`);
  if (ev.htmlLink) links.push(`<a class="event-link event-link-subtle" href="${escapeHtml(normalizeCalendarLink(ev.htmlLink))}" target="_blank" rel="noopener">Open in Calendar ↗</a>`);
  if (links.length) parts.push(`<div class="event-links">${links.join("")}</div>`);

  return parts.join("");
}

function renderEventItem(ev, isNow) {
  const expandable = hasExpandableDetails(ev);
  const summaryInner = `
    <div class="event-time">${formatTimeRange(ev)}</div>
    <div class="event-main">
      <p class="event-title">${escapeHtml(ev.title)}${eventTags(ev)}</p>
      ${ev.location ? `<p class="event-location">${escapeHtml(ev.location)}</p>` : ""}
    </div>
    ${expandable ? '<span class="event-chevron" aria-hidden="true"></span>' : ""}
  `;

  if (!expandable) {
    return `<div class="event ${isNow ? "event-now" : ""}"><div class="event-summary event-summary-static">${summaryInner}</div></div>`;
  }

  return `
    <details class="event ${isNow ? "event-now" : ""}">
      <summary class="event-summary">${summaryInner}</summary>
      <div class="event-details">${renderEventDetailsBody(ev)}</div>
    </details>`;
}

function renderSchedule() {
  const list = document.getElementById("schedule-list");
  const events = (DATA.calendar && DATA.calendar.events) || [];

  if (events.length === 0) {
    list.innerHTML = `<p class="empty-state">Nothing on your calendar today. Enjoy the open space.</p>`;
    return;
  }

  const now = new Date();
  list.innerHTML = events.map((ev) => {
    const start = new Date(ev.start);
    const end = ev.end ? new Date(ev.end) : null;
    const isNow = !ev.allDay && start <= now && (!end || end >= now);
    return renderEventItem(ev, isNow);
  }).join("");
}

function formatDayHeading(dateStr) {
  const dateObj = new Date(`${dateStr}T12:00:00`);
  return new Intl.DateTimeFormat("en-US", {
    weekday: "long", month: "long", day: "numeric",
  }).format(dateObj).toUpperCase();
}

function renderUpcoming() {
  const section = document.getElementById("coming-up");
  const days = (DATA.calendar && DATA.calendar.upcoming) || [];

  if (days.length === 0) {
    section.hidden = true;
    return;
  }

  document.getElementById("coming-up-events").innerHTML = days.map((day) => `
    <div class="upcoming-day-group">
      <p class="upcoming-day-date">${escapeHtml(formatDayHeading(day.date))}</p>
      ${day.events.map((ev) => renderEventItem(ev, false)).join("")}
    </div>
  `).join("");
  section.hidden = false;
}

function formatEventDateTime(ev) {
  const dateObj = new Date(ev.start);
  const datePart = new Intl.DateTimeFormat("en-US", { month: "short", day: "numeric" }).format(dateObj);
  return ev.allDay ? datePart : `${datePart} · ${formatEventTime(ev.start, false)}`;
}

function renderPendingInvites() {
  const section = document.getElementById("pending-invites");
  const invites = (DATA.calendar && DATA.calendar.pendingInvites) || [];

  if (invites.length === 0) {
    section.hidden = true;
    return;
  }

  document.getElementById("pending-invites-list").innerHTML = invites.map((ev) => {
    const expandable = hasExpandableDetails(ev);
    const summaryInner = `
      <div class="invite-date">${formatEventDateTime(ev)}</div>
      <div class="event-main">
        <p class="event-title">${escapeHtml(ev.title)}<span class="event-tag">Awaiting response</span>${eventTags(ev)}</p>
        ${ev.location ? `<p class="event-location">${escapeHtml(ev.location)}</p>` : ""}
      </div>
      ${expandable ? '<span class="event-chevron" aria-hidden="true"></span>' : ""}
    `;
    if (!expandable) {
      return `<div class="event invite-row"><div class="event-summary event-summary-static">${summaryInner}</div></div>`;
    }
    return `
      <details class="event invite-row">
        <summary class="event-summary">${summaryInner}</summary>
        <div class="event-details">${renderEventDetailsBody(ev)}</div>
      </details>`;
  }).join("");
  section.hidden = false;
}

const DAY_NAMES = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

function renderWorkScheduleItem(item) {
  return `
    <div class="wsched-item">
      <div class="wsched-time">${escapeHtml(item.time)}</div>
      <div class="wsched-main">
        <p class="wsched-title">${escapeHtml(item.title)}</p>
        ${item.note ? `<p class="wsched-note">${escapeHtml(item.note)}</p>` : ""}
      </div>
    </div>`;
}

function todaysWorkSchedule() {
  const schedule = window.WORK_SCHEDULE;
  if (!schedule || !schedule.week) return { schedule: null, todayName: null, today: null };

  const todayName = DAY_NAMES[new Date().getDay()];
  const today = schedule.week.find((d) => d.day === todayName);
  return { schedule, todayName, today };
}

function renderWorkSchedule() {
  const list = document.getElementById("workschedule-list");
  const fullBody = document.getElementById("workschedule-full-body");
  const { schedule, todayName, today } = todaysWorkSchedule();

  if (!schedule) {
    list.innerHTML = `<p class="empty-state">No work schedule set up yet.</p>`;
    return;
  }

  document.getElementById("workschedule-eyebrow").textContent = `Work Schedule · ${todayName}`;

  if (!today || (today.items.length === 0 && !today.note)) {
    list.innerHTML = `<p class="empty-state">Nothing set for today.</p>`;
  } else if (today.items.length === 0) {
    list.innerHTML = `<p class="empty-state">${escapeHtml(today.note)}</p>`;
  } else {
    list.innerHTML = today.items.map(renderWorkScheduleItem).join("");
  }

  fullBody.innerHTML = schedule.week.map((d) => `
    <div class="wsched-day">
      <p class="wsched-day-name">${escapeHtml(d.day)}</p>
      <div class="wsched-day-items">
        ${d.items.length > 0
          ? d.items.map(renderWorkScheduleItem).join("")
          : `<p class="empty-state">${escapeHtml(d.note || "")}</p>`}
      </div>
    </div>
  `).join("");

  if (schedule.officeHours || schedule.editingRhythm) {
    const notes = [schedule.officeHours, schedule.editingRhythm].filter(Boolean);
    fullBody.innerHTML += `
      <div class="workschedule-notes">
        ${notes.map((n) => `<p>${escapeHtml(n)}</p>`).join("")}
      </div>`;
  }
}

function renderHeroRhythm() {
  const widget = document.getElementById("hero-rhythm");
  const list = document.getElementById("hero-rhythm-list");
  const { schedule, todayName, today } = todaysWorkSchedule();

  if (!schedule || !today) {
    widget.hidden = true;
    return;
  }

  document.getElementById("hero-rhythm-eyebrow").textContent = `${todayName}’s Rhythm`;

  if (today.items.length > 0) {
    list.innerHTML = today.items.slice(0, 3).map((item) => `
      <div class="hero-rhythm-item">
        <span class="hero-rhythm-time">${escapeHtml(item.time)}</span>
        <span class="hero-rhythm-title">${escapeHtml(item.title)}</span>
      </div>`).join("");
  } else if (today.short || today.note) {
    list.innerHTML = `<div class="hero-rhythm-item hero-rhythm-item-solo">
      <span class="hero-rhythm-title">${escapeHtml(today.short || today.note)}</span>
    </div>`;
  } else {
    widget.hidden = true;
    return;
  }

  widget.hidden = false;
}

function renderOnboardingPlan() {
  const plan = window.ONBOARDING_PLAN;
  const card = document.querySelector(".bento-plan");
  if (!plan || !plan.startDate || !plan.phases) {
    if (card) card.hidden = true;
    return;
  }

  const start = new Date(`${plan.startDate}T00:00:00`);
  const now = new Date();
  const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const daysElapsed = Math.floor((startOfToday - start) / 86400000) + 1;
  const totalDays = plan.totalDays;
  const dayDisplay = Math.min(Math.max(daysElapsed, 1), totalDays);

  const phaseIndex = plan.phases.findIndex((p) => daysElapsed <= p.days);
  const isComplete = phaseIndex === -1;
  const currentPhase = isComplete ? null : plan.phases[phaseIndex];

  document.getElementById("plan-eyebrow").textContent = isComplete
    ? "Onboarding · Complete"
    : `Onboarding · Day ${dayDisplay} of ${totalDays}`;
  document.getElementById("plan-phase-title").textContent = isComplete
    ? "Fully ramped"
    : currentPhase.title;

  const progressPercent = Math.min(Math.max((daysElapsed / totalDays) * 100, 0), 100);
  document.getElementById("plan-progress-fill").style.width = `${progressPercent}%`;

  document.getElementById("plan-phase-labels").innerHTML = plan.phases.map((p, i) => {
    const cls = isComplete || i < phaseIndex ? "is-done" : i === phaseIndex ? "is-active" : "";
    return `<span class="plan-phase-label ${cls}">${p.days}d · ${escapeHtml(p.title)}</span>`;
  }).join("");

  const teamBlock = plan.team && plan.team.length ? `
    <div class="plan-phase-block">
      <p class="wsched-day-name">Your Team</p>
      <ul class="plan-team-list">
        ${plan.team.map((person) => `<li>${escapeHtml(person)}</li>`).join("")}
      </ul>
    </div>` : "";

  const phaseBlocks = plan.phases.map((p, i) => {
    const rangeStart = i === 0 ? 1 : plan.phases[i - 1].days + 1;
    const isCurrent = !isComplete && i === phaseIndex;
    return `
      <div class="plan-phase-block ${isCurrent ? "is-current" : ""}">
        <p class="wsched-day-name">Days ${rangeStart}–${p.days} · ${escapeHtml(p.title)}${isCurrent ? '<span class="plan-current-tag">Now</span>' : ""}</p>
        <ul class="plan-items">
          ${p.items.map((it) => `<li>${escapeHtml(it)}</li>`).join("")}
        </ul>
      </div>`;
  }).join("");

  const goalBlock = plan.goal ? `<div class="workschedule-notes"><p>${escapeHtml(plan.goal)}</p></div>` : "";

  document.getElementById("plan-full-body").innerHTML = teamBlock + phaseBlocks + goalBlock;
}

function renderSlack() {
  const list = document.getElementById("slack-list");
  const slack = DATA.slack || { connected: false, items: [] };

  if (!slack.connected) {
    list.innerHTML = `<p class="slack-connect-cta">Slack isn't connected yet. Once it is, unread channels and threads will show up here automatically each morning.</p>`;
    return;
  }

  const items = slack.items || [];
  if (items.length === 0) {
    list.innerHTML = `<p class="empty-state">Nothing new since your last refresh.</p>`;
    return;
  }

  list.innerHTML = items.map((it) => `
    <div class="slack-item">
      <div class="slack-item-head">
        <span class="slack-channel">${escapeHtml(it.channel)}</span>
        <span class="slack-count">${it.unreadCount ? it.unreadCount + " new" : ""}</span>
      </div>
      <p class="slack-preview">${escapeHtml(it.preview || "")}</p>
    </div>
  `).join("");
}

function normalizeCalendarLink(url) {
  try {
    return url.replace("https://www.google.com/calendar/", "https://calendar.google.com/calendar/");
  } catch {
    return url;
  }
}

function escapeHtml(str) {
  const div = document.createElement("div");
  div.textContent = str;
  return div.innerHTML;
}

function renderFooter() {
  const footer = document.getElementById("updated-at");
  if (DATA.generatedAt) {
    const d = new Date(DATA.generatedAt);
    const fmt = new Intl.DateTimeFormat("en-US", {
      month: "short", day: "numeric", hour: "numeric", minute: "2-digit",
    }).format(d);
    footer.textContent = `Updated ${fmt}`;
  } else {
    footer.textContent = "Dashboard";
  }
}

async function loadWeather(lat, lon) {
  const url = `https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&current=temperature_2m,weather_code&daily=temperature_2m_max,temperature_2m_min&temperature_unit=fahrenheit&timezone=auto`;
  const res = await fetch(url);
  const json = await res.json();

  const temp = Math.round(json.current.temperature_2m);
  const code = json.current.weather_code;
  const desc = WEATHER_CODES[code] || "—";

  document.getElementById("weather-temp").textContent = `${temp}°`;
  document.getElementById("weather-desc").textContent = desc;
}

function initWeather() {
  if (!navigator.geolocation) {
    document.getElementById("weather-desc").textContent = "Location unavailable";
    return;
  }
  navigator.geolocation.getCurrentPosition(
    (pos) => loadWeather(pos.coords.latitude, pos.coords.longitude),
    () => {
      document.getElementById("weather-desc").textContent = "Enable location for weather";
    },
    { timeout: 8000 }
  );
}

function renderVerse() {
  const verse = DATA.verse;
  const refEl = document.getElementById("verse-reference");
  const textEl = document.getElementById("verse-text");
  const versionEl = document.getElementById("verse-version");

  if (!verse || !verse.text) {
    refEl.textContent = "Verse of the Day";
    textEl.textContent = "Check back tomorrow morning for today's verse.";
    versionEl.textContent = "";
    return;
  }

  refEl.textContent = verse.reference || "";
  textEl.textContent = verse.text;
  versionEl.textContent = verse.version || "";
}

function initThemeToggle() {
  const root = document.documentElement;
  const btn = document.getElementById("theme-toggle");
  const label = document.getElementById("theme-toggle-label");

  let stored = null;
  try { stored = localStorage.getItem("dashboard-theme"); } catch {}

  function apply(theme) {
    if (theme) root.setAttribute("data-theme", theme);
    else root.removeAttribute("data-theme");
    const isDark = theme
      ? theme === "dark"
      : window.matchMedia("(prefers-color-scheme: dark)").matches;
    btn.setAttribute("aria-pressed", String(isDark));
    label.textContent = isDark ? "Dark" : "Light";
  }

  apply(stored);

  btn.addEventListener("click", () => {
    const currentlyDark = btn.getAttribute("aria-pressed") === "true";
    const next = currentlyDark ? "light" : "dark";
    apply(next);
    try { localStorage.setItem("dashboard-theme", next); } catch {}
  });
}

function initRefreshButton() {
  const btn = document.getElementById("refresh-btn");
  btn.addEventListener("click", () => {
    btn.disabled = true;
    btn.classList.add("is-spinning");
    setTimeout(() => window.location.reload(), 400);
  });
}

function initAutoRefresh() {
  // Data refreshes every 30 min (8am-5pm weekdays) — reload periodically
  // so an already-open tab picks that up without anyone clicking refresh.
  setInterval(() => window.location.reload(), 10 * 60 * 1000);
}

function renderStickyNote() {
  const note = DATA.stickyNote;
  const el = document.getElementById("sticky-note");
  if (!note || !note.text) {
    el.hidden = true;
    return;
  }

  const noteId = `${note.ts || ""}-${note.text.length}`;
  let dismissedId = null;
  try { dismissedId = localStorage.getItem("dashboard-dismissed-note"); } catch {}
  if (dismissedId === noteId) {
    el.hidden = true;
    return;
  }

  let hash = 0;
  for (let i = 0; i < noteId.length; i++) hash = (hash * 31 + noteId.charCodeAt(i)) >>> 0;
  const positionCount = 5;
  el.className = `sticky-note sticky-pos-${hash % positionCount}`;

  document.getElementById("sticky-note-text").textContent = note.text;
  document.getElementById("sticky-note-from").textContent = note.from ? `— ${note.from}` : "";
  el.hidden = false;

  document.getElementById("sticky-note-dismiss").onclick = () => {
    el.hidden = true;
    try { localStorage.setItem("dashboard-dismissed-note", noteId); } catch {}
  };
}

initThemeToggle();
initRefreshButton();
initAutoRefresh();
renderGreetingAndClock();
renderSchedule();
renderUpcoming();
renderPendingInvites();
renderWorkSchedule();
renderHeroRhythm();
renderOnboardingPlan();
renderSlack();
renderVerse();
renderStickyNote();
renderFooter();
initWeather();
