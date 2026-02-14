// RageCheck Content Script
// Multi-tier post detection: Tier 1 (platforms + forum engines), Tier 1.5 (schema.org), Tier 2 (heuristic)

const DEFAULT_API_BASE = 'https://ragecheck.com';

// --- Settings ---

let API_BASE = DEFAULT_API_BASE;
let autoCheck = false;
let telemetryEnabled = false;
let enabledPlatforms = {
  twitter: true, bluesky: true, facebook: true, reddit: true, threads: true,
  hackernews: true, youtube: true, stackoverflow: true
};

chrome.storage.sync.get(['apiBase', 'autoCheck', 'enabledPlatforms', 'telemetry'], (s) => {
  if (s.apiBase) API_BASE = s.apiBase;
  if (s.autoCheck !== undefined) autoCheck = s.autoCheck;
  if (s.enabledPlatforms) enabledPlatforms = { ...enabledPlatforms, ...s.enabledPlatforms };
  if (s.telemetry !== undefined) telemetryEnabled = s.telemetry;
});

chrome.storage.onChanged.addListener((changes) => {
  if (changes.apiBase) API_BASE = changes.apiBase.newValue || DEFAULT_API_BASE;
  if (changes.autoCheck) autoCheck = changes.autoCheck.newValue;
  if (changes.enabledPlatforms) enabledPlatforms = { ...enabledPlatforms, ...changes.enabledPlatforms.newValue };
  if (changes.telemetry) telemetryEnabled = changes.telemetry.newValue;
});

// --- Remote config ---

let remoteEngines = {};
chrome.storage.local.get(['selectorConfig'], (r) => {
  if (r.selectorConfig?.engines) remoteEngines = r.selectorConfig.engines;
});
chrome.storage.onChanged.addListener((changes) => {
  if (changes.selectorConfig?.newValue?.engines) remoteEngines = changes.selectorConfig.newValue.engines;
});

// ============================================================
// TIER 1: Social media platforms (auto-injected via content_scripts)
// ============================================================

