# Today

A glanceable, dark, native iOS app for one family's day: who is where, what
each kid needs, the afternoon pickup loop, and three time-aware check-ins.
Calendars and reminders are read on-device with EventKit; there is no server.
All date logic runs in **America/Chicago**, explicitly.

## Layout

```
Rules/
  household.json          The household rules. Edit this, not code.
  household.schema.json   JSON Schema: validation + autocomplete in most editors.
Packages/TodayKit/        Swift package, plain Swift + Foundation (runs on Linux)
  Sources/TodayCore/
    Time/                 LocalDate, LocalTime, DaySet, HouseholdClock (Chicago)
    Rules/                Rules model, strict loader, validator, writer, store,
                          editing helpers (Move to, add/remove people)
    Engine/               DayPlanner, assignment rules, lane layout, Up next,
                          spoken brief, "why is this here?", PlanText
    Samples/              The fictional sample household + seeded days
  Sources/TodaySources/   EventKit: calendars, reminders, Birthdays (iOS/macOS)
  Sources/today-plan/     CLI: prints a day plan as text
  Tests/TodayCoreTests/   Unit tests + Golden/ text plans for the seeded days
App/                      iOS app: Today screen, event sheet, brief speaker
App/Household/            People, Rules, Schedule and Calendars editors
Widgets/                  Widget extension (placeholder until M6)
TodayTests/ TodayUITests/ App tests; the UI tests walk and screenshot the seeded days
Support/                  Info.plist and entitlements
```

The Xcode project uses folder-synced groups: add a file under `App/`,
`Widgets/` or a test folder and it's in that target, with no project edits.

## Using the app

- **Today**: the date and weekday with ▶ (reads the brief aloud and shows
  it as a card), the day's chips (school, preschool, the grandparents),
  alerts, **Up next**, the lanes for the rest of today, weather, what the
  kids need (tap to check off, per day), and birthdays. **Swipe** left and
  right through the days (a month back, two ahead); **Today** jumps back.
- **Tap any block** for "Why is this here?": what put it there, and **who
  it's for**: pick people for **just this event**, **every repeat**, or
  **every event with this title** (a rule at the top of the list). Also
  **Make a Rule**, **Hide from Today**, **Open in Calendar**.
- **Needs a person**: events on a calendar set to "ask me" wait in this
  card until you tap who they're for.
- **Household** (the people button): People (photo, name, lane color,
  group, other names, shared lane, birthday, own calendar), Rules (Mail-style,
  with a live preview of the next 14 days), Schedule (blocks, school
  calendars, care, pickup loop, check-in times, lane hours, home location
  for weather; export/import household.json) and Calendars (what each
  calendar on the phone is, missing ones, Reminders lists for needs).
- Every save is validated first; a change that would break the rules is
  refused with the reason.

## Editing the rules

`Rules/household.json` holds every household fact that isn't on a calendar:
people, calendars and who owns them, work/school/preschool blocks, school
calendars (days off, early releases), the in-laws' care, the pickup loop,
kids' recurring needs, check-in times and what counts as important.

- Times are 24-hour strings in quotes: `"08:15"`. Dates are `"2026-11-26"`.
- Days are `"daily"`, `"weekdays"`, `"weekends"` or a list like `["tue", "thu"]`.
- Anything in `<angle brackets>` is a placeholder, and each `todo` entry is an
  open question. Both show as "rules incomplete" warnings until resolved.
- A misspelt key, a bad time or an id that doesn't exist is an error that names
  the exact spot (`blocks[1].start: "8.15" is not a time...`) and suggests the
  nearest valid key or id.

Check an edited file locally:

```sh
cd Packages/TodayKit
swift run today-plan --rules ../../Rules/household.json 2026-10-20
```

### How events are attributed

Each calendar lists who it belongs to (`"members"`: one person, several, or
`"everyone"`) and who gets an event whose title names nobody
(`"ifNobodyNamed"`: `"members"`, `"ask"`, or a list of people):

```json
{ "title": "Family", "members": "everyone",      "ifNobodyNamed": ["grandpa"] },
{ "title": "Sam",    "members": ["dad"] },
{ "title": "Us",     "members": ["dad", "mom"], "ifNobodyNamed": "ask" }
```

In order, the first that applies decides:

1. **A pick made by hand** in the app (one event, or every repeat). Kept in
   `assignments.json` beside the rules.
2. **Assignment rules**, top to bottom, Mail-style.
3. **A name in the title**: "Dentist - Emma", "Emma's dentist" and "Dentist
   (Emma)" all go to Emma. Matching ignores case and accents and only matches
   whole words, so "Al" never matches "Almond". On someone's own calendar the
   named people join them.
4. **The calendar's `ifNobodyNamed`**. `"ask"` holds the event under **Needs
   a person** until you pick.

A calendar that isn't on the device makes its members' lanes **no data**; a
missing `"everyone"` calendar makes every lane no data, since a name in a
title can put its events anywhere. Unknown time is never shown as free.
Files from schema 1–2 (`role`/`owner`/`defaultOwner`) still load and are
saved in the new form.

## Tests

```sh
cd Packages/TodayKit
swift test                                                  # rules engine, Linux or macOS
TODAY_UPDATE_GOLDENS=1 swift test --filter GoldenPlanTests  # after an intended change
```

The suites cover school-day detection (terms, days off, breaks, early
release), title-name attribution, the pickup loop, in-law coverage, lanes and
"no data", needs, the rules loader/validator, DST days, and a guard that no
Swift source uses the device's calendar or time zone.

## Pipeline

Ported from MyTeams:

| Workflow | Runs on | What |
|---|---|---|
| Core Tests | every push (Linux) | `swift test` for TodayCore; schema check of the rules |
| iOS Gate | `main`, `claude/**`, manual (`xcode-27`) | TodayCore tests on macOS; build + unit/UI tests on the iOS 27 simulator; screenshots → `ci-screenshots` branch |
| Build unsigned IPA | manual (`xcode-27`) | Release build → `Today-v1.0.N-unsigned.ipa` GitHub Release for Feather |

The repo is private, so download the `.ipa` while signed in to GitHub, then
open it in Feather. For the App Group, WeatherKit and Time Sensitive
notifications to survive re-signing, the signing profile must be for App IDs
with those capabilities: `PolarReailty.Today`, `PolarReailty.Today.widgets`,
`group.PolarReailty.Today`.

## Milestones

1. Rules engine + tests ✓
2. EventKit ingestion, household store, Mail-style assignment rules ✓
3. Main screen (lanes, Up next, weather, needs, birthdays) ✓
4. Spoken brief and in-app Household editors ✓
5. Shared calendars, picks by hand, Needs a person, swiping through days ✓
6. Check-in notifications (6:30 / 12:00 / 3:15)
7. Lock Screen + Home Screen widgets
