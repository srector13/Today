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
    Rules/                Rules model, strict loader, validator
    Engine/               DayPlanner, TitleAttributor, DayPlan, PlanText
    Samples/              The fictional sample household + seeded days
  Sources/today-plan/     CLI: prints a day plan as text
  Tests/TodayCoreTests/   Unit tests + Golden/ text plans for the seeded days
App/                      iOS app (M1: a debug view of the plan)
Widgets/                  Widget extension (M1: placeholder)
TodayTests/ TodayUITests/ App tests; the UI tests screenshot the seeded days
Support/                  Info.plist and entitlements
```

The Xcode project uses folder-synced groups: add a file under `App/`,
`Widgets/` or a test folder and it's in that target, with no project edits.

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

On the `shared` family calendar an event belongs to its `defaultOwner`
(Grandpa) unless the title names people. A name in the title wins: "Dentist -
Emma", "Emma's dentist" and "Dentist (Emma)" all go to Emma. Matching ignores
case and accents and only matches whole words, so "Al" never matches "Almond". On a
`personal` calendar, events belong to the owner plus anyone named.

A personal calendar that isn't on the device makes its owner's lane **no
data**; a missing shared calendar makes every lane no data, since a name in a
title can put its events anywhere. Unknown time is never shown as free.

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

1. **Rules engine + tests** ← M1
2. EventKit ingestion + lane model
3. Main screen (lanes, weather, needs, birthdays)
4. Spoken brief
5. Check-in notifications (6:30 / 12:00 / 3:15)
6. Lock Screen + Home Screen widgets