const PLATFORMS = {
  twitter: {
    host: ['twitter.com', 'x.com'],
    postSelector: 'article[data-testid="tweet"]',
    actionBarSelector: '[role="group"]:last-of-type',
    getPostUrl: (post) => {
      const timeLink = post.querySelector('a[href*="/status/"]');
      return timeLink ? timeLink.href : null;
    },
    getPostText: (post) => {
      const tweetText = post.querySelector('[data-testid="tweetText"]');
      return tweetText ? tweetText.innerText.trim() : '';
    }
  },
  bluesky: {
    host: ['bsky.app'],
    postSelector: null,
    actionBarSelector: null,
    getPostUrl: (post) => {
      const links = post.querySelectorAll('a[href*="/post/"]');
      for (const link of links) {
        const href = link.getAttribute('href');
        if (href?.includes('/post/')) {
          return href.startsWith('http') ? href : 'https://bsky.app' + href;
        }
      }
      return null;
    },
    getPostText: (post) => {
      // Bluesky post text is typically in a div with dir="auto" or the main text block
      const textEls = post.querySelectorAll('[dir="auto"]');
      const texts = [];
      textEls.forEach(el => {
        const t = el.innerText.trim();
        if (t.length > 20) texts.push(t);
      });
      return texts.join('\n').trim();
    },
    findPosts: () => {
      const posts = [];
      document.querySelectorAll('a[href*="/post/"]').forEach(link => {
        let container = link.parentElement;
        let depth = 0;
        while (container && depth < 10) {
          if (container.querySelector('svg') &&
              container.textContent.length > 50 &&
              !posts.includes(container)) {
            const buttons = container.querySelectorAll('button, [role="button"]');
            if (buttons.length >= 3) {
              posts.push(container);
              break;
            }
          }
          container = container.parentElement;
          depth++;
        }
      });
      return posts;
    }
  },
  facebook: {
    host: ['www.facebook.com'],
    postSelector: '[data-pagelet*="FeedUnit"], [role="article"]',
    actionBarSelector: '[role="button"]',
    getPostUrl: (post) => {
      const link = post.querySelector('a[href*="/posts/"], a[href*="permalink"]');
      return link ? link.href : null;
    },
    getPostText: (post) => {
      const textEl = post.querySelector('[data-ad-preview="message"], [data-ad-comet-preview="message"]');
      if (textEl) return textEl.innerText.trim();
      // Fallback: grab the largest text block in the post
      let best = '';
      post.querySelectorAll('div[dir="auto"]').forEach(el => {
        const t = el.innerText.trim();
        if (t.length > best.length) best = t;
      });
      return best;
    }
  },
  reddit: {
    host: ['www.reddit.com'],
    postSelector: 'shreddit-post, [data-testid="post-container"]',
    actionBarSelector: '[slot="post-actions"], [data-testid="post-bottom-bar"]',
    getPostUrl: (post) => {
      const link = post.querySelector('a[href*="/comments/"]');
      return link ? link.href : window.location.href;
    },
    getPostText: (post) => {
      // shreddit-post: title is in an <a> or <h1>, body in a text-neutral-content div
      const title = post.getAttribute('post-title') || post.querySelector('h1, [slot="title"]')?.innerText || '';
      const body = post.querySelector('[slot="text-body"], [data-testid="post-content"], .md')?.innerText || '';
      return (title + '\n' + body).trim();
    }
  },
  threads: {
    host: ['www.threads.net'],
    postSelector: '[data-pressable-container="true"]',
    actionBarSelector: '[role="button"]',
    getPostUrl: (post) => {
      const link = post.querySelector('a[href*="/post/"]');
      return link ? 'https://www.threads.net' + link.getAttribute('href') : null;
    },
    getPostText: (post) => {
      const textEl = post.querySelector('[dir="auto"]');
      return textEl ? textEl.innerText.trim() : '';
    }
  },
  hackernews: {
    host: ['news.ycombinator.com'],
    postSelector: '.athing.comtr',
    actionBarSelector: '.reply',
    getPostUrl: (post) => {
      const id = post.getAttribute('id');
      return id ? `https://news.ycombinator.com/item?id=${id}` : null;
    },
    getPostText: (post) => {
      const commText = post.querySelector('.commtext');
      return commText ? commText.innerText.trim() : '';
    },
    findPosts: () => {
      return document.querySelectorAll('.athing.comtr');
    }
  },
  youtube: {
    host: ['www.youtube.com'],
    postSelector: 'ytd-comment-thread-renderer',
    actionBarSelector: '#action-buttons',
    getPostUrl: () => window.location.href,
    getPostText: (post) => {
      const content = post.querySelector('#content-text');
      return content ? content.innerText.trim() : '';
    },
    findPosts: () => document.querySelectorAll('ytd-comment-thread-renderer')
  },
  stackoverflow: {
    host: ['stackoverflow.com', 'stackexchange.com'],
    postSelector: '.answer, .question',
    actionBarSelector: '.js-post-menu',
    getPostUrl: (post) => {
      const link = post.querySelector('.js-share-link, a[href*="/a/"], a[href*="/q/"]');
      return link ? link.href : window.location.href;
    },
    getPostText: (post) => {
      const body = post.querySelector('.js-post-body, .postcell .post-text');
      return body ? body.innerText.trim() : '';
    }
  }
};

// ============================================================
// TIER 1: Forum engines (detected by fingerprint)
// ============================================================

