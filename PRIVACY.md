<!--
  No lists: the parser joins consecutive lines into one paragraph. Headings and
  short paragraphs instead.

  PRIVACY.el.md is the same policy in Greek and changes with it.
-->

# Privacy policy

Prosefchi collects nothing about you. There is no account to create, no sign-in,
no analytics, no advertising and no crash reporting. Nothing you do in the app
is sent anywhere, so nobody, including the people who make it, can see which
prayers you read, which reminders you set, or whether you opened the app at all.

This policy covers the Prosefchi app, which appears on your device as Orthodox
Prayer, and the website at prosefchi.org. It is written plainly on purpose:
there is very little to describe, and putting that little into legal wording
would only make it harder to check.

## What is kept on your device

The app remembers the language and text size you chose, whether you have seen
the welcome pages, which reminders you switched on, and the times you set for
them. It also keeps the calendar of saints, feasts and readings that it
downloads, so the day's page and the prayers work with no signal.

All of that is held in the app's own private storage on your device. None of it
is uploaded, and removing the app removes it.

## What the app sends

The calendar of saints, feasts and readings is not built into the app. It is a
file published on this site and fetched when the app is opened, and that request
is the only thing the app sends anywhere.

Asking a server for a file means it sees your device's internet address, the
time of the request and which file was asked for, which is to say which of the
two languages you read. That is the ordinary record any web server keeps of any
request. The app sends no identifier of its own, because it has none, and no
cookies.

The site is served by GitHub Pages, so that record is GitHub's rather than ours.
We are not given those logs and cannot see them. GitHub's
[privacy statement](https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement)
describes what they do with them.

Nothing else the app does touches the network.

## Reminders

Reminders are worked out and scheduled on your device, using the notification
scheduling Android and iOS provide. Nothing is pushed from a server, which is
why a reminder still arrives with no signal, and why the app never learns when
you pray or fast.

The app reads your device's time zone so that a reminder set for seven in the
morning arrives at seven in the morning. That is read on the device and stays
there.

## The website

The website sets no cookies and runs no analytics. Its prayer pages are plain
files. Its day page fetches the same calendar file the app does, from this site,
to work out today's date and readings, and that request is logged by GitHub in
the same way as the app's.

## Links to somewhere else

A prayer names the site its text came from, and the about page links to the
project on GitHub. Following one of those hands you to that site, which is
governed by its own privacy policy rather than by this one.

## Permissions

Notifications, so a reminder you switched on can appear.

Internet access, so the calendar can be downloaded.

Starting at boot, so reminders you have already set are put back after the
device restarts. Without it they would disappear on the first restart.

Vibration, so a reminder can be felt as well as seen.

The app asks for nothing else. It has no access to your contacts, your location,
your camera, your microphone, your files, your accounts, or anything else on the
device.

## Backups

If you have Android's backup turned on, Android may include this app's settings
and reminders in the backup it makes for you. That is a copy of the same data
described above, made by the operating system at your instruction rather than by
the app, and it goes to your own account rather than to us. Android's settings
are where it is turned off.

## Where the app comes from

Installing from Google Play means Google records the install, as it does for
every app. Google reports back to us in aggregate: how many installs there have
been, in which countries, on which kinds of device, and, where you have allowed
Google to share usage and diagnostics, anonymised reports of crashes. None of it
identifies anyone and none of it comes from the app. It is Google's collection,
described in [Google's privacy policy](https://policies.google.com/privacy).

Installing the APK from the project's GitHub releases instead means GitHub sees
the download, in the way any site sees a download.

## Children

The app is for anyone who wants to pray with it. It collects nothing from
anybody of any age, so there is nothing held about a child either.

## Removing what is stored

Uninstalling the app deletes everything it kept. On Android the same can be done
without removing the app, from Settings, then Apps, then this app, then Storage,
then Clear data.

There is nothing held anywhere else to delete, and no request to make of us. We
have nothing of yours.

## Changes to this policy

If this policy changes, the new version is published here and the date below
changes with it. Every change to it is public in the project's history, so what
it said before can always be read.

## Contact

Questions about this policy can be raised as an issue on the project:
[github.com/Prosefchi/prosefchi/issues](https://github.com/Prosefchi/prosefchi/issues).

---

Last updated 1 August 2026.
