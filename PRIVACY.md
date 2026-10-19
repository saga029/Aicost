# Privacy

## What the app reads

Aicost analyzes local session usage metadata and provider quota results, including Grok's local session usage files. Parsing may read existing transcript files, but Aicost's usage cache does not retain their conversation content. Most credential discovery and provider requests are handled by the bundled upstream Runway CLI on the user's Mac.

For Antigravity's Gemini quotas, Aicost can also invoke an already installed `agy` CLI with the `/usage` command. It runs outside the current project directory, with no user conversation text. This CLI is optional and is not bundled with Aicost. If Gemini quotas are unavailable, Aicost can read an unexpired token from the local Runway Antigravity authentication file and request quota metadata directly from Google's Cloud Code service. Aicost does not copy that token into its history cache, repository or release package.

## Network activity

There is no Aicost server, telemetry collection or remote upload endpoint. Quota requests may authenticate directly to the user's AI provider, including Google's `daily-cloudcode-pa.googleapis.com` and `cloudcode-pa.googleapis.com` quota endpoints for the Antigravity fallback. The upstream helper can download public model pricing. An optional integration reads the local OpenUsage HTTP service on the loopback interface.

## Local storage

Aicost stores numeric usage, dates and model names in Application Support/Aicost and interface preferences in its own macOS preferences domain. The upstream helper may maintain its own local caches/logs. Review [Runway privacy documentation](https://github.com/mstallone/runway/blob/v0.8.17/docs/privacy.md) for upstream behavior.

## Published artifacts

The repository and release package are assembled from source, static artwork, license notices and checksum-verified public upstream binaries. No account databases, credentials, cookies, token history, local configuration, development transcripts or private signing material are bundled. Build and test scripts never package the user's home directory. Tests use generated data and temporary files.