const FORUM_ENGINES = {
  discourse: {
    detect: () => !!document.querySelector('meta[name="generator"][content*="Discourse"]') ||
                  document.body.classList.contains('discourse'),
    postSelector: 'article[data-post-id]',
    contentSelector: '.cooked',
    authorSelector: '.names .username',
    actionBarSelector: '.post-controls',
    getPostUrl: (post) => {
      const num = post.dataset.postNumber;
      return num ? window.location.href.replace(/\/\d+$/, '') + '/' + num : window.location.href;
    },
    spa: true,
    observeTarget: '.post-stream'
  },
  phpbb: {
    detect: () => !!document.querySelector('meta[name="copyright"][content*="phpBB"]') ||
                  window.location.href.includes('viewtopic.php'),
    postSelector: 'div.post',
    contentSelector: '.postbody .content',
    authorSelector: '.postprofile .username, .postprofile .username-coloured',
    actionBarSelector: '.postbody .post-buttons',
    getPostUrl: (post) => {
      const link = post.querySelector('.post-buttons a[href*="viewtopic"]');
      return link ? link.href : window.location.href;
    }
  },
  xenforo: {
    detect: () => !!document.querySelector('[data-xf-init]') ||
                  !!document.querySelector('html[data-app="public"]'),
    postSelector: 'article.message',
    contentSelector: '.message-body .bbWrapper',
    authorSelector: 'h4.message-name',
    actionBarSelector: '.message-actionBar',
    getPostUrl: (post) => {
      const link = post.querySelector('a[href*="/post-"]');
      return link ? link.href : window.location.href;
    }
  },
  vbulletin: {
    detect: () => !!document.querySelector('meta[name="generator"][content*="vBulletin"]') ||
                  window.location.href.includes('showthread.php'),
    postSelector: '.postbit, .postbitlegacy, .b-post',
    contentSelector: '.postcontent, .js-post__content-wrapper',
    authorSelector: '.username',
    actionBarSelector: '.postfoot',
    getPostUrl: (post) => {
      const link = post.querySelector('a[href*="showthread.php"], a[href*="#post"]');
      return link ? link.href : window.location.href;
    }
  },
  lemmy: {
    detect: () => !!document.querySelector('a[href*="/api/v3/"]') ||
                  !!document.querySelector('[class*="comment-node"]'),
    postSelector: '.post-listing, [class*="comment-node"]',
    contentSelector: '.md-div, .post-body',
    authorSelector: 'a[href*="/u/"]',
    actionBarSelector: '.post-bottom-bar',
    getPostUrl: (post) => {
      const link = post.querySelector('a[href*="/post/"], a[href*="/comment/"]');
      return link ? link.href : window.location.href;
    }
  },
  nodebb: {
    detect: () => !!document.querySelector('[data-nbb-module]') ||
                  !!document.querySelector('[component="category/post"]'),
    postSelector: '[component="post"]',
    contentSelector: '[component="post/content"]',
    authorSelector: '[component="post/header"] a',
    actionBarSelector: '[component="post/tools"]',
    getPostUrl: (post) => {
      const link = post.querySelector('[component="post/header"] a[href*="/topic/"]');
      return link ? link.href : window.location.href;
    }
  },
  flarum: {
    detect: () => !!document.querySelector('#flarum-loading') ||
                  !!document.querySelector('div[id="app"] .PostStream'),
    postSelector: '.PostStream-item article',
    contentSelector: '.Post-body',
    authorSelector: '.PostUser-name',
    actionBarSelector: '.Post-actions',
    getPostUrl: () => window.location.href
  },
  vanilla: {
    detect: () => !!document.querySelector('ul.MessageList') ||
                  !!document.querySelector('.vanilla'),
    postSelector: 'ul.MessageList li.Item',
    contentSelector: '.Message',
    authorSelector: '.Author a',
    actionBarSelector: '.Meta',
    getPostUrl: (post) => {
      const link = post.querySelector('a[href*="/discussion/"]');
      return link ? link.href : window.location.href;
    }
  },
  disqus: {
    detect: () => !!document.querySelector('#disqus_thread iframe'),
    // Disqus runs in an iframe — we can detect it but can't inject into it directly
    // We mark the page as having Disqus and let the user know via popup
    postSelector: null,
    note: 'Disqus comments run in a cross-origin iframe and cannot be directly injected into.'
  }
};

// ============================================================
// TIER 1.5: Schema.org DiscussionForumPosting detection
// ============================================================

function detectSchemaOrgPosts() {
  const posts = [];

  // Check JSON-LD
  document.querySelectorAll('script[type="application/ld+json"]').forEach(script => {
    try {
      const data = JSON.parse(script.textContent);
      const items = Array.isArray(data) ? data : [data];
      items.forEach(item => {
        if (item['@type'] === 'DiscussionForumPosting' || item['@type'] === 'Comment') {
          posts.push({ type: 'jsonld', data: item });
        }
        // Check nested comments
        if (item.comment) {
          const comments = Array.isArray(item.comment) ? item.comment : [item.comment];
          comments.forEach(c => posts.push({ type: 'jsonld', data: c }));
        }
      });
    } catch (e) { /* invalid JSON-LD, skip */ }
  });

  // Check microdata
  document.querySelectorAll('[itemtype*="DiscussionForumPosting"], [itemtype*="Comment"]').forEach(el => {
    posts.push({ type: 'microdata', element: el });
  });

  return posts;
}

