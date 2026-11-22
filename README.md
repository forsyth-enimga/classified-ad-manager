# Classified Ad Manager

Keep your classified ads in a local database and export each one as a text file
formatted for **Kijiji, eBay, Facebook Marketplace, VarageSale, Karrot,
Poshmark and Depop** (Canadian versions). Copy and paste from the file into the
platform's "create listing" page. Windows, Linux and Android 8+ (Flutter +
SQLite, single user, no login, no encryption, no photo management).

## Features

- Add, edit, clone, search/filter, move to trash (with confirmation), restore or delete permanently
- Mandatory shared fields: **Title (max 80)**, **Description (max 500)**, **Price**, **Category** (free text)
- Optional shared fields: Condition, Location. Optional platform-only fields in one expandable section per platform
- Per platform: *Posted* checkbox + posted date. *Sold* checkbox, sold-on dropdown (7 platforms + "Local / in person / other"), sold price, sold date
- Relist reminder date (shows a "Relist due" badge and filter)
- Export one platform (`.txt`) or all platforms (`.zip`); a save dialog always asks where to save

## Export format

Only the fields that platform has, in the platform's form order:

```
Ad title
Scott Pilgrim vs The World, Vol 1-6
Description
Line one
Line two
Tags
comics, manga, graphic novel
```

Checkboxes export `Yes`/`No`, lists are comma-joined, line breaks inside values
are kept, empty optional fields get a blank value line. Depop has no title field,
so its single `Description` is title + blank line + description + blank line + hashtags
(1,000 characters and 5 hashtags max; a warning appears before saving if exceeded).

## Build

Requires the Flutter SDK (stable).

```bash
bash tool/setup_platforms.sh          # creates android/windows/linux runners, minSdk 26, pub get
dart run tool/self_check.dart         # core logic checks (no packages needed)
flutter run -d linux                  # or windows / an Android device
```

Installers (also built by `.github/workflows/build.yml` on GitHub Actions):

| Platform | Command | Output |
|---|---|---|
| Android | `flutter build apk --release` | `build/app/outputs/flutter-apk/app-release.apk` |
| Linux | `flutter build linux --release && bash packaging/linux/build_deb.sh 1.0.0` | `build/deb/classified-ad-manager_1.0.0_amd64.deb` |
| Windows | `flutter build windows --release` then `iscc packaging\windows\installer.iss` (Inno Setup 6) | `build/installer/ClassifiedAdManager-Setup-1.0.0.exe` |

Linux needs `libgtk-3-0` and `libsqlite3-0` (declared in the .deb) and `zenity`
(recommended) for the save dialog. The APK is debug-signed; add your own
signing config before publishing it anywhere.

## Layout

- `lib/core/` platform-independent logic: field definitions per marketplace (`marketplaces.dart`), validation, export, zip writer, filters
- `lib/data/ad_repository.dart` SQLite storage (one `ads` table; `posted_<platform>` columns; platform-only values as JSON)
- `lib/ui/` screens: list, form, trash, export
- To change a limit or add/rename a platform field, edit `lib/core/marketplaces.dart`

## Field limits and sources

Title 80 = lowest verified limit (eBay and Poshmark). Description 500 = Poshmark's
lower reported limit (sources disagree with 1,500). Karrot's and Kijiji's own
limits could not be confirmed; if either form cuts off earlier, lower
`kTitleMax` / `kDescriptionMax` in `lib/core/marketplaces.dart`.
