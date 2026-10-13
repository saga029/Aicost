# Aicost

[简体中文](README.zh-CN.md) · English

A native macOS menu bar app for AI subscription quotas and local token usage.

## Requirements

- Apple Silicon Mac, macOS 15 or newer.
- Existing local accounts/session logs for the providers you use.
- Xcode Command Line Tools and Python 3 when building from source.

## Download

Download **Aicost-1.0.0-macos-arm64.zip** from [Releases](https://github.com/saga029/Aicost/releases), extract it, and move `Aicost.app` to Applications. This initial release uses an ad-hoc signature and is not Apple-notarized; macOS may require approval through Finder / Privacy & Security on first launch.

## Features

- Menu bar quota icons, names and remaining percentages.
- Five-hour windows take priority where available.
- Daily stacked usage, per-app shares and model breakdowns.
- Today, this month, past 7/30 days and custom ranges up to 31 days.
- English and Simplified Chinese, with responsive quota cards.
- Local history, manual refresh and launch-at-login settings.

## Build and test

```sh
python3 scripts/test.py
python3 scripts/build.py
open build/Aicost.app
python3 scripts/package.py
```

The build downloads the public Runway **v0.8.17** release, verifies its pinned SHA-256, and uses only its CLI helper, runtime framework and static resource bundle. The Aicost UI is compiled from this repository. The upstream source is linked in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Data and privacy

Aicost reads local usage metadata from Codex, Claude Code and Antigravity. The bundled Runway CLI can reuse local credentials to request quotas from the corresponding provider. These requests go to the provider, not to an Aicost backend. The optional OpenUsage service is read at `127.0.0.1:6736`.

Usage history is stored in `~/Library/Application Support/Aicost`. Aicost's history cache contains dates, models and numeric usage/cost data, not conversation content or credential values. Aicost does not include an analytics or telemetry backend. See [PRIVACY.md](PRIVACY.md) for the distinction between local processing and provider requests.

## Current limits

- Daily buckets currently use the Asia/Shanghai time zone.
- Token/cost estimates depend on available logs and pricing coverage. Displayed costs are API-equivalent estimates, not subscription invoices.
- Moving or deleting source logs can change historical daily totals.
- Some diagnostic text remains in Chinese; only English and Simplified Chinese are supported.

## License

MIT. Includes MIT-licensed Runway/OpenUsage components and other notices in [licenses/](licenses/) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Aicost is an independent application, not an official client of the listed AI providers.