// ============================================================
// TIER 2: Generic heuristic post detector
// ============================================================

const POST_CLASS_PATTERNS = /\b(post|comment|reply|message|thread|discussion|entry|review|response)\b/i;
const TIMESTAMP_PATTERNS = /\b(\d+\s*(minutes?|hours?|days?|weeks?|months?|years?)\s*ago|ago|just now)\b/i;
const TIMESTAMP_SELECTORS = 'time, [datetime], [data-time], .timestamp, .time, .date, .age, .timeago, [class*="time"], [class*="date"]';
const AVATAR_SELECTORS = 'img[src*="avatar"], img[src*="profile"], img[class*="avatar"], img[class*="profile"], .avatar img, .user-avatar img';
const AUTHOR_SELECTORS = 'a[href*="/user/"], a[href*="/profile/"], a[href*="/u/"], a[href*="/member/"], a[href*="/author/"], [class*="author"], [class*="username"]';

function genericDetectPosts() {
  const candidateGroups = [];

  // Find repeating sibling groups
  const containers = document.querySelectorAll('main, article, section, [role="main"], #content, .content, #comments, .comments, .posts, .thread, .forum, body');

  for (const container of containers) {
    // Group children by tag+class signature
    const groups = {};
    for (const child of container.children) {
      if (child.tagName === 'SCRIPT' || child.tagName === 'STYLE' || child.tagName === 'NAV' ||
          child.tagName === 'HEADER' || child.tagName === 'FOOTER') continue;

      const sig = child.tagName + '.' + (child.className?.toString().split(/\s+/).sort().join('.') || '_');
      if (!groups[sig]) groups[sig] = [];
      groups[sig].push(child);
    }

    // Only consider groups with 3+ siblings
    for (const [sig, elements] of Object.entries(groups)) {
      if (elements.length < 3) continue;
      candidateGroups.push({ elements, sig, container });
    }
  }

  // Score each candidate group
  let bestGroup = null;
  let bestScore = 0;

  for (const group of candidateGroups) {
    let score = 0;
    const sample = group.elements.slice(0, 5); // sample first 5

    let hasTimestamps = 0;
    let hasAvatars = 0;
    let hasAuthors = 0;
    let hasActionButtons = 0;
    let hasGoodText = 0;

    for (const el of sample) {
      const text = el.textContent || '';
      if (text.length > 50 && text.length < 50000) hasGoodText++;

      // Check link density (ratio of link text to total text)
      const linkText = Array.from(el.querySelectorAll('a')).reduce((sum, a) => sum + (a.textContent?.length || 0), 0);
      const linkDensity = text.length > 0 ? linkText / text.length : 1;
      if (linkDensity > 0.5) continue; // skip nav-heavy elements

      if (el.querySelector(TIMESTAMP_SELECTORS) || TIMESTAMP_PATTERNS.test(text)) hasTimestamps++;
      if (el.querySelector(AVATAR_SELECTORS)) hasAvatars++;
      if (el.querySelector(AUTHOR_SELECTORS)) hasAuthors++;
      if (el.querySelector('button, [role="button"], a[class*="reply"], a[class*="vote"]')) hasActionButtons++;
    }

    const n = sample.length;
    if (hasTimestamps > n * 0.5) score += 20;
    if (hasAvatars > n * 0.3) score += 15;
    if (hasAuthors > n * 0.5) score += 15;
    if (hasActionButtons > n * 0.3) score += 10;
    if (hasGoodText > n * 0.6) score += 10;

    // Class/ID name bonus
    if (POST_CLASS_PATTERNS.test(group.sig)) score += 25;

    // Article/li elements bonus
    if (group.elements[0].tagName === 'ARTICLE' || group.elements[0].tagName === 'LI') score += 5;

    if (score > bestScore) {
      bestScore = score;
      bestGroup = group;
    }
  }

  // Require minimum confidence threshold of 40
  if (!bestGroup || bestScore < 40) {
    return { posts: [], confidence: bestScore, selector: null };
  }

  return {
    posts: bestGroup.elements,
    confidence: bestScore,
    selector: bestGroup.sig
  };
}

// ============================================================
// Shared UI: button creation, result display
// ============================================================

const processedPosts = new WeakSet();

let requestCount = 0;
let requestResetTime = Date.now();
const MAX_REQUESTS_PER_MINUTE = 20;

