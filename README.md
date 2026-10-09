# Axiom for iPhone

The Axiom dashboard as an iPhone app, with Home Screen and Lock Screen widgets. It's for sideloading with SideStore or AltStore.

## What's inside

- **The dashboard:** the same Axiom file, full screen, working offline, with your data saved on the phone.
- **Alarm clock:** alarms with a time, a label and repeat days, like the Clock app, in Axiom's dots. On iOS 26 and later they ring even when the phone is locked, on silent or in Focus, and a snoozed alarm counts down on the Lock Screen in dots. Earlier iOS shows them as notifications.
- **Siri and Shortcuts:** "When's my next report in Axiom?", "Where am I flying tomorrow in Axiom?", "What's my next alarm in Axiom?", "Add a glass of water in Axiom". Also in the Shortcuts app.
- **19 widgets** (touch and hold the Home Screen, tap **Edit**, **Add Widget**, search "Axiom"):
  - **Roster:** Next duty (small, medium, large departure board; turns yellow, then red, before report), Flight progress (a dot moving along the sector while you fly), Globe (the dot-matrix globe zoomed to your route in red), Next 7 days, Roster month.
  - **Time:** Clock (Bangkok in big dots, with UTC), World clock (your cities, live), Year (days left, every day as a dot).
  - **Crew:** Duty hours (7/14/28-day duty and 28-day flying against the limits), Rest (rest so far and when you're legal again), Wake-up (alarm, bedtime, leave home), Layover (local time, hotel, pickup countdown).
  - **Everyday:** Weather (updates by itself), Sun (sunrise, sunset and the sun's path), Water (+ adds a glass), Next alarm, To-do and Shopping (tick items off on the Home Screen), Countdown.
  - **Lock Screen:** Next duty, Flight progress, Wake-up, Next alarm, snooze countdown, Countdown, Duty hours, Water and Year.

The widgets read what Axiom last saved. Open the app after importing a new eCrew PDF and the widgets update.

## Build the .ipa (no Mac needed)

1. Put this folder in a GitHub repository, with the files at the top level, and push to `main`.
2. GitHub Actions builds it on a Mac machine (`.github/workflows/build-ipa.yml`). This takes about 5–10 minutes.
3. `Axiom.ipa` appears under the repository's **Releases**, as "latest".

Building on your own Mac instead: install XcodeGen (`brew install xcodegen`), run `xcodegen generate`, then open `Axiom.xcodeproj`.

## Install on your iPhone with SideStore

1. **Set up SideStore once.** Follow the guide at docs.sidestore.io. It needs a Windows or Mac computer for about 20 minutes. After that, everything happens on the phone.
2. **Download Axiom.ipa.** In Safari on the iPhone, open the repository's Releases page and download `Axiom.ipa`.
3. **Install.** In SideStore, go to **My Apps**, tap **+**, and pick `Axiom.ipa`. Sign in with your Apple ID when it asks.
4. **Add widgets.** Touch and hold the Home Screen, tap **Edit**, then **Add Widget**, and search for **Axiom**.
5. **Refresh every week.** With a free Apple ID the app expires after 7 days. Open SideStore and tap **Refresh**. Your data and widgets stay.

AltStore works the same way: install AltServer on the computer, then use **My Apps** and **+**.

## Moving your data from the Home Screen web app

The app keeps its own saved data, separate from Safari.

1. In the old Axiom (the Home Screen web app), tap **Back up**.
2. Open the new Axiom app and tap **Restore**, then pick the backup file.

## Notes

- **Signing:** the app is built unsigned, with an ad-hoc signature that lists its app group. SideStore and AltStore sign it with your Apple ID and set up the shared storage between the app and the widgets.
- **App limits:** a free Apple ID allows 3 sideloaded apps at once. The widgets count as a second registration in the weekly limit of 10.
- **Rebuilding:** to update the dashboard inside the app, replace `web/index.html` with the latest `index.html` and push. A new .ipa builds by itself.
