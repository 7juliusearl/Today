let DATA = window.DASHBOARD_DATA || { calendar: { events: [], upcoming: [], pendingInvites: [] }, slack: { connected: false, items: [] }, stickyNotes: [] };

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

let greetingClockTimer;
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
    renderHappeningNow(t);
    updateScheduleTime(t);
  }
  tick();
  clearInterval(greetingClockTimer);
  greetingClockTimer = setInterval(tick, 1000 * 15);
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

function happeningNowState(events, now = new Date()) {
  const timed = events.filter(ev => !ev.allDay && ev.status !== "cancelled" &&
    ev.status !== "canceled" && ev.myResponseStatus !== "declined" &&
    Number.isFinite(Date.parse(ev.start)) && Number.isFinite(Date.parse(ev.end)) &&
    Date.parse(ev.end) > Date.parse(ev.start));
  return {
    active: timed.filter(ev => Date.parse(ev.start) <= now.getTime() && now.getTime() < Date.parse(ev.end))
      .sort((a, b) => Date.parse(a.end) - Date.parse(b.end)),
    soon: timed.filter(ev => Date.parse(ev.start) > now.getTime() && Date.parse(ev.start) - now.getTime() <= 60 * 60000)
      .sort((a, b) => Date.parse(a.start) - Date.parse(b.start)),
    next: timed.filter(ev => Date.parse(ev.start) > now.getTime())
      .sort((a, b) => Date.parse(a.start) - Date.parse(b.start))[0]
  };
}

function eventCountdown(start, now) {
  const remaining = Date.parse(start) - now.getTime();
  if (remaining <= 0 || remaining > 60 * 60000) return null;
  const minutes = Math.ceil(remaining / 60000);
  return `Happening in ${minutes} ${minutes === 1 ? "min" : "mins"}`;
}