function checkRateLimit() {
  const now = Date.now();
  if (now - requestResetTime > 60000) {
    requestCount = 0;
    requestResetTime = now;
  }
  if (requestCount >= MAX_REQUESTS_PER_MINUTE) return false;
  requestCount++;
  return true;
}

const SIGNAL_LABELS = {
  arousal: 'Emotional Arousal',
  enemy: 'Enemy Construction',
  moral: 'Moral Outrage',
  urgency: 'False Urgency',
  tribal: 'Tribal Signaling'
};

function createCheckButton(postUrl, postText, isBeta) {
  const btn = document.createElement('button');
  btn.className = 'ragecheck-btn ragecheck-enter' + (isBeta ? ' ragecheck-beta' : '');
  btn.innerHTML = `
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
      <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2z"/>
      <path d="M12 6v6l4 2"/>
    </svg>
    <span class="ragecheck-label">Check</span>
    ${isBeta ? '<span class="ragecheck-beta-tag">beta</span>' : ''}
  `;

  btn.onclick = async (e) => {
    e.preventDefault();
    e.stopPropagation();

    if (btn.classList.contains('ragecheck-has-result')) {
      const url = btn.dataset.postUrl;
      window.open(`${API_BASE}?url=${encodeURIComponent(url)}`, '_blank');
      // Report success for Tier 3
      if (isBeta) reportDiagnostic('success', postUrl);
      return;
    }

    if (btn.classList.contains('ragecheck-error')) {
      btn.classList.remove('ragecheck-error');
      btn.querySelector('.ragecheck-label').textContent = 'Check';
      const existingTooltip = btn.querySelector('.ragecheck-tooltip');
      if (existingTooltip) existingTooltip.remove();
    }

    if (!postUrl) {
      showResult(btn, { error: 'Could not find post URL' }, postUrl);
      return;
    }

    if (!checkRateLimit()) {
      showResult(btn, { error: 'Rate limited - try again in a moment' }, postUrl);
      return;
    }

    btn.classList.add('ragecheck-loading');
    btn.querySelector('.ragecheck-label').textContent = '...';

    try {
      const payload = { url: postUrl };
      if (postText) payload.text = postText;
      const response = await fetch(`${API_BASE}/api/analyze`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      });

      if (response.status === 429) {
        showResult(btn, { error: 'Rate limited - please wait' }, postUrl);
        btn.classList.remove('ragecheck-loading');
        return;
      }

      const data = await response.json();
      if (data.success) {
        showResult(btn, {
          score: data.score, label: data.label,
          reasons: data.reasons || [], signals: data.signals || {}
        }, postUrl);
        if (isBeta) reportDiagnostic('success', postUrl);
      } else {
        showResult(btn, { error: data.error || 'Analysis failed' }, postUrl);
      }
    } catch (err) {
      showResult(btn, { error: 'Connection failed - click to retry' }, postUrl);
    }

    btn.classList.remove('ragecheck-loading');
  };

  return btn;
}

function showResult(btn, result, postUrl) {
  const label = btn.querySelector('.ragecheck-label');

  if (result.error) {
    label.textContent = 'Error';
    btn.classList.add('ragecheck-error');
    btn.title = result.error;
    return;
  }

  const score = result.score;
  label.textContent = score;
  btn.classList.remove('ragecheck-error');

  let levelText, levelDesc;
  if (score >= 66) {
    btn.classList.add('ragecheck-high');
    levelText = 'High Rage';
    levelDesc = 'Likely designed to provoke anger';
  } else if (score >= 33) {
    btn.classList.add('ragecheck-medium');
    levelText = 'Medium Rage';
    levelDesc = 'Some emotional manipulation detected';
  } else {
    btn.classList.add('ragecheck-low');
    levelText = 'Low Rage';
    levelDesc = 'Appears relatively balanced';
  }

  let tooltipHTML = `
    <div class="ragecheck-tooltip-score">${score}/100</div>
    <div class="ragecheck-tooltip-label">${levelText} - ${levelDesc}</div>
  `;

  if (result.signals && Object.keys(result.signals).length > 0) {
    tooltipHTML += '<div class="ragecheck-tooltip-signals">';
    for (const [key, value] of Object.entries(result.signals)) {
      const signalLabel = SIGNAL_LABELS[key] || key;
      tooltipHTML += `
        <div class="ragecheck-signal">
          <span class="ragecheck-signal-name">${signalLabel}</span>
          <div class="ragecheck-signal-bar">
            <div class="ragecheck-signal-fill" style="width:${value}%"></div>
          </div>
        </div>
      `;
    }
    tooltipHTML += '</div>';
  }

  if (result.reasons?.length > 0) {
    tooltipHTML += '<div class="ragecheck-tooltip-reasons">';
    result.reasons.slice(0, 2).forEach(r => {
      tooltipHTML += `<div class="ragecheck-tooltip-reason">${r}</div>`;
    });
    tooltipHTML += '</div>';
  }

  tooltipHTML += '<div class="ragecheck-tooltip-cta">Click for full analysis</div>';

  const tooltip = document.createElement('div');
  tooltip.className = 'ragecheck-tooltip';
  tooltip.innerHTML = tooltipHTML;
  btn.appendChild(tooltip);

  btn.classList.add('ragecheck-has-result');
  btn.dataset.postUrl = postUrl;
  btn.title = '';
}

