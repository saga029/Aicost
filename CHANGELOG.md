# Changelog

## 1.0.2 — 2026-10-19

- The menu bar shows the 5-hour balance while the weekly and monthly allowances remain, or the monthly balance when there is no 5-hour window. A used-up weekly or monthly allowance replaces that figure with 0% and the 5-hour balance leaves the menu bar.
- Subscription cards keep 5-hour, weekly and monthly windows.
- A 30-day Codex window is labeled monthly even when the provider places it in the session slot.
- Usage details list every active subscription as an icon.
- Grok model rows come from local session usage, including days after the OpenUsage cache.
- Antigravity shows Gemini 5-hour and weekly quotas, using optional local `agy` or the direct-provider fallback. Partial responses retain known weekly windows; the other-model pool stays off the card when Gemini is available.
- Positive sub-percent quotas show `<1%` and do not hide the session as exhausted.
- Reject oversized/truncated protobuf fields, overflowing token counts, invalid timestamps and negative/non-finite Grok usage.
- Bound local helper stdout, execution time and forced termination, including processes whose children keep stdout open.
- Preserve localized window names when quota IDs collide after normalization.
- Keep optional Codex Spark limits separate so they do not mark the regular Codex pool as exhausted.
- Verify the built application's identity and version before packaging.
- Document optional Antigravity credential discovery and provider requests.

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
