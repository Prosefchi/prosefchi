# Orthodox Prayer · Προσευχητάριον

<div align="center">
<a href="https://apps.obtainium.imranr.dev/redirect.html?r=obtainium://add/https://github.com/Prosefchi/prosefchi">
<img src="https://github.com/ImranR98/Obtainium/blob/main/assets/graphics/badge_obtainium.png"
alt="Get it on Obtainium" align="center" height="80" />
</a>
</div>

A Greek Orthodox daily prayer app for Android and iOS. It shows the day's commemoration and appointed readings, holds the prayer rules, and can remind you to pray. English and Greek.

Everything works offline once the calendar has been downloaded, and reminders are scheduled on the device — nothing is pushed from a server, and the app collects nothing.

## Building

```bash
flutter pub get
flutter run
```

Requires Flutter 3.44 or later.

## The calendar

Saints, feasts and readings come from the calendar published by the [Greek Orthodox Archdiocese of America](https://www.goarch.org/), fetched and republished as JSON by a daily GitHub Actions run:

```
https://prosefchi.github.io/prosefchi/calendar.en.json
https://prosefchi.github.io/prosefchi/calendar.el.json
```

The app fetches those and keeps a copy on the device. To rebuild them locally:

```bash
dart run tool/build_calendar.dart
```

The Paschalion, the Octoechos tone, the eothinon and the fasting seasons are computed from the date rather than fetched, so the app still has something to show for dates the published calendar does not reach.

## Status

Early. The prayer texts are not written: only the opening Trisagion sequence is in place, and every other rule is a marked placeholder under `res/prayers/`. Those need texts chosen by someone qualified to choose them.

## Licence

[GNU AGPL v3](LICENSE).

Calendar content belongs to the Greek Orthodox Archdiocese of America and is not covered by that licence.
