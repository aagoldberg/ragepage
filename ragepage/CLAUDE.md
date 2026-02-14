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

## Currently supported platforms

**Tier 1 social (auto-injected):** Twitter/X, Bluesky, Facebook, Reddit, Threads, Hacker News, YouTube, Stack Overflow/Exchange

**Tier 1 forum engines (fingerprint-detected):** Discourse, phpBB, XenForo, vBulletin, Lemmy, NodeBB, Flarum, Vanilla Forums, Disqus

**Tier 1.5:** Any site emitting schema.org DiscussionForumPosting structured data

**Tier 2:** Generic heuristic detector (user-initiated via popup/context menu)

## Architecture decisions

**Platform detection**: Four-tier system in `content.js`:
1. Hardcoded `PLATFORMS` object for social media (Twitter, Reddit, etc.) — auto-injected via `content_scripts`
2. Hardcoded `FORUM_ENGINES` object for known forum engines (Discourse, phpBB, XenForo, etc.) — detected by fingerprint (`<meta>` tags, URL patterns, `data-*` attributes), selectors applied if matched
3. Schema.org `DiscussionForumPosting` structured data detection — works on any forum emitting JSON-LD or microdata, no selectors needed
4. Generic heuristic detector — repeating sibling analysis with confidence scoring, falls back to this on unknown sites

**Permission model** (based on Chrome Web Store best practices):
- Ship with `activeTab` + `scripting` + specific Tier 1 URLs in `content_scripts`
- Use `optional_host_permissions: ["https://*/*"]` for everything else
- When user clicks "Scan this page" on an unknown site, call `chrome.permissions.request()` for that origin
- Then inject via `chrome.scripting.executeScript()` and optionally `chrome.scripting.registerContentScripts()` for persistent access
- This avoids scary install warnings and gets faster CWS review vs broad `<all_urls>`

**API**: All analysis goes through `API_BASE/api/analyze` (POST with `{ url }` or `{ text }`). The API returns `{ success, score, label, reasons[], signals{} }`. The `signals` object contains 5 keys: `arousal`, `enemy`, `moral`, `urgency`, `tribal` (each 0-100).

**Settings**: Stored in `chrome.storage.sync`. Content script and background worker both read from storage and listen for changes. Options page writes on every toggle change.

**Badge**: Background worker sets per-tab badge text/color when a score comes back from context menu analysis.

**Remote config**: Background worker fetches `GET ragecheck.com/api/selectors` on startup, caches in `chrome.storage.local` for 24h. Returns JSON with forum engine selectors. Bundled defaults always work offline. Remote data (JSON) is explicitly allowed under MV3 — only remote executable code is banned.

## Whack-a-Mole Strategy: Expanding site coverage

The goal is to work on every site where rage bait lives, not just 5 social platforms. The approach is a self-improving loop: start with known sites, have a generic fallback for everything else, and use real-world failures to tell us what to fix next. Keep going until all the moles are whacked.

### Tier 1: Curated selectors (known platforms + forum engines)

Hand-written CSS selectors for platforms/forum engines where we know the exact DOM structure. These are reliable and fast.

**Social platforms (auto-injected via content_scripts):**
Twitter/X, Bluesky, Facebook, Reddit, Threads, Hacker News, YouTube, Stack Overflow/Exchange

**Forum engines (detected by fingerprint, then selectors applied):**

| Engine | Fingerprint | Post selector | Content selector |
|--------|------------|---------------|------------------|
| Discourse | `<meta name="generator" content="Discourse">` | `article[data-post-id]` | `.cooked` |
| phpBB | `<meta name="copyright" content="phpBB">`, `viewtopic.php` in URL | `div.post` | `.postbody .content` |
| XenForo | `data-xf-init` attributes on elements | `article.message` | `.message-body .bbWrapper` |
| vBulletin 4 | `showthread.php` in URL, `<meta name="generator" content="vBulletin">` | `.postbit, .postbitlegacy` | `.postcontent` |
| vBulletin 5 | `<meta name="generator" content="vBulletin">` | `.b-post` | `.js-post__content-wrapper` |
| Lemmy | `/api/v3/` endpoint, ActivityPub markers | `.post-listing` | comment node elements |
| NodeBB | `data-nbb-*` attributes | `[component="category/post"]` | `[component="post/content"]` |
| Flarum | `flarum` in source/meta | Mithril.js rendered elements | dynamic class patterns |
| Vanilla Forums | `vanilla` in CSS classes | `li.Item` in `ul.MessageList` | `.Message` |
| Disqus | `#disqus_thread` iframe | `.post` inside iframe | `.post-message` |