// ============================================================
// Post processing and injection
// ============================================================

function getPostText(post, config) {
  // Try platform/engine-specific extractor first
  if (config.getPostText) {
    const text = config.getPostText(post);
    if (text) return text;
  }
  // Forum engines have contentSelector
  if (config.contentSelector) {
    const el = post.querySelector(config.contentSelector);
    if (el) return el.innerText.trim();
  }
  // Fallback: grab innerText of the post, truncated
  const raw = post.innerText?.trim() || '';
  return raw.slice(0, 2000);
}

function processPost(post, config, isBeta) {
  if (processedPosts.has(post)) return;
  processedPosts.add(post);

  const postUrl = config.getPostUrl ? config.getPostUrl(post) : window.location.href;
  if (!postUrl) return;
  if (post.querySelector('.ragecheck-btn')) return;

  const postText = getPostText(post, config);
  const btn = createCheckButton(postUrl, postText, isBeta);

  const wrapper = document.createElement('div');
  wrapper.className = 'ragecheck-wrapper';
  wrapper.appendChild(btn);

  // Find action bar
  let actionBar = null;
  let useFloating = !config.actionBarSelector;

  if (config.actionBarSelector) {
    actionBar = post.querySelector(config.actionBarSelector);
    if (config.name === 'twitter') {
      const groups = post.querySelectorAll('[role="group"]');
      actionBar = groups[groups.length - 1];
    }
    if (!actionBar) useFloating = true;
  }

  if (useFloating) {
    wrapper.className = 'ragecheck-wrapper ragecheck-floating';
    post.style.position = post.style.position || 'relative';
    post.appendChild(wrapper);
  } else if (config.name === 'twitter') {
    actionBar.appendChild(wrapper);
  } else if (config.name === 'reddit') {
    actionBar.insertBefore(wrapper, actionBar.firstChild);
  } else {
    actionBar.appendChild(wrapper);
  }

  if (autoCheck) btn.click();
}

// ============================================================
// Tier 3: Diagnostic reporting
// ============================================================

let diagnosticSent = false;

function reportDiagnostic(outcome, context) {
  if (!telemetryEnabled || diagnosticSent) return;

  const engineName = currentEngine?.name || currentPlatform?.name || 'generic';
  const payload = {
    type: 'diagnostic',
    domain: window.location.hostname,
    engine: engineName,
    outcome, // 'success' | 'ignored' | 'failed' | 'error'
    selector: context || null,
    timestamp: Date.now()
  };

  // Send to background worker for batching
  chrome.runtime.sendMessage(payload);
  diagnosticSent = true;
}

// ============================================================
// Detection and initialization
// ============================================================

let currentPlatform = null;
let currentEngine = null;
let detectionTier = null;

