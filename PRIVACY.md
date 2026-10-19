# Privacy

## What the app reads

Aicost analyzes local session usage metadata and provider quota results, including Grok's local session usage files. Parsing may read existing transcript files, but Aicost's usage cache does not retain their conversation content. Most credential discovery and provider requests are handled by the bundled upstream Runway CLI on the user's Mac.

For Antigravity's Gemini quotas, Aicost can also invoke an already installed `agy` CLI with the `/usage` command. It runs outside the current project directory, with no user conversation text. This CLI is optional and is not bundled with Aicost. Subscription labels can be read from the running client or CLI loopback status API. When starting the CLI for usage, Aicost supplies a new local CSRF token and keeps only the parsed plan label, without exporting OAuth credentials or caching the status response. If Gemini quotas are unavailable, Aicost can read an unexpired token from the local Runway Antigravity authentication file and request quota metadata directly from Google's Cloud Code service. Aicost does not copy that token into its history cache, repository or release package.

Antigravity token totals are read from the local conversation databases of the desktop app, the Antigravity IDE and the `agy` CLI: `~/.gemini/antigravity/conversations`, `~/.gemini/antigravity-ide/conversations` and `~/.gemini/antigravity-cli/conversations`. Aicost keeps the numeric usage metadata and does not copy conversation text into its history cache.

## Network activity

There is no Aicost server, telemetry collection or remote upload endpoint. Quota requests may authenticate directly to the user's AI provider, including Google's `daily-cloudcode-pa.googleapis.com` and `cloudcode-pa.googleapis.com` quota endpoints for the Antigravity fallback. The upstream helper can download public model pricing. An optional integration reads the local OpenUsage HTTP service on the loopback interface.

## Local storage

Aicost stores numeric usage, dates and model names in Application Support/Aicost and interface preferences in its own macOS preferences domain. Claude per-file caches also contain file size/modification stamps and SHA-256 hashes of message identities for deduplication; they contain no raw message IDs or conversation text. The upstream helper may maintain its own local caches/logs. Review [Runway privacy documentation](https://github.com/mstallone/runway/blob/v0.8.17/docs/privacy.md) for upstream behavior.

## Published artifacts

The repository and release package are assembled from source, static artwork, license notices and checksum-verified public upstream binaries. No account databases, credentials, cookies, token history, local configuration, development transcripts or private signing material are bundled. Build and test scripts never package the user's home directory. Tests use generated data and temporary files.