Each social platform config is an entry in `PLATFORMS` specifying: `host` patterns, `postSelector`, `actionBarSelector`, `getPostUrl()`, and optionally `findPosts()`.

Each forum engine config is an entry in `FORUM_ENGINES` specifying: `detect()` fingerprint function, `postSelector`, `contentSelector`, `authorSelector`, `getPostUrl()`.

**Discourse special handling**: Discourse is an Ember.js SPA. Never cache DOM references (virtual DOM replaces nodes on re-render). Watch `.post-stream` for new `article[data-post-id]` elements. Monitor URL changes for SPA navigation (no `DOMContentLoaded` fires on route change). Re-query selectors on every MutationObserver callback.

### Tier 1.5: Schema.org DiscussionForumPosting

Many modern forums emit schema.org structured data as JSON-LD or microdata. Google recommends `DiscussionForumPosting` markup. The extension checks for this before falling back to heuristics — it's a free, platform-agnostic detection layer that works on any compliant forum without needing custom selectors.

### Tier 2: Generic post detector (unknown sites)

When no Tier 1/1.5 config matches, a heuristic detector adapted from the Readability.js algorithm kicks in. It is user-initiated only (via popup "Scan this page" or context menu), never auto-injected.

**Detection algorithm:**
1. Check for schema.org `DiscussionForumPosting` JSON-LD or microdata (if found, use those elements directly — skip to step 5)
2. Find all repeating sibling groups: elements sharing the same parent, tag name, and class structure, appearing 3+ times
3. Score each candidate group:
   - Has timestamps or relative time strings (+20)
   - Has avatar images (small square images near text) (+15)
   - Has author/profile links (+15)
   - Has reply/action buttons (+10)
   - Class/ID names contain `post`, `comment`, `reply`, `message`, `thread`, `discussion` (+25)
   - Text density is reasonable: >50 chars per block, link density <0.5 (+10)
   - Has `<article>` or `<li>` elements (+5)
4. Select highest-scoring group as "posts"; require minimum confidence threshold of 40
5. Inject Check buttons with a `ragecheck-beta` visual indicator (dotted border) so user knows it's best-effort
6. If confidence too low, don't inject — still log attempt for Tier 3 diagnostics

**Negative signals (skip these elements):**
- `<nav>`, `<header>`, `<footer>` elements
- Very short text (<20 chars)
- High link density (>0.5 ratio of link text to total text)
- Elements matching sidebar/ad patterns

**Gating rules:**
- Never auto-runs — only activated by user action (popup button or context menu)
- Uses `activeTab` + `scripting` permissions → `chrome.scripting.executeScript()` for on-demand injection
- If user wants persistent access, `chrome.permissions.request()` escalates to that origin and `chrome.scripting.registerContentScripts()` adds it permanently

### Tier 3: Feedback loop (the whack-a-mole engine)

This is what makes the system self-improving. When the generic detector runs on an unknown site, it reports back:

