# AMS Tria Menu 0.1 (build 1, 26 Nov 2026) - Specification

## Purpose

AMS Triathlon Training runs on the Mac as an iPad app, and an iPad app cannot put anything in the menu bar. AMS Tria Menu is a separate, tiny Mac-only menu bar app (no Dock icon) that shows today's training session and the owner's Garmin Body Battery at a glance. It only reads. It never changes the plan. Bundle id: `com.schabbauer.AMSTriaMenu`. Apple Silicon, macOS 15 or later. It is installed directly on the Mac with `Tools/install.sh`.

## Menu bar item

Since 0.3 the item is ONE icon and nothing beside it (his own wish, with a picture of AMS Triathlon Training's app icon: "make it like this").

- The icon is the training wave: the line with three blocks of AMS Triathlon Training's app icon (`tools/app-icon.svg` there), redrawn on the 24-point grid as the app mark `trainingWave` ("Training wave") in the central icon library (AMS-Icons). In the menu bar it is drawn 20 points wide with a stroke of 2.3, round ends and joins.
- Green (day `#00875A`, night `#01C97B`) while the app has a note that counts today; grey while it has none. It does not change with the session, and it is redrawn only when it turns from green to grey or back.
- No number: Body Battery is in the panel and in the hover words.
- Resting the pointer on it says the sessions and Body Battery in words, for example "Run 45 min, to do · Swim 40 min, done" and under it "Body Battery 62".
- A click opens the panel. A right click or control-click shows the short menu: "Open Triathlon", "Refresh now", "Settings…".
- In 0.1 and 0.2 the item was a mark with four faces (the sport's mark in its colour while a session was to do, a green tick when done, a moon on a rest day, a grey mark without a note) and the Body Battery number, or a dash, beside it.

## Panel

300 points wide, under the item. From top to bottom:

1. Header: the app tile (the white training wave on green; a white medal before 0.3.1), "AMS Tria Menu", the version, and a gear button for Settings.
2. "Today · Tue 1 Dec" (green heading). One row per session: the sport's mark, the sport with its length right beside it ("Run 45 min"), then a small filled pill "to do" in the sport's colour, or a green tick with "done", or grey "missed". Under that, the session's title in small grey words. A click on a row opens that session in AMS Triathlon Training with the link `amsworkoutsync://session/<key>`. A grey line under the rows says "Click a session to open it in Triathlon". A rest day shows one row with the moon and "Rest day".
3. If there is no note for today, grey words say why: "No note for today yet. Triathlon writes it when it opens.", or "AMS Triathlon Training is not on this Mac.", or that the Mac did not let the app read the note (allow it in System Settings, Privacy & Security), or that the note is newer than this version understands.
4. "Tomorrow" (blue heading): tomorrow's first session, for example "Bike, 1 h 10 min", or "Rest day". Missing when nothing is planned.
5. "This week" (purple heading): for example "40 min done of 3 h 35 min planned", and a slim purple bar filled to that share (done divided by planned, limited to 0 to 1; no bar when nothing is planned).
6. Body Battery card (raspberry, filled, white words; look C3 since 0.2). Top line: "Body Battery" with the number (24 points, bold) right beside it, and at the right the small words "watch synced 15:09" (the watch's last sync; with the weekday, for example "watch synced Mon 15:09", when it was not today). Under it a curve as wide as the card, 74 points tall: today is a white line (2.2) with a dot at the newest reading and a soft white fill (22 %) under it down to the bottom line; yesterday is a thin dark plum line (1.3) with the word "yesterday". The curve runs from midnight to midnight; the bottom line is 0, the top 100; small marks and the figures 06, 12 and 18 under it are the hours. It is only as fine as the watch's syncs. With no reading at all the curve is left out.
7. One full-colour green main button "Open Triathlon". It brings the Triathlon app to the front (`amsworkoutsync://today`).

There is no "done" button. Triathlon cannot log a session on the Mac (only the iPhone logs), so a click only opens the session.

## Where the figures come from

| Figure | Source | When read |
|---|---|---|
| Today's sessions, tomorrow, the week | The note `today-note.json`, written by AMS Triathlon Training 2.8 or newer in its own container on this Mac, each time it opens and when the plan changes | Once a minute |
| Body Battery now and today's curve | The AMS Garmin Bridge Board on this Mac, `127.0.0.1:7788/api/board` (the same numbers as the Board shows) | Every 30 minutes, and when the panel opens if the last answer is older than 5 minutes; "Refresh now" asks at once |
| Body Battery when the Board does not answer | The reading in Triathlon's note, small words "as Triathlon last read it" | With the note |
| Yesterday's line | As Triathlon read it (the same line as on its Body page); otherwise the app's own memory of yesterday | With the note |

- The note counts only on its own day (the Mac's time zone), so yesterday's session is never shown. A note written more than 36 hours ago is not used either.
- The note has a format number (1 at first). Unknown fields are ignored and missing ones are empty. A higher format number than the app knows means: show nothing and say so.
- If neither the Board nor Triathlon has a reading: a dash and the words "Garmin Board not answering".
- If the Board answers for today but has no reading yet (the watch has not synced since midnight): a dash and the words "no reading yet today". Yesterday's number is never shown as today's.
- Each answer makes the Board ask Garmin about 17 questions (the Board keeps its answer for 5 minutes). That is why the app asks only every 30 minutes: Body Battery changes only when the watch syncs.
- Triathlon's own reading (`garmin-body.json` beside the note) counts its times from 2001; the app turns them into the same count as the Board's. When that file is still yesterday's, its "today" curve is used as yesterday's line.
- The sport marks are AMS Triathlon Training's own marks from the central icon library (AMS-Icons package, pinned revision), so both apps show the same drawings.
- The app keeps its own memory of each day's curve, for the newest three days, on this Mac only. The fuller curve of a day wins.
- No Garmin key is stored in this app. The app never contacts Garmin or the internet. Nothing leaves the Mac.

## Open Triathlon quietly

Triathlon writes today's note only when it opens. A switch in Settings, "Open Triathlon quietly" (on at first), lets the app open it in the background: hidden, never in front, no window. The note is there a few seconds later.

- No note for today (each morning, or after midnight): open Triathlon hidden. If a try brings no note, wait 20 minutes before the next.
- While a session is still to do: again every 30 minutes. If Triathlon still runs hidden, it is closed politely and opened hidden again, so it reads the plan afresh. That way a session logged on the iPhone turns into the green tick.
- Once all is done, or it is a rest day: the app leaves Triathlon alone.
- Never while Triathlon's window is showing.
- Nothing is done when Triathlon is not on the Mac.
- "Refresh now" (right-click menu) asks at once, and the waiting times do not count then, even with the switch off.
- With the switch off, the grey wave and the words "No note for today yet" stay until the owner opens Triathlon himself.

## First start

Nothing to set up. On 26 Nov 2026 the installed app read Triathlon's note without any question from the Mac (both apps are signed by the same developer team). Should the Mac ever ask whether "AMS Tria Menu" may access data from other apps, Allow is the answer. If it was refused, the panel says so, and it can be allowed in System Settings, Privacy & Security. The read never happens on the main thread, because it waits while such a question is up.

## Settings window

440 points wide. Three tabs: "Settings", "How it works", "What's new". At the bottom of every tab: "Version 0.1 (1)", "Quit AMS Tria Menu", and the full-colour "Done" button. Escape also closes the window.

- Settings: "Open at login"; "Open Triathlon quietly" with two lines of explanation; the section "Where the figures come from" with two status lines (today's note: when Triathlon wrote it; Body Battery: from the Garmin Board, when the watch last synced).
- How it works: a guide to the whole app, including the section "Signs in this app" (every mark and colour with its meaning). The text is in `App/Sources/Guide.swift`.
- What's new: every version, newest first.

## Keeper and only one copy

- Open at login uses the "keeper": a LaunchAgent, `com.schabbauer.AMSTriaMenu.keeper`. It opens the app at every login and again after an unexpected stop, but not after Quit (a clean end). The Mac's own login list is not used. A copy opened by hand gives way to the keeper while "Open at login" is on and the app sits in an Applications folder. A copy opened with `--plain` never hands itself over.
- Only one copy of the app runs: the copy that started first stays. Same start time: the smaller process number counts as earlier.

## Place in the menu bar

A new menu bar item can land behind the notch when the bar is full. At first start the app picks a place in sight: 236 points from the right edge. If the Mac saves a place above 1000 (the far-left group) and the item has been out of sight for 10 seconds, the app puts it back at that home place.

## Colours and signs

Each colour or mark means one thing:

- Green heading: today. Blue heading: tomorrow. Purple heading and slim purple bar: this week.
- Raspberry: Body Battery. White line with a dot: today so far. Thin dark plum line: yesterday.
- Green wave in the menu bar: the app has today's note. Grey wave: no note for today yet.
- A sport's colour (in the panel's rows): that sport.
- Green tick: done. Nothing else is ever a tick.
- Grey: nothing to do or nothing known. Never red.
- Full-colour button: the main thing to do on that screen.

## What is remembered

On this Mac only: the switches "Open at login" and "Open Triathlon quietly", the app's own memory of the newest three days' Body Battery curves, and the saved menu bar place.

## What is tested

Nine small rule tests in `Core/Tests/TriaMenuCoreTests/RulesTests.swift` (all values invented), run with `swift test --package-path Core`:

- reading the note (format, unknown fields, newer format, only its own day, 36 hours);
- the words (session lengths, hover text, "watch synced" with and without the weekday);
- Body Battery from the Board, from Triathlon, waiting for the first sync of the day, or none; yesterday from Triathlon or from the app's memory; times counted from 2001; the three-day memory;
- the curve positions across the day;
- the quiet opening rule with its numbers (20 minutes, 30 minutes, never while Triathlon's window shows);
- the keeper's start order, the place repair and the one-copy rule.

## Not in 0.1

- No "done" button on the Mac.
- No notifications.
- No graphs window.
- No changes to the plan: the app only reads.

## Version history

- 0.3.1 (4), 26 Nov 2026: the app icon and the tile in the panel and in Settings are the white training wave on calm green `#00875A` (his yes; a white medal before). White on green, not green on dark teal like AMS Triathlon Training's icon, so the two apps can be told apart. Made by `Tools/make-icon.py` and `Tools/mark-outline.swift` from the same points as the library mark `trainingWave`.
- 0.3 (3), 26 Nov 2026: the menu bar item is one icon, the training wave (green with today's note, grey without); the changing mark and the Body Battery number left the menu bar. The rule for the mark's faces and its test were removed (nine rule tests). The wave was added to AMS-Icons as `trainingWave`; the package pin moved to 58433eb.
- 0.2 (2), 26 Nov 2026: the Body Battery card in look C3 (his pick from one picture with numbered options; he kept the menu bar item and the session rows as they were): number beside the name, wide curve with a soft fill under today and the hours 06, 12, 18. In 0.1 the number stood large on the left with a small curve (150 by 62 points) beside it.
- 0.1 (1), 26 Nov 2026: first version.

## Checks from outside (for whoever maintains it)

- `--snapshots <folder>`: pictures of every screen with invented values, by day and by night.
- `--read`: prints what the app reads right now (green or grey wave, Body Battery, the note's day and states, the Body Battery source). Opens nothing.
- `--refresh`: tells the running copy to do "Refresh now".
- `--open-at-login on|off|status`, `--right-menu-items`.
- Notifications the running copy listens to: `com.schabbauer.AMSTriaMenu.togglePanel`, `.openSettings` (object: a tab's title, or "end"), `.showRightMenu`, `.refresh`, `.openFirstSession`.
- A short diary of what the app did is kept in `~/Library/Logs/AMS Tria Menu/diary.log` (times and steps, no training or health figures).
