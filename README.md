<div align="center">

# UmamiBar

**Your Umami analytics, one click away in the macOS menu bar.**

[Download](https://github.com/gentpan/UmamiBar/releases/latest) · [中文说明](README.zh-CN.md) · [Report an issue](https://github.com/gentpan/UmamiBar/issues)

<img src="docs/screenshot.png" alt="UmamiBar menu bar dashboard with example websites and a two-tone traffic chart" width="392">

*The screenshot uses synthetic demonstration data.*

</div>

UmamiBar is a native SwiftUI companion for [Umami](https://umami.is). See live visitors, pageviews and visits without opening a browser, then expand a website to inspect its traffic, top pages and referrers. The app lives in the menu bar and opens a compact panel beneath its icon.

## What you can do

- **Focus on the sites you care about.** Display all accessible websites or select a few. Select just one and its details open automatically.
- **Read traffic at a glance.** Each time slot has one two-tone column: deeper blue for visitors, lighter blue for pageviews. The metrics share a baseline; their values are not added together.
- **See the whole day.** Today always reserves 24 hourly positions from 00:00 to 23:00. Missing and future hours stay empty, so early-day bars keep their normal width.
- **Explore the details.** View the five leading pages and referrers, plus live visitor counts and changes against the comparison period returned by Umami.
- **Choose your time range.** Today, last 24 hours, last 7 days, last 30 days or this month, using your Mac's local time zone.
- **Keep it simple.** An opaque panel, a small black logo, aligned cards and hidden scroll indicators. Refresh shows one loading indicator at the refresh button.
- **Use either hosting option.** Connect to a self-hosted Umami server or Umami Cloud. English and Simplified Chinese interfaces are included.

## Install

The downloadable build requires **macOS 26 or later** and an **Apple silicon Mac**.

1. Download **UmamiBar-macOS.zip** from the [latest release](https://github.com/gentpan/UmamiBar/releases/latest).
2. Extract the archive and move **UmamiBar.app** to your Applications folder.
3. Open the app, then click the chart icon in the menu bar.
4. Open the panel's gear button to configure your connection.

Published release builds are signed with a **Developer ID Application** certificate, notarized by Apple and include a stapled notarization ticket. A source build needs its own signing and notarization before distribution.

## Connect your account

| Hosting | What to enter |
| --- | --- |
| Self-hosted | Your server URL and username/password, or an API key on servers that support it. A URL ending in `/api` is also accepted. |
| Umami Cloud | Your Cloud API key and region: Auto, US or EU. Create a key in Umami Cloud → Settings → API keys. |

Click **Test Connection**, then **Save**. Passwords and API keys are stored in macOS Keychain; login tokens stay in memory. Credentials are not written into the app bundle or repository.

Interactive two-factor authentication is not supported. For a self-hosted account requiring it, use an API key if your server supports that authentication method.

### Pick the websites to display

Open **Settings → Displayed websites**, choose **All websites** or **Selected websites**, and save your selection. At least one selected website is required. Hiding a website only changes this app's panel; it does not delete the website from Umami.

When one site is selected, opening the panel expands its details. If you manually collapse it, a scheduled refresh respects that choice. The next panel opening expands it again.

### Refresh and startup

Refresh manually from the panel, or choose an automatic interval of 30 seconds, 1 minute or 5 minutes. Enable **Launch at login** in Settings after moving the app to its permanent location. If macOS requests approval, allow it in System Settings → General → Login Items.

## Build from source

Requires macOS 26+, Xcode 26+ and Swift 6.2+. The package has no third-party dependencies.

```sh
git clone https://github.com/gentpan/UmamiBar.git
cd UmamiBar
make test
make build
open build/UmamiBar.app
```

| Command | Result |
| --- | --- |
| `make test` | Runs model, API and application-flow tests. |
| `make build` | Creates and verifies `build/UmamiBar.app`. |
| `make run` | Builds and launches the menu bar app. |
| `make preview` | Opens a preview with labeled demonstration data. |
| `make clean` | Removes local build products. |

The build script selects an available Developer ID certificate, then a configured local development certificate, then ad-hoc signing. It does not automatically notarize source builds. Never commit certificates, private keys or signing credentials.

The preview uses separate preferences and in-memory credentials. **Connect for preview** can inspect a real connection temporarily; exit the preview and use the normal application to save a permanent connection.

## Reliability and privacy

- Summary failures are shown per website. Existing statistics may remain visible, but failed live counts are cleared and incomplete refreshes do not claim a new successful update time.
- Detail failures offer Retry. Old results cannot overwrite a newer time range or connection.
- Concurrent refreshes are coalesced; Cloud requests are paced and rate-limited responses receive a bounded retry.
- Requests go to the Umami server you configure. The app does not add a separate analytics service.
- Automated tests use simulated responses. Self-hosted login, saved credentials and the menu panel have also been checked against a live server; Cloud has been checked with simulated API responses.

## Project layout

```text
Sources/UmamiBar/       SwiftUI panel, settings, charts and app state
Sources/UmamiBarCore/   Umami client, models, settings and Keychain storage
Resources/             App metadata, icon and translations
Tests/UmamiBarTests/    Regression tests
Scripts/               App packaging and icon generation
```

## Contributing

For a bug report, include your macOS version, Umami hosting type/version, selected time range and steps to reproduce. Please redact server credentials, tokens and private analytics from screenshots or logs. For code changes, run `make test` and check the real menu panel before opening a pull request.