**What gets reported (lightweight, privacy-respecting):**
- Domain name (e.g., `forum.example.com`) — NOT the full URL or page content
- Forum engine fingerprint: detected CMS/platform if identifiable (e.g., "Discourse", "vBulletin", "unknown")
- Detection outcome: `success` (user clicked a Check button, so placement was correct), `ignored` (buttons placed but user didn't interact), `failed` (no posts detected), `error` (JS error during detection)
- DOM structure hint: the tag/class pattern of the repeating blocks found (e.g., `div.post-content` repeated 12x) — just the selector, not the content
- Timestamp

**What does NOT get reported:**
- No page content, post text, or URLs beyond the domain
- No user browsing history
- No PII

**The feedback dashboard (server-side on ragecheck.com):**
- Aggregates reports by domain and forum engine
- Surfaces the highest-impact targets: "43 users hit `community.example.com` (Discourse) this week, generic detector succeeded 60% of the time"
- Prioritizes: high traffic + low success rate = write a Tier 1 config next
- Shows error patterns so we can fix generic detector bugs

**The iteration cycle:**
1. Users browse forums naturally → generic detector tries its best
2. Diagnostics flow back to the dashboard
3. We review the top failing/partial domains weekly
4. Write a Tier 1 config for the forum engine (or specific domain if it's custom)
5. Ship via remote config (instant) or extension update
6. That domain graduates from Tier 2 → Tier 1
7. Repeat — the long tail shrinks with every cycle

### Remote selector config

The extension fetches a selector manifest on startup. Under MV3, remote JSON data is explicitly allowed — only remote executable code is banned.

**Endpoint:** `GET ragecheck.com/api/selectors`

**Response format:**
```json
{
  "version": 12,
  "engines": {
    "discourse": {
      "detect": "meta[name='generator'][content*='Discourse']",
      "postSelector": "article[data-post-id]",
      "contentSelector": ".cooked",
      "authorSelector": ".names .username",
      "getPostUrlPattern": "a[href*='/t/']",
      "spa": true
    }
  }
}
```

**Behavior:**
- Fetched by background worker on startup, cached in `chrome.storage.local` for 24h
- Content script reads cached config from storage on init
- Bundled `FORUM_ENGINES` in content.js always work offline as fallback
- Remote configs merge on top of bundled ones — remote can fix a broken selector instantly without CWS update
- Version number in response; extension only re-downloads when version changes
- No unique user identifiers sent in config requests (CWS compliance)

### Opt-in telemetry

The Tier 3 feedback loop requires user consent:
- Off by default
- Toggle in options page: "Help improve RageCheck by reporting which sites work and which don't (no page content is sent)"
- When off, the generic detector still works locally — it just doesn't report back
- When on, only the lightweight diagnostic payload described above is sent

### Other surfaces to consider (future)

Beyond forums, rage bait lives in:
- **News site comments** (Disqus is the big one — single Tier 1 config covers thousands of sites)
- **YouTube comments** (standardized DOM, high value)
- **Email/newsletters** (Substack especially — would need different injection approach)
- **Messaging web apps** (Slack, Discord, Telegram web — group chats get heated)
- **Search results** (show rage score next to Google/Bing results before you click — highest-impact but different architecture, would score headlines/snippets)

These are listed roughly in order of feasibility. Disqus and YouTube comments are low-hanging fruit since they have standardized DOMs.

## Best practices (from research)

These informed the architecture and should guide future changes:

**MutationObserver performance:**
- Scope narrow: observe the post container (e.g., `.post-stream`), not `document.body`, whenever possible
- Debounce callbacks (200ms) and use `requestIdleCallback` for non-urgent post scanning
- Use `WeakSet` to deduplicate processed posts (already implemented)
- Consider `IntersectionObserver` to only process visible posts (RES pattern) — reduces work on infinite scroll
- For Discourse and other SPAs: never cache DOM references, re-query on each callback batch

**Chrome Web Store review:**
- `<all_urls>` in `content_scripts` or `host_permissions` triggers longer review and scary install warnings
- `activeTab` + `scripting` + `optional_host_permissions` is the preferred pattern
- Remote JSON config is allowed; remote executable JS is banned
- No unique user IDs in config/telemetry requests
- No obfuscated code (minified is fine)
- Permissions must be justified by features — request only what's used

**Forum engine handling:**
- Detect engine first via fingerprint (meta tags, URL patterns, data attributes), then apply known selectors
- Schema.org `DiscussionForumPosting` is a free detection layer — check JSON-LD and microdata before heuristics
- Discourse is Ember SPA: watch for URL changes, re-query selectors, observe `.post-stream`
- Self-hosted engines (phpBB, XenForo, vBulletin) can't have hosts listed in manifest — use fingerprint detection + remote config

**Patterns from other extensions:**
- RES: IntersectionObserver + WeakSet dedup, processes ~screen-height worth of posts on initial paint
- uBlock: two-tier selector system (specific per-host + generic), DOM surveyor with class/ID hashing
- Grammarly: coordinate-based overlay positioning (avoid polluting host DOM), Shadow DOM for isolation

## Commands

- `npm run zip` — packages `extension/` into `ragecheck-extension.zip` for Chrome Web Store upload

## Dev notes

- Switch API to localhost: set `http://localhost:3000` in the extension's Settings page (options UI), or edit `apiBase` in `chrome.storage.sync`
- Load unpacked: go to `chrome://extensions`, enable Developer mode, "Load unpacked" → select the `extension/` directory
- The manifest includes `offline_enabled: false` to be transparent that network is required
- Icons are currently solid purple placeholders — need real branded icons before store submission
