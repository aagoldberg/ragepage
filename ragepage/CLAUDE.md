# RageCheck Browser Extension

## What this is

Chrome extension that detects rage bait and emotional manipulation in social media posts. Adds inline "Check" buttons to posts, provides a popup analyzer, and context menu integration. All scoring goes through the `ragecheck.com/api/analyze` endpoint.

## Repo structure

```
extension/           # The distributable Chrome extension (Manifest V3)
  manifest.json      # Permissions: activeTab, storage, contextMenus, notifications
  content.js         # Injected into social media pages, adds Check buttons to posts
  content.css        # Styles for buttons, tooltips, signal bars
  background.js      # Service worker: context menus, badge, notifications
  popup/             # Extension popup UI (URL analyzer)
  options/           # Settings page (auto-check, per-platform toggles, API endpoint)
  icons/             # 16/48/128px icons
store/               # Chrome Web Store listing assets
  description.txt    # Store listing copy
  screenshots/       # 1280x800 screenshots (TODO)
  promo/             # Promotional images (TODO)
```

## Currently supported platforms (Tier 1 - curated selectors)

- Twitter / X
- Bluesky
- Facebook
- Reddit
- Threads

## Architecture decisions

**Platform detection**: Each platform has hardcoded CSS selectors in `content.js` under the `PLATFORMS` object. Post detection, URL extraction, and button placement are all platform-specific.

**API**: All analysis goes through `API_BASE/api/analyze` (POST with `{ url }` or `{ text }`). The API returns `{ success, score, label, reasons[], signals{} }`. The `signals` object contains 5 keys: `arousal`, `enemy`, `moral`, `urgency`, `tribal` (each 0-100).

**Settings**: Stored in `chrome.storage.sync`. Content script and background worker both read from storage and listen for changes. Options page writes on every toggle change.

**Badge**: Background worker sets per-tab badge text/color when a score comes back from context menu analysis.

## Planned: Three-tier forum/site coverage

The extension should evolve beyond the 5 hardcoded social platforms:

### Tier 1: Curated selectors
Exact CSS selectors for known platforms/forum engines. Currently: Twitter, Bluesky, Facebook, Reddit, Threads. Next targets: Discourse, Hacker News, XenForo, phpBB, vBulletin, Lemmy, Stack Exchange.

### Tier 2: Generic post detector
Heuristic-based detector for unknown sites. Looks for repeating content blocks with timestamps/usernames. Injects Check buttons with a "beta" indicator. Falls back to this when no Tier 1 config matches the current domain.

### Tier 3: Feedback loop
When the generic detector runs on an unknown forum, it sends lightweight diagnostics back (domain, structure fingerprint, error details). This feeds a dashboard so we can see which forums need proper Tier 1 configs. New configs get added iteratively until coverage is solid.

**Remote config**: Instead of hardcoding all selectors, the extension should fetch a selector manifest from `ragecheck.com/api/selectors` on startup. Hardcoded platforms remain as offline fallbacks. This lets us add forum support without requiring a Chrome Web Store update cycle.

## Commands

- `npm run zip` — packages `extension/` into `ragecheck-extension.zip` for Chrome Web Store upload

## Dev notes

- Switch API to localhost: set `http://localhost:3000` in the extension's Settings page (options UI), or edit `apiBase` in `chrome.storage.sync`
- Load unpacked: go to `chrome://extensions`, enable Developer mode, "Load unpacked" → select the `extension/` directory
- The manifest includes `offline_enabled: false` to be transparent that network is required
- Icons are currently solid purple placeholders — need real branded icons before store submission