function detectCurrentSite() {
  const hostname = window.location.hostname;

  // Tier 1: Check social platforms
  for (const [name, config] of Object.entries(PLATFORMS)) {
    if (config.host.some(h => hostname.includes(h))) {
      if (enabledPlatforms[name] === false) return null;
      currentPlatform = { name, ...config };
      detectionTier = 1;
      return currentPlatform;
    }
  }

  // Tier 1: Check forum engine fingerprints (bundled)
  for (const [name, config] of Object.entries(FORUM_ENGINES)) {
    if (config.detect && config.detect()) {
      currentEngine = { name, ...config };
      detectionTier = 1;
      return currentEngine;
    }
  }

  // Tier 1: Check remote config engines
  for (const [name, config] of Object.entries(remoteEngines)) {
    if (config.detect) {
      // Remote config uses CSS selector string for detect
      if (document.querySelector(config.detect)) {
        currentEngine = { name, ...config, getPostUrl: () => window.location.href };
        detectionTier = 1;
        return currentEngine;
      }
    }
  }

  return null;
}

function processAllPosts() {
  const config = currentPlatform || currentEngine;
  if (!config) return;

  let posts;
  if (config.findPosts) {
    posts = config.findPosts();
  } else if (config.postSelector) {
    posts = document.querySelectorAll(config.postSelector);
  } else {
    posts = [];
  }

  posts.forEach(post => processPost(post, config, false));
}

// Tier 2 scanning (called by background via message)
function runGenericScan() {
  // First try schema.org (Tier 1.5)
  const schemaPosts = detectSchemaOrgPosts();
  if (schemaPosts.length > 0) {
    detectionTier = 1.5;
    // For microdata posts, the element is directly available
    const elements = schemaPosts
      .filter(p => p.type === 'microdata' && p.element)
      .map(p => p.element);

    if (elements.length > 0) {
      const config = {
        name: 'schema-org',
        getPostUrl: (post) => {
          const link = post.querySelector('a[href]');
          return link ? link.href : window.location.href;
        },
        actionBarSelector: null
      };
      elements.forEach(el => processPost(el, config, false));
      reportDiagnostic('success', 'schema.org');
      return { tier: 1.5, count: elements.length };
    }
  }

  // Tier 2: Generic heuristic
  detectionTier = 2;
  const result = genericDetectPosts();

  if (result.posts.length === 0) {
    reportDiagnostic('failed', result.selector);
    return { tier: 2, count: 0, confidence: result.confidence };
  }

  const config = {
    name: 'generic',
    getPostUrl: (post) => {
      const link = post.querySelector('a[href]');
      return link ? link.href : window.location.href;
    },
    actionBarSelector: null
  };

  result.posts.forEach(post => processPost(post, config, true));
  reportDiagnostic('ignored', result.selector); // will upgrade to 'success' if user clicks

  return { tier: 2, count: result.posts.length, confidence: result.confidence };
}

// Listen for scan requests from popup/background
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg.action === 'scan-page') {
    const result = runGenericScan();
    sendResponse(result);
  } else if (msg.action === 'get-tier') {
    sendResponse({
      tier: detectionTier,
      platform: currentPlatform?.name || currentEngine?.name || null,
      hostname: window.location.hostname
    });
  }
  return true; // keep channel open for async
});

// ============================================================
// Main initialization
// ============================================================

function init() {
  const site = detectCurrentSite();

  if (!site) {
    // Not a known platform — wait for scan request from popup
    console.log('RageCheck: Unknown site, ready for manual scan');
    return;
  }

  console.log(`RageCheck: Tier ${detectionTier} — ${currentPlatform?.name || currentEngine?.name}`);

  processAllPosts();

  // Set up MutationObserver
  // Scope to known container if possible, otherwise fall back to body
  const observeTarget = (currentEngine?.observeTarget && document.querySelector(currentEngine.observeTarget)) || document.body;
  let debounceTimer;

  const observer = new MutationObserver(() => {
    clearTimeout(debounceTimer);
    debounceTimer = setTimeout(() => {
      if (typeof requestIdleCallback !== 'undefined') {
        requestIdleCallback(processAllPosts);
      } else {
        processAllPosts();
      }
    }, 200);
  });

  observer.observe(observeTarget, { childList: true, subtree: true });

  // SPA navigation detection (for Discourse, etc.)
  if (currentEngine?.spa) {
    let lastUrl = location.href;
    const navObserver = new MutationObserver(() => {
      if (location.href !== lastUrl) {
        lastUrl = location.href;
        // Reset and re-detect on navigation
        setTimeout(processAllPosts, 500);
      }
    });
    navObserver.observe(document, { subtree: true, childList: true });
  }
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init);
} else {
  init();
}