function renderHappeningNow(now = new Date()) {
  const container = document.getElementById("happening-now-content");
  if (!container) return;
  const calendar = DATA.calendar || {};
  const events = [...(calendar.events || []), ...(calendar.upcoming || []).flatMap(day => day.events || [])];
  const unique = Array.from(new Map(events.map(ev => [`${ev.id || ev.title}|${ev.start}`, ev])).values());
  const { active, soon, next } = happeningNowState(unique, now);
  container.closest(".happening-now")?.classList.toggle("has-countdown", soon.length > 0);
  document.getElementById("happening-now-title").textContent = !active.length && soon.length ? "Happening soon" : "Happening now";
  let markup;
  if (!active.length && !soon.length) {
    markup = `<p class="now-empty">Nothing scheduled right now.</p>${next
      ? `<p class="now-next">Next: <strong>${escapeHtml(next.title)}</strong> · ${escapeHtml(formatEventDateTime(next))}</p>` : ""}`;
  } else {
    markup = [...active, ...soon].map(ev => {
      const start = Date.parse(ev.start);
      const end = Date.parse(ev.end);
      const countdown = eventCountdown(ev.start, now);
      const startingMinutes = Math.max(1, Math.ceil((start - now.getTime()) / 60000));
      const remaining = Math.max(1, Math.ceil((end - now.getTime()) / 60000));
      const elapsed = Math.max(0, Math.min(100, Math.round((now.getTime() - start) / (end - start) * 100)));
      let join = "";
      try {
        const url = new URL(ev.meetingLink);
        if (url.protocol === "https:" || url.protocol === "http:") {
          join = `<a class="now-join" href="${escapeHtml(url.href)}" target="_blank" rel="noopener">Join meeting ↗</a>`;
        }
      } catch {}
      return `<div class="now-event${countdown ? " now-event-soon" : ""}">
        <div class="now-event-top"><div class="now-event-info">
          <p class="now-live"><span aria-hidden="true">${countdown ? "◷" : "●"}</span> ${countdown ? "Up next" : "In progress"}</p>
          <h3>${escapeHtml(ev.title)}</h3>
          <p class="now-meta">${escapeHtml(formatTimeRange(ev))}${ev.location ? ` · ${escapeHtml(ev.location)}` : ""}</p>
          ${join ? `<div class="now-actions">${join}</div>` : ""}
        </div><div class="now-countdown" aria-label="${countdown ? `Starting within ${startingMinutes} minutes` : `${remaining} minutes remaining`}">
          <span class="now-countdown-label">${countdown ? "Starting in" : "Time left"}</span>
          <span class="now-countdown-number">${countdown ? startingMinutes : remaining}</span>
          <span class="now-countdown-unit">${(countdown ? startingMinutes : remaining) === 1 ? "minute" : "minutes"}</span>
        </div></div>
        ${countdown ? "" : `<div class="now-progress" role="progressbar" aria-label="Event elapsed" aria-valuemin="0" aria-valuemax="100" aria-valuenow="${elapsed}"><span style="width:${elapsed}%"></span></div>`}
      </div>`;
    }).join("");
  }
  if (container.innerHTML !== markup) container.innerHTML = markup;
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
    <details class="event ${isNow ? "event-now" : ""}" data-event-key="${escapeHtml(`${ev.id || ev.title}|${ev.start}`)}">
      <summary class="event-summary">${summaryInner}</summary>
      <div class="event-details">${renderEventDetailsBody(ev)}</div>
    </details>`;
}

function scheduleEventEnded(event, now) {
  const end = Date.parse(event.end);
  const start = Date.parse(event.start);
  return !event.allDay && Number.isFinite(end) && Number.isFinite(start) && end >= start && end <= now.getTime();
}

function updateScheduleTime(now = new Date()) {
  const list = document.getElementById("schedule-list");
  if (!list) return;
  const top = list.scrollTop;
  const pageY = window.scrollY;
  list.querySelectorAll(".schedule-event").forEach(row => {
    const event = { start: row.dataset.start, end: row.dataset.end, allDay: row.dataset.allDay === "true" };
    const ended = scheduleEventEnded(event, now);
    row.querySelector(".event")?.classList.toggle("event-now", !ended && !event.allDay && Date.parse(event.start) <= now.getTime());
    if (ended && !row.classList.contains("schedule-event-ended")) {
      row.classList.add("schedule-event-ended");
      list.append(row);
    }
  });
  list.scrollTop = top;
  if (window.scrollY !== pageY) window.scrollTo({ top: pageY, behavior: "instant" });
}

function renderSchedule() {
  const list = document.getElementById("schedule-list");
  const events = (DATA.calendar && DATA.calendar.events) || [];

  const date = new Date();
  const today = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
  const tasks = (DATA.asana?.tasks || []).filter(task => task.dueDate === today);
  if (events.length === 0 && tasks.length === 0) {
    list.innerHTML = `<p class="empty-state">Nothing on your calendar today. Enjoy the open space.</p>`;
    return;
  }

  const now = new Date();
  list.innerHTML = events.map((ev) => {
    const start = new Date(ev.start);
    const end = ev.end ? new Date(ev.end) : null;
    const isNow = !ev.allDay && start <= now && (!end || end >= now);
    return `<div class="schedule-event" data-start="${escapeHtml(ev.start || "")}" data-end="${escapeHtml(ev.end || "")}" data-all-day="${!!ev.allDay}">${renderEventItem(ev, isNow)}</div>`;
  }).join("");
  if (tasks.length) {
    const section = document.createElement("section");
    section.className = "schedule-asana";
    section.setAttribute("aria-label", "Asana tasks due today");
    const heading = document.createElement("p");
    heading.className = "upcoming-day-date";
    heading.textContent = "Asana · Due today";
    section.append(heading);
    for (const task of tasks) {
      const url = asanaDesktopLink(task.url);
      const row = document.createElement("div");
      row.className = "asana-task";
      const title = document.createElement(url ? "a" : "p");
      title.className = "asana-task-title";
      title.textContent = task.title + (url ? " ↗" : "");
      if (url) { title.href = url; title.target = "_blank"; title.rel = "noopener"; }
      row.append(title);
      if (task.brief) {
        const button = document.createElement("button");
        button.type = "button"; button.className = "asana-brief-button";
        button.textContent = "View brief";
        button.addEventListener("click", () => showAsanaBrief(task));
        row.append(button);
      }
      if (!task.brief && typeof task.description === "string" && task.description.trim()) {
        const details = document.createElement("details");
        const summary = document.createElement("summary");
        summary.textContent = "Task details";
        const description = document.createElement("p");
        description.className = "asana-task-description";
        description.textContent = task.description.trim();
        details.append(summary, description);
        row.append(details);
      }
      section.append(row);
    }
    list.append(section);
  }
  updateScheduleTime(now);
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

  document.getElementById("coming-up-events").innerHTML = days.map((day, index) => `
    <div class="upcoming-day-group" style="--day-glow: ${days.length === 1 ? 1 : 1 - index / (days.length - 1)}">
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

  if (window.LOCAL_CALENDAR_PROTOTYPE) {
    const list = document.getElementById("pending-invites-list");
    list.replaceChildren();
    for (const ev of invites) {
      const row = document.createElement("div");
      row.className = "invite-mail-row";
      const title = document.createElement("h3");
      title.textContent = ev.title;
      const meta = document.createElement("p");
      meta.className = "invite-mail-meta";
      meta.textContent = `${formatEventDateTime(ev)} · Awaiting response`;
      const action = document.createElement("button");
      action.className = "invite-mail-action";
      action.type = "button";
      const statusText = DATA.calendarActions?.[ev.id];
      action.textContent = window.TODAY_COMPANION ? "Respond on your Mac" : "Respond in Calendar ↗";
      action.disabled = window.TODAY_COMPANION || statusText === "Opening Calendar…";
      action.addEventListener("click", () => window.webkit.messageHandlers.respondInCalendar.postMessage(ev.id));
      row.append(title, meta, action);
      if (statusText) {
        const status = document.createElement("p");
        status.className = "invite-mail-meta";
        status.textContent = statusText;
        row.append(status);
      }
      list.append(row);
    }
    section.hidden = false;
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

function isCoworkerDashboard() {
  return document.documentElement.dataset.edition === "coworker";
}

function todaysWorkSchedule() {
  if (isCoworkerDashboard()) return { schedule: null, todayName: null, today: null };
  const schedule = window.WORK_SCHEDULE;
  if (!schedule || !schedule.week) return { schedule: null, todayName: null, today: null };

  const todayName = DAY_NAMES[new Date().getDay()];
  const today = schedule.week.find((d) => d.day === todayName);
  return { schedule, todayName, today };
}

function renderWorkSchedule() {
  const fullBody = document.getElementById("workschedule-full-body");
  const { schedule } = todaysWorkSchedule();
  if (!fullBody) return;
  if (!schedule) {
    fullBody.innerHTML = '<p class="empty-state">No work schedule set up yet.</p>';
    return;
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

  if (!schedule) {
    widget.hidden = true;
    return;
  }

  document.getElementById("hero-rhythm-eyebrow").textContent = `${todayName}’s Rhythm`;

  if (today?.items?.length > 0) {
    list.innerHTML = today.items.slice(0, 3).map((item) => `
      <div class="hero-rhythm-item">
        <span class="hero-rhythm-time">${escapeHtml(item.time)}</span>
        <span class="hero-rhythm-title">${escapeHtml(item.title)}</span>
      </div>`).join("");
  } else if (today?.short || today?.note) {
    list.innerHTML = `<div class="hero-rhythm-item hero-rhythm-item-solo">
      <span class="hero-rhythm-title">${escapeHtml(today.short || today.note)}</span>
    </div>`;
  } else {
    list.innerHTML = '<span class="hero-rhythm-title">No regular plans today.</span>';
  }

  widget.hidden = false;
}

function initRhythmWeekDialog() {
  const dialog = document.getElementById("rhythm-week-dialog");
  const link = document.getElementById("hero-week-link");
  if (!dialog || !link) return;
  link.addEventListener("click", () => {
    renderWorkSchedule();
    const body = document.getElementById("rhythm-week-body");
    if (!dialog.open) dialog.showModal();
    body.scrollTop = 0;
  });
  document.getElementById("rhythm-week-close").addEventListener("click", () => dialog.close());
  dialog.addEventListener("click", event => {
    const bounds = dialog.getBoundingClientRect();
    if (event.target === dialog && (event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom)) dialog.close();
  });
}

function focusRemaining(state, now = Date.now()) {
  return state.mode === "running" ? Math.max(0, state.deadline - now) : state.remaining;
}

// Layout follows each section's role instead of giving every card equal weight.
function initQuickLinks() {
  const grid = document.querySelector(".quicklinks-grid");
  const dialog = document.getElementById("quicklinks-dialog");
  if (!grid || !dialog) return;
  const key = "today-quick-links";
  const defaults = [...grid.querySelectorAll("a")].map(a => ({name: a.querySelector(".quicklink-label").textContent, url: a.href, icon: a.querySelector("img")?.src}));
  function normalize(value) {
    const raw = value.trim();
    if (!raw) throw Error("Enter a website address for each link.");
    const url = new URL(/^[a-z][a-z\d+.-]*:/i.test(raw) ? raw : `https://${raw}`);
    if (!["https:", "http:"].includes(url.protocol) || !url.hostname || url.username || url.password) throw Error("Use an http or https website address without a username or password.");
    return url.href;
  }
  let links = defaults;
  try {
    const saved = JSON.parse(localStorage.getItem(key));
    if (Array.isArray(saved) && saved.every(link => typeof link.name === "string" && link.name.trim() && typeof link.url === "string")) {
      links = saved.map(link => ({name: link.name, url: normalize(link.url)}));
    }
  } catch (_) { /* Keep working defaults if stored data is unreadable. */ }
  function render() {
    grid.replaceChildren();
    for (const link of links) {
      const a = document.createElement("a");
      a.className = "quicklink"; a.href = link.url; a.target = "_blank"; a.rel = "noopener noreferrer";
      const icon = document.createElement("span"); icon.className = "quicklink-icon";
      const original = defaults.find(item => item.url === link.url);
      if (original?.icon) {
        const img = document.createElement("img"); img.src = original.icon; img.alt = ""; img.loading = "lazy"; img.referrerPolicy = "no-referrer"; icon.append(img);
      } else { icon.textContent = link.name.trim().slice(0, 1).toUpperCase(); }
      const label = document.createElement("span"); label.className = "quicklink-label"; label.textContent = link.name;
      a.title = `${link.name} — ${link.url}`; a.append(icon, label); grid.append(a);
    }
    if (!links.length) { const empty = document.createElement("span"); empty.className = "quicklinks-empty"; empty.textContent = "Add your first link with Edit links."; grid.append(empty); }
  }
  const rows = document.getElementById("quicklinks-rows");
  const error = document.getElementById("quicklinks-error");
  function addRow(link = {name: "", url: ""}) {
    const row = document.createElement("div"); row.className = "quicklinks-row";
    for (const [field, title, placeholder] of [["name", "Name", "Project board"], ["url", "Website", "https://example.com"]]) {
      const label = document.createElement("label"); label.textContent = title;
      const input = document.createElement("input"); input.dataset.field = field; input.value = link[field]; input.placeholder = placeholder; input.type = "text";
      if (field === "url") { input.inputMode = "url"; input.autocapitalize = "off"; input.spellcheck = false; }
      label.append(input); row.append(label);
    }
    const remove = document.createElement("button"); remove.type = "button"; remove.className = "quicklinks-edit"; remove.textContent = "Remove";
    remove.addEventListener("click", () => { const next = row.nextElementSibling || row.previousElementSibling; row.remove(); (next?.querySelector("input") || document.getElementById("quicklinks-add")).focus(); });
    row.append(remove); rows.append(row); return row;
  }
  document.getElementById("quicklinks-edit").addEventListener("click", () => { rows.replaceChildren(); links.forEach(addRow); error.textContent = ""; dialog.showModal(); });
  document.getElementById("quicklinks-add").addEventListener("click", () => addRow().querySelector("input").focus());
  for (const id of ["quicklinks-close", "quicklinks-cancel"]) document.getElementById(id).addEventListener("click", () => dialog.close());
  dialog.addEventListener("click", e => { if (e.target === dialog && e.clientX >= 0) { const r = dialog.getBoundingClientRect(); if (e.clientX < r.left || e.clientX > r.right || e.clientY < r.top || e.clientY > r.bottom) dialog.close(); } });
  document.getElementById("quicklinks-save").addEventListener("click", () => {
    const next = [];
    for (const row of rows.children) {
      const name = row.querySelector('[data-field="name"]'), url = row.querySelector('[data-field="url"]');
      if (!name.value.trim()) { error.textContent = "Give each link a name, or remove the empty row."; name.focus(); return; }
      try { next.push({name: name.value.trim(), url: normalize(url.value)}); }
      catch (_) { error.textContent = "Enter a valid http or https website address for each link."; url.focus(); return; }
    }
    try { localStorage.setItem(key, JSON.stringify(next)); }
    catch (_) { error.textContent = "Your links couldn’t be saved. Please try again."; return; }
    links = next; render(); dialog.close();
  });
  render();
}

function arrangeDashboardSections(cards) {
  const page = document.querySelector(".page");
  const visible = new Map(cards);
  const mail = visible.get("mail");
  const links = visible.get("links");
  const headers = ["welcome", "now"].filter(id => visible.has(id));
  const lists = ["schedule", "upcoming"].filter(id => visible.has(id));
  const supporting = ["timer", "invites", "plan", "verse"].filter(id => visible.has(id));
  const hasLeft = headers.length + lists.length + supporting.length > 0;
  const leftWidth = mail && hasLeft ? 24 : 36;
  const rows = [];
  function place(card, column, span, row, rowSpan = 1) {
    card.style.setProperty("--dashboard-column", `${column} / span ${span}`);
    card.style.setProperty("--dashboard-row", `${row} / span ${rowSpan}`);
  }
  function row(ids, height) {
    if (!ids.length) return;
    rows.push(height);
    const width = leftWidth / ids.length;
    ids.forEach((id, i) => place(visible.get(id), i * width + 1, width, rows.length));
  }
  const countdown = visible.get("now")?.classList.contains("has-countdown");
  row(headers, lists.length || supporting.length ? (countdown ? "clamp(230px, 30vh, 310px)" : "clamp(175px, 23vh, 235px)") : "minmax(0, 1fr)");
  row(lists, "minmax(0, 1fr)");
  row(supporting, lists.length ? "clamp(155px, 22vh, 205px)" : "minmax(0, 1fr)");
  if (mail) {
    if (!rows.length) rows.push("minmax(0, 1fr)");
    place(mail, hasLeft ? 25 : 1, hasLeft ? 12 : 36, 1, rows.length);
  }
  if (links) { rows.push(hasLeft || mail ? "48px" : "minmax(0, 1fr)"); place(links, 1, 36, rows.length); }
  page.style.setProperty("--dashboard-template-rows", rows.join(" ") || "minmax(0, 1fr)");
  document.body.classList.toggle("dashboard-with-mail", !!mail && hasLeft);
}

function initDashboardSections() {
  const sections = [
    ["welcome", "Welcome, weather & rhythm", ".hero"], ["now", "Happening now", ".happening-now"],
    ["schedule", "Today’s schedule", ".bento-schedule"], ["mail", "Mail", ".bento-mail"],
    ["upcoming", "Coming up", ".bento-comingup"], ["invites", "Pending invitations", ".bento-invites"],
    ["timer", "Focus timer", ".bento-focus"], ["plan", "Learn & Observe / personal plan", ".bento-plan"],
    ["verse", "Verse of the day", ".bento-verse"], ["links", "Quick links", ".quicklinks"]
  ].filter(([id]) => !isCoworkerDashboard() || id !== "plan")
    .map(([id, label, selector]) => [id, isCoworkerDashboard() && id === "welcome" ? "Welcome & weather" : label, selector]);
  let selected = new Set(sections.map(([id]) => id));
  try {
    const saved = JSON.parse(localStorage.getItem("today-dashboard-sections"));
    if (Array.isArray(saved)) selected = new Set(saved.filter(id => sections.some(section => section[0] === id)));
  } catch {}
  const dialog = document.getElementById("dashboard-sections-dialog");
  const inputs = [];
  function apply() {
    const active = document.body.classList.contains("focus-mode");
    let count = 0;
    const visibleCards = [];
    for (const [id, , selector] of sections) {
      const card = document.querySelector(selector);
      if (!card) continue;
      const visible = selected.has(id) || (active && id === "timer");
      card.classList.toggle("dashboard-section-hidden", !visible);
      if (visible && !card.hidden) { count++; visibleCards.push([id, card]); }
    }
    document.body.classList.toggle("dashboard-filtered", !active && sections.some(([id]) => !selected.has(id)));
    arrangeDashboardSections(visibleCards);
    document.getElementById("dashboard-sections-empty").hidden = count > 0;
  }
  window.applyDashboardSections = apply;
  for (const [id, title, selector] of sections) {
    if (!document.querySelector(selector)) continue;
    const label = document.createElement("label");
    const input = document.createElement("input");
    input.type = "checkbox"; input.value = id; input.checked = selected.has(id);
    input.addEventListener("change", () => {
      input.checked ? selected.add(id) : selected.delete(id);
      save();
    });
    label.append(input, document.createTextNode(title));
    document.getElementById("dashboard-section-options").append(label); inputs.push(input);
  }
  function save() {
    try { localStorage.setItem("today-dashboard-sections", JSON.stringify([...selected])); } catch {}
    apply(); window.dispatchEvent(new Event("today:updated"));
  }
  document.getElementById("dashboard-sections-button").addEventListener("click", () => dialog.showModal());
  for (const id of ["dashboard-sections-close", "dashboard-sections-done"]) document.getElementById(id).addEventListener("click", () => dialog.close());
  document.getElementById("dashboard-show-all").addEventListener("click", () => {
    selected = new Set(sections.map(([id]) => id)); inputs.forEach(input => { input.checked = true; }); save();
  });
  dialog.addEventListener("click", event => {
    const box = dialog.getBoundingClientRect();
    if (event.target === dialog && (event.clientX < box.left || event.clientX > box.right || event.clientY < box.top || event.clientY > box.bottom)) dialog.close();
  });
  window.addEventListener("today:updated", apply);
  apply();
}

function initFocusSections() {
  const sections = [
    ["welcome", "Welcome, weather & rhythm", ".hero"],
    ["now", "Happening now", ".happening-now"],
    ["schedule", "Today’s schedule", ".bento-schedule"],
    ["mail", "Mail", ".bento-mail"],
    ["upcoming", "Coming up", ".bento-comingup"],
    ["invites", "Pending invitations", ".bento-invites"],
    ["plan", "Learn & Observe / personal plan", ".bento-plan"],
    ["verse", "Verse of the day", ".bento-verse"],
    ["links", "Quick links", ".quicklinks"],
  ].filter(([id]) => !isCoworkerDashboard() || id !== "plan")
    .map(([id, label, selector]) => [id, isCoworkerDashboard() && id === "welcome" ? "Welcome & weather" : label, selector]);
  let selected = new Set(sections.map(([id]) => id));
  try {
    const saved = JSON.parse(localStorage.getItem("today-focus-sections"));
    if (Array.isArray(saved)) selected = new Set(saved.filter(id => sections.some(section => section[0] === id)));
  } catch {}
  const dialog = document.getElementById("focus-settings-dialog");
  const options = document.getElementById("focus-section-options");
  const inputs = new Map();
  const tallMail = document.getElementById("focus-tall-mail");
  try { tallMail.checked = localStorage.getItem("today-focus-tall-mail") !== "false"; } catch {}
  tallMail.addEventListener("change", () => {
    try { localStorage.setItem("today-focus-tall-mail", String(tallMail.checked)); } catch {}
    apply();
  });
  function apply() {
    const active = document.body.classList.contains("focus-mode");
    window.applyDashboardSections?.();
    const customized = sections.some(([id]) => !selected.has(id));
    const mailCard = document.querySelector(".bento-mail");
    const mailColumn = active && tallMail.checked && selected.has("mail") && mailCard && !mailCard.hidden && !mailCard.classList.contains("dashboard-section-hidden");
    document.body.classList.toggle("focus-filtered", active && (customized || mailColumn || document.querySelector(".dashboard-section-hidden")));
    document.body.classList.toggle("focus-mail-column", !!mailColumn);
    const leftCards = [];
    let count = 0;
    for (const [id, , selector] of sections) {
      const card = document.querySelector(selector);
      if (!card) continue;
      card.classList.toggle("focus-section-hidden", active && !selected.has(id));
      if (selected.has(id) && !card.hidden && !card.classList.contains("dashboard-section-hidden")) {
        count++;
        if (id !== "mail") leftCards.push(card);
      }
    }
    const columns = Math.max(1, Math.min(3, count));
    const page = document.querySelector(".page");
    page.style.setProperty("--focus-mail-rows", Math.max(1, Math.ceil(leftCards.length / 2)));
    leftCards.forEach((card, index) => {
      card.style.setProperty("--focus-mail-row", Math.floor(index / 2) + 2);
      card.style.setProperty("--focus-mail-column", index === leftCards.length - 1 && index % 2 === 0 ? "1 / 3" : String(index % 2 + 1));
    });
    document.body.classList.toggle("focus-mail-solo", !!mailColumn && leftCards.length === 0);
    page.style.setProperty("--focus-columns", columns);
    page.style.setProperty("--focus-rows", Math.max(1, Math.ceil(count / columns)));
    document.body.classList.toggle("focus-timer-only", active && count === 0);
  }
  function save() {
    try { localStorage.setItem("today-focus-sections", JSON.stringify([...selected])); } catch {}
    apply();
  }
  for (const [id, title, selector] of sections) {
    if (!document.querySelector(selector)) continue;
    const label = document.createElement("label");
    const input = document.createElement("input");
    input.type = "checkbox"; input.checked = selected.has(id); input.value = id;
    input.addEventListener("change", () => { input.checked ? selected.add(id) : selected.delete(id); save(); });
    label.append(input, document.createTextNode(title)); options.append(label); inputs.set(id, input);
  }
  document.getElementById("focus-settings").addEventListener("click", () => dialog.showModal());
  for (const id of ["focus-settings-close", "focus-settings-done"]) document.getElementById(id).addEventListener("click", () => dialog.close());
  document.getElementById("focus-show-all").addEventListener("click", () => {
    selected = new Set(sections.map(([id]) => id)); inputs.forEach(input => { input.checked = true; }); save();
  });
  dialog.addEventListener("click", event => {
    const box = dialog.getBoundingClientRect();
    if (event.target === dialog && (event.clientX < box.left || event.clientX > box.right || event.clientY < box.top || event.clientY > box.bottom)) dialog.close();
  });
  window.addEventListener("today:updated", apply);
  return apply;
}

function initFocusTimer() {
  const card = document.getElementById("focus-timer");
  if (!card) return;
  const applySections = initFocusSections();
  const form = document.getElementById("focus-form");
  const session = document.getElementById("focus-session");
  const status = document.getElementById("focus-status");
  const pause = document.getElementById("focus-pause");
  let validationMessage = "";
  let state = { mode: "idle", total: 0, remaining: 0, deadline: 0 };
  try {
    const saved = JSON.parse(localStorage.getItem("today-focus-timer"));
    if (saved && ["running", "paused", "done"].includes(saved.mode) && Number.isFinite(saved.total) && saved.total > 0 && saved.total <= 86400000 && Number.isFinite(saved.remaining) && saved.remaining >= 0 && saved.remaining <= saved.total && Number.isFinite(saved.deadline)) state = saved;
  } catch {}
  const task = document.getElementById("focus-task");
  task.value = typeof state.task === "string" ? state.task.slice(0, 100) : "";
  function save() { try { localStorage.setItem("today-focus-timer", JSON.stringify(state)); } catch {} }
  function paint() {
    let remaining = focusRemaining(state);
    if (state.mode === "running" && remaining <= 0) {
      state = { ...state, mode: "done", remaining: 0 };
      save();
    }
    const active = state.mode === "running" || state.mode === "paused";
    document.body.classList.toggle("focus-mode", active);
    applySections();
    document.getElementById("focus-title").textContent = state.mode === "running" ? "Locked in" : state.mode === "paused" ? "Focus paused" : state.mode === "done" ? "Focus complete" : "Focus timer";
    const working = document.getElementById("focus-working-on");
    working.hidden = !state.task;
    working.textContent = state.task ? `Working on: ${state.task}` : "";
    card.classList.toggle("focus-complete", state.mode === "done");
    form.hidden = state.mode !== "idle";
    session.hidden = state.mode === "idle";
    pause.hidden = state.mode === "done";
    pause.textContent = state.mode === "paused" ? "Resume" : "Pause";
    const seconds = Math.ceil(remaining / 1000);
    const pad = value => String(value).padStart(2, "0");
    document.getElementById("focus-digits").innerHTML = `${Math.floor(seconds / 3600)}:${pad(Math.floor(seconds / 60) % 60)}<span class="focus-seconds">:${pad(seconds % 60)}</span>`;
    const progress = state.total ? Math.min(100, Math.max(0, (1 - remaining / state.total) * 100)) : 0;
    document.getElementById("focus-progress-fill").style.width = `${progress}%`;
    document.getElementById("focus-progress").setAttribute("aria-valuenow", String(Math.round(progress)));
    const message = state.mode === "done" ? "Time’s up. Take a breath—you’re done." : state.mode === "paused" ? "Paused. Resume when you’re ready." : state.mode === "running" ? "In my focus era. Please save non-urgent chats for after the timer—thank you!" : validationMessage || "Choose a duration in hours and minutes.";
    if (status.textContent !== message) status.textContent = message;
  }
  form.addEventListener("submit", event => {
    event.preventDefault();
    const hours = Number(document.getElementById("focus-hours").value);
    const minutes = Number(document.getElementById("focus-minutes").value);
    if (!Number.isInteger(hours) || hours < 0 || hours > 23 || !Number.isInteger(minutes) || minutes < 0 || minutes > 59 || hours + minutes === 0) {
      validationMessage = "Enter a duration of at least one minute.";
      status.textContent = validationMessage;
      return;
    }
    validationMessage = "";
    const total = (hours * 60 + minutes) * 60000;
    state = { mode: "running", total, remaining: total, deadline: Date.now() + total, task: task.value.trim().slice(0, 100) };
    save(); paint();
    pause.focus({ preventScroll: true });
    card.scrollIntoView({ block: "nearest", behavior: "smooth" });
  });
  pause.addEventListener("click", () => {
    if (state.mode === "running") {
      const remaining = focusRemaining(state);
      state = { ...state, mode: remaining ? "paused" : "done", remaining };
    } else if (state.mode === "paused") state = { ...state, mode: "running", deadline: Date.now() + state.remaining };
    save(); paint();
  });
  document.getElementById("focus-reset").addEventListener("click", () => {
    state = { mode: "idle", total: 0, remaining: 0, deadline: 0 };
    save(); paint();
    document.getElementById("focus-hours").focus({ preventScroll: true });
  });
  setInterval(paint, 1000);
  document.addEventListener("visibilitychange", paint);
  paint();
}

function renderOnboardingPlan() {
  const plan = isCoworkerDashboard() ? null : window.ONBOARDING_PLAN;
  const card = document.querySelector(".bento-plan");
  if (!plan || !plan.startDate || !plan.phases) {
    if (card) card.hidden = true;
    return;
  }
  if (card) card.hidden = false;

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

function getDismissedSlackIds() {
  try {
    return JSON.parse(localStorage.getItem("dashboard-dismissed-slack") || "[]");
  } catch {
    return [];
  }
}

function addDismissedSlackId(id) {
  try {
    let ids = getDismissedSlackIds();
    ids.push(id);
    if (ids.length > 50) ids = ids.slice(-50);
    localStorage.setItem("dashboard-dismissed-slack", JSON.stringify(ids));
  } catch {}
}

function slackItemId(it) {
  return it.permalink || `${it.channel}::${it.preview}`;
}

function toSlackAppLink(permalink) {
  // Permalinks look like https://TEAM.slack.com/archives/CHANNEL_ID/pTIMESTAMP.
  // Converting to the slack:// scheme opens the desktop app directly at that
  // exact message instead of the web client in a browser tab. Omitting the
  // team param is intentional — channel IDs are globally unique, so Slack's
  // app resolves the right workspace from id alone.
  try {
    const match = permalink.match(/\/archives\/([A-Z0-9]+)\/p(\d+)/);
    if (!match) return permalink;
    const channelId = match[1];
    const tsDigits = match[2];
    const ts = `${tsDigits.slice(0, -6)}.${tsDigits.slice(-6)}`;
    return `slack://channel?id=${channelId}&message=${ts}`;
  } catch {
    return permalink;
  }
}

// Join only explicit Message-ID reply chains, including shared ancestors not in today's inbox.
function groupMailThreads(items) {
  const parents = items.map((_, i) => i);
  const find = i => { while (parents[i] !== i) { parents[i] = parents[parents[i]]; i = parents[i]; } return i; };
  const owners = new Map();
  const normalize = id => String(id || "").trim().replace(/^<|>$/g, "");
  items.forEach((item, i) => {
    const ids = [item.messageID, ...(item.threadReferences || [])].map(normalize).filter(Boolean);
    ids.forEach(id => {
      if (owners.has(id)) parents[find(i)] = find(owners.get(id));
      else owners.set(id, i);
    });
  });
  const groups = new Map();
  items.forEach((item, i) => {
    const root = find(i);
    if (!groups.has(root)) groups.set(root, []);
    const group = groups.get(root);
    if (!group.some(existing => item.messageID ? normalize(existing.messageID) === normalize(item.messageID) : existing.id === item.id)) group.push(item);
  });
  return [...groups.values()].map(group => group.sort((a, b) => Date.parse(b.receivedAt) - Date.parse(a.receivedAt)))
    .sort((a, b) => Date.parse(b[0].receivedAt) - Date.parse(a[0].receivedAt));
}

function asanaDesktopLink(value) {
  try {
    const candidate = new URL(value);
    if (candidate.protocol === "https:" && ["app.asana.com", "asana.com"].includes(candidate.hostname)) {
      return candidate.pathname === "/-/desktop_app_link"
        ? candidate.href
        : `https://app.asana.com/-/desktop_app_link?path=${encodeURIComponent(candidate.pathname + candidate.search + candidate.hash)}`;
    }
  } catch {}
  return null;
}

function renderMail() {
  const list = document.getElementById("mail-list");
  if (!list) return;
  const mail = DATA.mail || {};
  const mailItems = (mail.items || []).filter(item => !(mail.stickyNotesEnabled && typeof item.stickyBody === "string"));
  const threads = groupMailThreads(mailItems);
  document.getElementById("mail-title").textContent = "Today’s emails";
  list.replaceChildren();
  const openMail = document.getElementById("mail-open-app");
  openMail.onclick = () => window.webkit.messageHandlers.mailOpenApp.postMessage("open");
  const note = document.createElement("p");
  note.className = "mail-status";
  note.textContent = mail.status || (mail.updatedAt
    ? `${mail.label} · ${threads.length} conversation${threads.length === 1 ? "" : "s"} · ${mailItems.length} messages today · Updated ${new Date(mail.updatedAt).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })}`
    : "Connect Apple Mail in Settings.");
  list.append(note);
  function mailRow(item, isRead = item.isRead) {
    const row = document.createElement("button");
    row.className = "mail-item";
    row.type = "button";
    row.disabled = window.TODAY_COMPANION || !item.messageID;
    row.title = item.sender;
    row.addEventListener("click", () => window.webkit.messageHandlers.mailOpen.postMessage(item.id));
    const sender = document.createElement("span");
    sender.className = "mail-sender";
    sender.textContent = item.sender.replace(/\s*<[^>]+>\s*$/, "").replace(/^"|"$/g, "").trim() || item.sender;
    if (typeof isRead === "boolean") {
      row.classList.add(isRead ? "mail-item-read" : "mail-item-unread");
      const readStatus = document.createElement("span");
      readStatus.className = "mail-read-status";
      readStatus.textContent = isRead ? "Read" : "Unread";
      sender.append(readStatus);
    }
    const time = document.createElement("span");
    time.className = "mail-time";
    time.textContent = new Date(item.receivedAt).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
    const subject = document.createElement("span");
    subject.className = "mail-subject";
    subject.textContent = item.subject;
    row.append(sender, time, subject);
    if (item.attachmentCount > 0) {
      const count = document.createElement("span");
      count.className = "mail-attachments";
      count.textContent = `📎 ${item.attachmentCount} attachment${item.attachmentCount === 1 ? "" : "s"}`;
      row.append(count);
    }
    return row;
  }
  for (const thread of threads) {
    if (thread.length === 1) { list.append(mailRow(thread[0])); continue; }
    const group = document.createElement("div");
    group.className = "mail-thread";
    const isRead = thread.some(item => item.isRead === false) ? false : thread.every(item => item.isRead === true) ? true : undefined;
    group.append(mailRow(thread[0], isRead));
    const details = document.createElement("details");
    details.dataset.eventKey = "mail-thread:" + thread.map(item => item.messageID || item.id).sort().join("|");
    const summary = document.createElement("summary");
    summary.className = "mail-thread-toggle";
    summary.textContent = `${thread.length} messages today · Show earlier messages`;
    details.append(summary);
    thread.slice(1).forEach(item => details.append(mailRow(item)));
    group.append(details);
    list.append(group);
  }
  if (mail.updatedAt && !mail.status && !mailItems.length) {
    const empty = document.createElement("p");
    empty.className = "empty-state";
    empty.textContent = "No emails received today.";
    list.append(empty);
  }
}

function renderSlack() {
  const list = document.getElementById("slack-list");
  const slack = DATA.slack || { connected: false, items: [] };

  if (!slack.connected) {
    list.innerHTML = `<p class="slack-connect-cta">Slack isn't connected yet. Once it is, unread channels and threads will show up here automatically each morning.</p>`;
    return;
  }

  const dismissed = new Set(getDismissedSlackIds());
  const items = (slack.items || []).filter((it) => !dismissed.has(slackItemId(it)));

  if (items.length === 0) {
    list.innerHTML = `<p class="empty-state">Nothing new since your last refresh.</p>`;
    return;
  }

  list.innerHTML = items.map((it) => {
    const tag = it.permalink ? "a" : "div";
    const linkAttrs = it.permalink
      ? `href="${escapeHtml(toSlackAppLink(it.permalink))}"`
      : "";
    return `
    <${tag} class="slack-item" data-slack-id="${escapeHtml(slackItemId(it))}" ${linkAttrs}>
      <div class="slack-item-head">
        <span class="slack-channel">${escapeHtml(it.channel)}</span>
        <span class="slack-count">${it.unreadCount ? it.unreadCount + " new" : ""}</span>
      </div>
      <p class="slack-preview">${escapeHtml(it.preview || "")}</p>
    </${tag}>
  `;
  }).join("");

  list.querySelectorAll("a.slack-item").forEach((el) => {
    el.addEventListener("click", () => {
      addDismissedSlackId(el.getAttribute("data-slack-id"));
      el.classList.add("is-dismissing");
      setTimeout(() => {
        el.remove();
        if (!list.querySelector(".slack-item")) {
          list.innerHTML = `<p class="empty-state">Nothing new since your last refresh.</p>`;
        }
      }, 300);
    });
  });
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
  if (window.LOCAL_CALENDAR_PROTOTYPE) {
    const weather = DATA.weather || {};
    if (Number.isFinite(weather.temperature)) {
      document.getElementById("weather-temp").textContent = `${Math.round(weather.temperature)}°`;
    }
    document.getElementById("weather-desc").textContent = weather.message || WEATHER_CODES[weather.code] || "Weather unavailable";
    return;
  }
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

function initNativeControls() {
  const bridge = window.webkit?.messageHandlers?.dashboardControl;
  if (!bridge || window.TODAY_COMPANION) return;
  const bar = document.querySelector(".top-controls");
  const theme = document.getElementById("theme-toggle");
  const icons = {
    options: '<rect x="3" y="4" width="18" height="16" rx="3"/><path d="M10 4v16"/>',
    pin: '<path d="m9 3 6 0-1 7 4 4v2H6v-2l4-4-1-7Z"/><path d="M12 16v6"/>',
    settings: '<path d="M9.28,5.44 L10.65,5.03 L10.19,2.67 L13.81,2.67 L13.35,5.03 L14.72,5.44 L15.97,6.11 L17.31,4.12 L19.88,6.69 L17.89,8.03 L18.56,9.28 L18.97,10.65 L21.33,10.19 L21.33,13.81 L18.97,13.35 L18.56,14.72 L17.89,15.97 L19.88,17.31 L17.31,19.88 L15.97,17.89 L14.72,18.56 L13.35,18.97 L13.81,21.33 L10.19,21.33 L10.65,18.97 L9.28,18.56 L8.03,17.89 L6.69,19.88 L4.12,17.31 L6.11,15.97 L5.44,14.72 L5.03,13.35 L2.67,13.81 L2.67,10.19 L5.03,10.65 L5.44,9.28 L6.11,8.03 L4.12,6.69 L6.69,4.12 L8.03,6.11 Z"/><circle cx="12" cy="12" r="3.2"/>'
  };
  for (const [action, label] of [["options", "Window options"], ["pin", "Always on top"], ["settings", "Settings"]]) {
    const button = document.createElement("button");
    button.type = "button"; button.id = "native-" + action; button.className = "icon-btn native-control";
    button.setAttribute("aria-label", label); button.title = label;
    button.innerHTML = '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round" stroke-linecap="round">' + icons[action] + '</svg>';
    if (action === "pin") button.setAttribute("aria-pressed", "false");
    button.addEventListener("click", () => action === "settings" ? window.webkit.messageHandlers.openSettings.postMessage("open") : bridge.postMessage(action));
    bar.insertBefore(button, theme);
  }
  window.todayNativeState = state => {
    document.getElementById("native-pin").setAttribute("aria-pressed", String(state.pinned));
    const settings = document.getElementById("native-settings");
    settings.classList.toggle("native-attention", state.updateAvailable);
    settings.title = state.updateAvailable ? "Settings — update available" : "Settings";
    const options = document.getElementById("native-options");
    options.classList.toggle("native-attention", state.spaceWarning);
    options.title = state.spaceWarning ? "Window options — permission needed" : "Window options";
  };
}

function initDesignThemes() {
  const root = document.documentElement, dialog = document.getElementById("design-dialog");
  const defaults = {glass: ["#ff7a45", "#ffb37a"], studio: ["#658bff", "#8fd8d0"], editorial: ["#ac7955", "#d8be95"], retro: ["#a64de4", "#ef98cc"]};
  const key = "today-design-themes";
  let saved = {selected: "glass", colors: {}};
  try {
    const value = JSON.parse(localStorage.getItem(key));
    if (value && Object.hasOwn(defaults, value.selected)) {
      saved.selected = value.selected;
      for (const name of Object.keys(defaults)) {
        const pair = value.colors?.[name];
        if (Array.isArray(pair) && pair.length === 2 && pair.every(c => typeof c === "string" && /^#[0-9a-f]{6}$/i.test(c))) saved.colors[name] = pair;
      }
    }
  } catch (_) {}
  let draft = null;
  const rgb = hex => [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16));
  const luminance = color => color.map(c => { c /= 255; return c <= .04045 ? c / 12.92 : ((c + .055) / 1.055) ** 2.4; }).reduce((sum, c, i) => sum + c * [.2126, .7152, .0722][i], 0);
  const css = c => `rgb(${c.map(Math.round).join(",")})`;
  function apply() {
    const state = draft || saved, pair = state.colors[state.selected] || defaults[state.selected];
    const dark = document.getElementById("theme-toggle").getAttribute("aria-pressed") === "true";
    root.dataset.design = state.selected;
    const base = rgb(pair[0]); let readable = [...base];
    const background = dark ? [40, 40, 40] : [242, 237, 228];
    const ratio = c => (Math.max(luminance(c), luminance(background)) + .05) / (Math.min(luminance(c), luminance(background)) + .05);
    for (let i = 0; i < 30 && ratio(readable) < 4.5; i++) readable = readable.map(c => c + ((dark ? 255 : 0) - c) * .12);
    root.style.setProperty("--accent", css(readable));
    root.style.setProperty("--accent-fill", pair[0]);
    root.style.setProperty("--accent-2", pair[1]);
    root.style.setProperty("--companion-soft", `rgba(${rgb(pair[1]).join(",")},.12)`);
    root.style.setProperty("--accent-soft", `rgba(${base.join(",")},.14)`);
    root.style.setProperty("--accent-glow", `rgba(${base.join(",")},.35)`);
    root.style.setProperty("--accent-on-fill", luminance(base) > .179 ? "#111111" : "#ffffff");
    root.style.setProperty("--retro-primary-ink", luminance(base) > .179 ? "#111111" : "#ffffff");
    root.style.setProperty("--retro-secondary-ink", luminance(rgb(pair[1])) > .179 ? "#111111" : "#ffffff");
    document.querySelectorAll("[data-design-choice]").forEach(button => button.setAttribute("aria-pressed", String(button.dataset.designChoice === state.selected)));
    document.getElementById("design-accent").value = pair[0];
    document.getElementById("design-secondary").value = pair[1];
  }
  document.getElementById("design-button").addEventListener("click", () => { draft = JSON.parse(JSON.stringify(saved)); document.getElementById("design-error").textContent = ""; apply(); dialog.showModal(); });
  document.querySelectorAll("[data-design-choice]").forEach(button => button.addEventListener("click", () => { draft.selected = button.dataset.designChoice; apply(); }));
  ["design-accent", "design-secondary"].forEach((id, index) => document.getElementById(id).addEventListener("input", e => {
    const pair = [...(draft.colors[draft.selected] || defaults[draft.selected])]; pair[index] = e.target.value;
    draft.colors[draft.selected] = pair; apply();
  }));
  document.getElementById("design-reset").addEventListener("click", () => { delete draft.colors[draft.selected]; apply(); });
  document.getElementById("design-close").addEventListener("click", () => dialog.close());
  dialog.addEventListener("close", () => { draft = null; apply(); });
  document.getElementById("design-save").addEventListener("click", () => {
    try { localStorage.setItem(key, JSON.stringify(draft)); saved = JSON.parse(JSON.stringify(draft)); dialog.close(); }
    catch (_) { document.getElementById("design-error").textContent = "Your design couldn’t be saved. Please try again."; }
  });
  window.addEventListener("today:appearance", apply);
  apply();
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
    window.dispatchEvent(new Event("today:appearance"));
    window.webkit?.messageHandlers?.dashboardControl?.postMessage(isDark ? "dark" : "light");
  }

  apply(stored);

  btn.addEventListener("click", () => {
    const currentlyDark = btn.getAttribute("aria-pressed") === "true";
    const next = currentlyDark ? "light" : "dark";
    apply(next);
    try { localStorage.setItem("dashboard-theme", next); } catch {}
  });
}

async function currentDashboardGeneratedAt() {
  try {
    const res = await fetch(`data/dashboard.js?poll=${Date.now()}`, { cache: "no-store" });
    const text = await res.text();
    const match = text.match(/generatedAt:\s*"([^"]+)"/);
    return match ? match[1] : null;
  } catch {
    return null;
  }
}

// The flag file at data/.refresh-requested exists for the whole time a
// refresh is queued or actively running, and its content is a unix
// timestamp of when it was requested. Fetching it directly tells us,
// from any page load (not just the one that clicked the button), whether
// a refresh is already in flight and since when.
//
// If the checker task ever crashes mid-run without cleaning up (killed,
// machine slept mid-task, etc.), this file could in theory be left behind
// indefinitely. Treat anything older than STALE_MS as abandoned rather
// than "in progress" — otherwise every future page load would compute an
// already-passed deadline and reload immediately, forever.
const STALE_FLAG_MS = 10 * 60 * 1000; // 10 min — comfortably past the ~2 min a real refresh needs

async function pendingRefreshSince() {
  try {
    const res = await fetch(`data/.refresh-requested?poll=${Date.now()}`, { cache: "no-store" });
    if (!res.ok) return null;
    const text = (await res.text()).trim();
    const seconds = parseFloat(text);
    const since = Number.isFinite(seconds) ? seconds * 1000 : Date.now();
    if (Date.now() - since > STALE_FLAG_MS) return null;
    return since;
  } catch {
    return null;
  }
}

function initRefreshButton() {
  const btn = document.getElementById("refresh-btn");
  const status = document.getElementById("refresh-status");
  if (window.LOCAL_CALENDAR_PROTOTYPE) {
    btn.title = "Read the latest events synced to Apple Calendar";
    btn.addEventListener("click", () => {
      window.webkit.messageHandlers.calendarRefresh.postMessage("refresh");
    });
    return;
  }
  const POLL_INTERVAL_MS = 8000;
  const MAX_WAIT_MS = 150000; // a bit past the ~2 min the on-demand checker needs

  // Background tabs get their timers throttled or fully paused by the
  // browser/OS (App Nap, tab freezing, the laptop sleeping) — a plain
  // setTimeout chain can silently stall for many minutes while a tab sits
  // unfocused. `watchTimer` is the pending setTimeout for the next
  // scheduled check; `watching` marks whether a watch is active at all.
  // Alongside its own timer, a check also re-runs the instant the tab
  // becomes visible/focused again, so a stalled wait catches up right away
  // instead of waiting on a throttled timer that may not fire soon.
  let watching = false;
  let watchTimer = null;
  let checkInFlight = false;

  async function checkOnce(startedAt, deadline) {
    if (!watching || checkInFlight) return;
    checkInFlight = true;
    try {
      const latest = await currentDashboardGeneratedAt();
      if (!watching) return; // a newer watch superseded this one while we awaited
      if (latest && latest !== startedAt) {
        watching = false;
        status.textContent = "Updated";
        setTimeout(() => window.location.reload(), 300);
        return;
      }
      if (Date.now() >= deadline) {
        watching = false;
        status.textContent = "Reloading…";
        setTimeout(() => window.location.reload(), 300);
        return;
      }
      status.textContent = "Refreshing…";
      clearTimeout(watchTimer);
      watchTimer = setTimeout(() => checkOnce(startedAt, deadline), POLL_INTERVAL_MS);
    } finally {
      checkInFlight = false;
    }
  }

  function watchForUpdate(deadline) {
    const startedAt = DATA.generatedAt || null;
    watching = true;
    btn.disabled = true;
    btn.classList.add("is-spinning");
    status.hidden = false;
    clearTimeout(watchTimer);
    checkOnce(startedAt, deadline);

    const catchUp = () => {
      if (watching && document.visibilityState === "visible") checkOnce(startedAt, deadline);
    };
    document.addEventListener("visibilitychange", catchUp);
    window.addEventListener("focus", catchUp);
  }

  btn.addEventListener("click", async () => {
    if (btn.disabled) return;
    // Disable synchronously, before any awaited check, so two rapid real
    // clicks can't both slip through while the flag-file check is pending.
    btn.disabled = true;
    btn.classList.add("is-spinning");
    status.hidden = false;
    status.textContent = "Requesting…";

    // A refresh may already be queued or running — from this tab, another
    // tab, or a previous page load — since the flag file persists the
    // whole time. Don't fire a redundant request; just tell the user and
    // start watching for the one already in progress.
    const already = await pendingRefreshSince();
    if (already) {
      status.textContent = "Already refreshing — please wait…";
      watchForUpdate(already + MAX_WAIT_MS);
      return;
    }

    // Best-effort: ask the on-demand checker task to do a real data pull
    // within the next ~2 min. If the server doesn't support this endpoint
    // (e.g. an older cached deploy), we just fall back to a plain reload.
    let requested = false;
    try {
      const res = await fetch("/api/refresh", { method: "POST" });
      requested = res.ok;
    } catch {}

    if (!requested) {
      setTimeout(() => window.location.reload(), 400);
      return;
    }

    watchForUpdate(Date.now() + MAX_WAIT_MS);
  });

  // If a refresh was already requested before this page load (e.g. the
  // user clicked Refresh, then reloaded manually while it was still
  // working), pick up watching for it immediately instead of leaving the
  // button looking idle.
  pendingRefreshSince().then((already) => {
    if (already) {
      status.textContent = "Refreshing — please wait…";
      watchForUpdate(already + MAX_WAIT_MS);
    }
  });
}

function initAutoRefresh() {
  if (window.LOCAL_CALENDAR_PROTOTYPE) return; // The Mac app refreshes every five minutes.
  // Data refreshes every 30 min (8am-5pm weekdays) — reload periodically
  // so an already-open tab picks that up without anyone clicking refresh.
  setInterval(() => window.location.reload(), 10 * 60 * 1000);
}

function stickyNoteId(note) {
  return note.id || `${note.ts || ""}-${note.from || ""}-${note.text.length}`;
}

function getDismissedNoteIds() {
  try {
    const ids = JSON.parse(localStorage.getItem("dashboard-dismissed-notes") || "[]");
    return Array.isArray(ids) ? ids : [];
  } catch {
    return [];
  }
}

function addDismissedNoteId(id) {
  try {
    let ids = getDismissedNoteIds();
    ids.push(id);
    ids = [...new Set(ids)];
    localStorage.setItem("dashboard-dismissed-notes", JSON.stringify(ids));
  } catch {}
}

function hashString(str) {
  let hash = 0;
  for (let i = 0; i < str.length; i++) hash = (hash * 31 + str.charCodeAt(i)) >>> 0;
  return hash;
}

function renderStickyNotes() {
  const container = document.getElementById("sticky-notes");
  container.innerHTML = "";

  // Accept both the old singular `stickyNote` shape and the new plural
  // `stickyNotes` array, so cached data mid-transition still renders.
  let raw = typeof DATA.mail?.stickyNotesEnabled === "boolean" ? [] : DATA.stickyNotes || (DATA.stickyNote ? [DATA.stickyNote] : []);
  const mail = DATA.mail || {};
  if (mail.stickyNotesEnabled && mail.stickyScope) {
    const key = "today-email-notes:" + mail.stickyScope;
    let cached = [];
    try { const saved = JSON.parse(localStorage.getItem(key) || "[]"); if (Array.isArray(saved)) cached = saved.filter(n => n && typeof n.id === "string" && typeof n.text === "string"); } catch {}
    const notes = new Map(cached.map(n => [n.id, n]));
    for (const item of mail.items || []) {
      if (typeof item.stickyBody !== "string") continue;
      const id = key + ":" + (item.messageID || item.id);
      notes.set(id, {id, text: item.stickyBody.trim() || "(An empty note)", from: item.sender.replace(/\s*<[^>]+>\s*$/, "").replace(/^"|"$/g, ""), ts: item.receivedAt});
    }
    raw = [...notes.values()].slice(-100);
    try { localStorage.setItem(key, JSON.stringify(raw)); } catch {}
  }

  const dismissed = new Set(getDismissedNoteIds());
  const notes = raw.filter((n) => n && n.text && !dismissed.has(stickyNoteId(n)));
  if (notes.length === 0) return;

  const positionCount = 5;
  const usedPositions = new Set();

  notes.slice(0, window.innerWidth <= 700 ? 1 : 5).forEach((note) => {
    const noteId = stickyNoteId(note);
    let position = hashString(noteId) % positionCount;
    // Nudge to an unused slot so simultaneous notes don't stack on each other.
    let attempts = 0;
    while (usedPositions.has(position) && attempts < positionCount) {
      position = (position + 1) % positionCount;
      attempts++;
    }
    usedPositions.add(position);

    const el = document.createElement("div");
    el.className = `sticky-note sticky-pos-${position}`;
    el.innerHTML = `
      <button class="sticky-note-dismiss" type="button" aria-label="Dismiss note">&times;</button>
      <p class="sticky-note-text"></p>
      <p class="sticky-note-from"></p>
    `;
    el.querySelector(".sticky-note-text").textContent = note.text;
    el.querySelector(".sticky-note-from").textContent = note.from ? `— ${note.from}` : "";
    el.querySelector(".sticky-note-dismiss").onclick = () => {
      addDismissedNoteId(noteId);
      renderStickyNotes();
    };
    let savedPosition;
    try { savedPosition = JSON.parse(localStorage.getItem("today-note-position:" + noteId)); } catch {}
    const place = (x, y) => {
      el.style.left = Math.max(8, Math.min(x, window.innerWidth - el.offsetWidth - 8)) + "px";
      el.style.top = Math.max(8, Math.min(y, window.innerHeight - 80)) + "px";
      el.style.right = "auto"; el.style.bottom = "auto";
    };
    container.appendChild(el);
    if (window.innerWidth > 700 && savedPosition && Number.isFinite(savedPosition.x) && Number.isFinite(savedPosition.y)) place(savedPosition.x, savedPosition.y);
    const handle = el.querySelector(".sticky-note-from");
    handle.title = "Drag to move note";
    handle.onpointerdown = event => {
      if (window.innerWidth <= 700 || event.button !== 0) return;
      const rect = el.getBoundingClientRect();
      const dx = event.clientX - rect.left, dy = event.clientY - rect.top;
      handle.setPointerCapture(event.pointerId);
      handle.onpointermove = e => place(e.clientX - dx, e.clientY - dy);
      handle.onpointerup = () => {
        try { localStorage.setItem("today-note-position:" + noteId, JSON.stringify({x: parseFloat(el.style.left), y: parseFloat(el.style.top)})); } catch {}
        handle.onpointermove = null; handle.onpointerup = null;
      };
      handle.onpointercancel = () => { handle.onpointermove = null; handle.onpointerup = null; };
    };
  });
}

// Native refreshes update content in place; they must not navigate the web view.
window.refreshLocalDashboard = function () {
  if (!window.LOCAL_CALENDAR_PROTOTYPE) return;
  const x = window.scrollX;
  const y = window.scrollY;
  const panelScroll = Array.from(document.querySelectorAll(".panel-body, .bento-workschedule, .bento-plan, .happening-now, .hero"), el => [el, el.scrollTop]);
  const detailKey = el => el.dataset.eventKey || el.id || el.querySelector("summary")?.textContent;
  const expanded = new Set(Array.from(document.querySelectorAll("details[open]"), detailKey));
  DATA = window.DASHBOARD_DATA;
  renderGreetingAndClock();
  renderSchedule();
  renderUpcoming();
  renderPendingInvites();
  renderWorkSchedule();
  renderHeroRhythm();
  renderOnboardingPlan();
  renderMail();
  renderStickyNotes();
  renderVerse();
  initWeather();
  document.querySelectorAll("details").forEach(el => { el.open = expanded.has(detailKey(el)); });
  panelScroll.forEach(([el, top]) => { el.scrollTop = top; });
  window.scrollTo({ left: x, top: y, behavior: "instant" });
  window.dispatchEvent(new Event("today:updated"));
};

initQuickLinks();
initNativeControls();
initThemeToggle();
initDesignThemes();
initRhythmWeekDialog();
initDashboardSections();
initFocusTimer();
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
renderMail();
renderVerse();
renderStickyNotes();
initWeather();

function showAsanaBrief(task) {
  document.getElementById('asana-brief-dialog')?.remove();
  const dialog = document.createElement('dialog');
  dialog.id = 'asana-brief-dialog'; dialog.className = 'asana-brief-dialog';
  dialog.setAttribute('aria-labelledby', 'asana-brief-title');
  const head = document.createElement('header');
  const title = document.createElement('h2');
  title.id = 'asana-brief-title'; title.textContent = task.title;
  const close = document.createElement('button');
  close.textContent = '×'; close.setAttribute('aria-label', 'Close task brief');
  close.addEventListener('click', () => dialog.close());
  head.append(title, close);
  const content = document.createElement('div'); content.className = 'asana-brief-content';
  const brief = task.brief;
  function addText(value) {
    const p = document.createElement('p'); p.className = 'asana-brief-text';
    const text = String(value || '');
    let end = 0;
    for (const match of text.matchAll(/https:\/\/[^\s<>"']+/g)) {
      p.append(document.createTextNode(text.slice(end, match.index)));
      const a = document.createElement('a'); a.textContent = match[0];
      a.href = match[0]; a.target = '_blank'; a.rel = 'noopener noreferrer';
      p.append(a); end = match.index + match[0].length;
    }
    p.append(document.createTextNode(text.slice(end))); content.append(p);
  }
  function heading(text) { const h = document.createElement('h3'); h.textContent = text; content.append(h); }
  if (brief.parentTitle) {
    heading('Parent task · ' + brief.parentTitle);
    addText(brief.parentDescription || 'No description on the parent task.');
    if (brief.description) { heading('Your task’s instructions'); addText(brief.description); }
  } else {
    heading('Task brief'); addText(brief.description || 'No description on this task.');
  }
  if (brief.message) addText(brief.message);
  const url = asanaDesktopLink(brief.parentURL || brief.url || task.url);
  if (url) {
    const a = document.createElement('a'); a.href = url;
    a.textContent = brief.parentURL ? 'Open parent in Asana ↗' : 'Open task in Asana ↗';
    a.target = '_blank'; a.rel = 'noopener'; content.append(a);
  }
  dialog.append(head, content); document.body.append(dialog);
  dialog.addEventListener('close', () => dialog.remove());
  dialog.addEventListener('click', event => {
    const box = dialog.getBoundingClientRect();
    if (event.target === dialog && (event.clientX < box.left || event.clientX > box.right || event.clientY < box.top || event.clientY > box.bottom)) dialog.close();
  });
  dialog.showModal();
}
