# Orthodox Prayer · Προσευχητάριον

<div align="center">
<a href="https://apps.obtainium.imranr.dev/redirect.html?r=obtainium://add/https://github.com/Prosefchi/prosefchi">
<img src="https://github.com/ImranR98/Obtainium/blob/main/assets/graphics/badge_obtainium.png"
alt="Get it on Obtainium" align="center" height="80" />
</a>
</div>

A Greek Orthodox daily prayer app for Android and iOS. It shows the day's
commemoration and appointed readings, holds the prayer rules, and can remind you
to fast and pray.

The following languages are supported:

| Language       | Supported |
| -------------- | --------- |
| Koine Greek    | **Full**  |
| Modern English | **Full**  |

## Screenshots

<div align="center">
<img src="docs/screenshots/today-en.png" alt="The day's commemoration, tone and readings" width="200" />
<img src="docs/screenshots/morning-en.png" alt="The morning prayer rule" width="200" />
<img src="docs/screenshots/today-el.png" alt="Η ημέρα στα ελληνικά" width="200" />
<img src="docs/screenshots/morning-el.png" alt="Οι πρωινές προσευχές" width="200" />
</div>

## Building

```bash
flutter pub get
flutter run
```

Requires Flutter 3.44 or later.

## Calendar

Saints, feasts and readings come from the calendar published by the
[Greek Orthodox Archdiocese of America](https://www.goarch.org/), fetched and
republished as JSON by a daily GitHub Actions run:

- `https://prosefchi.github.io/prosefchi/calendar.en.json`
- `https://prosefchi.github.io/prosefchi/calendar.el.json`

The app fetches those and keeps a copy on the device. To rebuild them locally:

```bash
dart run tool/build_calendar.dart
```

The Paschalion, the Octoechos tone, the eothinon and the fasting seasons are
also computed on the device, from the date alone. Where the published calendar
states one of them it is preferred; the computation is what the app falls back
on for the dates that calendar may not publish.

## Licence

[GNU AGPL v3](LICENSE).

Calendar content belongs to the Greek Orthodox Archdiocese of America and is not
covered by that licence.
