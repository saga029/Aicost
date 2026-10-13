# Changelog

## 1.0.1 — 2026-10-13

- Daily usage, date pickers and quota reset times follow the device's current time zone.
- Separate time-zone archives prevent reusing daily totals grouped in another zone; legacy files remain local.
- Date presets advance at local midnight and refresh when the device time zone changes.
- Quota and login-item errors update with the interface language, without including untranslated system descriptions.
- Remove language-specific diagnostic strings from stored source and warning metadata.
- Add pure regression checks across four time zones, DST transitions and both diagnostic languages.

## 1.0.0 — 2026-10-13

Initial public release for Apple Silicon and macOS 15+.

- Native menu bar quotas and usage dashboard.
- Local token history, daily trends, application shares and cost estimates.
- English / Simplified Chinese interface and date-range selection.
- Responsive quota cards and compact summary layout.
- Clean source build, pinned public runtime dependencies and privacy-conscious packaging.
