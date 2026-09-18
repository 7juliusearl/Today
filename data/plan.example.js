// EXAMPLE — optional. Copy to plan.js and fill in your own onboarding/goal
// plan to populate the "Onboarding" progress card. Hand-maintained; the
// daily refresh task never touches this file.
window.ONBOARDING_PLAN = {
  startDate: "2026-01-01",
  totalDays: 90,
  goal: "By day 90, independently own a project from concept through delivery.",
  team: [
    "Jordan — Manager",
    "Sam — Teammate"
  ],
  phases: [
    {
      days: 30,
      title: "Learn & Observe",
      items: [
        "Learn the team's tools and workflow",
        "Shadow a full project cycle end to end"
      ],
    },
    {
      days: 60,
      title: "Contribute & Build",
      items: [
        "Lead one project start to finish",
        "Build confidence hitting deadlines independently"
      ],
    },
    {
      days: 90,
      title: "Own & Lead",
      items: [
        "Own end-to-end projects on the regular rotation"
      ],
    },
  ],
};
