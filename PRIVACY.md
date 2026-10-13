# Privacy

## What the app reads

Aicost analyzes local session usage metadata and provider quota results. Parsing may read existing transcript files, but Aicost's usage cache does not retain their conversation content. Credential discovery and provider requests are handled by the bundled upstream Runway CLI on the user's Mac.

## Network activity

There is no Aicost server, telemetry collection or remote upload endpoint. Quota requests may authenticate directly to the user's AI provider. The upstream helper can download public model pricing. An optional integration reads the local OpenUsage HTTP service on the loopback interface.

## Local storage

Aicost stores numeric usage, dates and model names in Application Support/Aicost and interface preferences in its own macOS preferences domain. The upstream helper may maintain its own local caches/logs. Review [Runway privacy documentation](https://github.com/mstallone/runway/blob/v0.8.17/docs/privacy.md) for upstream behavior.

## Published artifacts

The repository and release package are assembled from source, static artwork, license notices and checksum-verified public upstream binaries. No account databases, credentials, cookies, token history, local configuration, development transcripts or private signing material are bundled. Build and test scripts never package the user's home directory. Tests use generated data and temporary files.
