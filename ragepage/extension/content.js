// RageCheck Content Script
// Injects "Check" buttons into social media posts

const DEFAULT_API_BASE = 'https://ragecheck.com';

// Load settings from chrome.storage
let API_BASE = DEFAULT_API_BASE;
let autoCheck = false;
let enabledPlatforms = {
  twitter: true, bluesky: true, facebook: true, reddit: true, threads: true
};

chrome.storage.sync.get(['apiBase', 'autoCheck', 'enabledPlatforms'], (settings) => {
  if (settings.apiBase) API_BASE = settings.apiBase;
  if (settings.autoCheck !== undefined) autoCheck = settings.autoCheck;
  if (settings.enabledPlatforms) enabledPlatforms = settings.enabledPlatforms;
});

// Listen for settings changes
chrome.storage.onChanged.addListener((changes) => {
  if (changes.apiBase) API_BASE = changes.apiBase.newValue || DEFAULT_API_BASE;
  if (changes.autoCheck) autoCheck = changes.autoCheck.newValue;
  if (changes.enabledPlatforms) enabledPlatforms = changes.enabledPlatforms.newValue;
});

// Platform-specific selectors
const PLATFORMS = {
  twitter: {
    host: ['twitter.com', 'x.com'],
    postSelector: 'article[data-testid="tweet"]',
    actionBarSelector: '[role="group"]:last-of-type',
    urlSelector: 'a[href*="/status/"] time',
    getPostUrl: (post) => {
      const timeLink = post.querySelector('a[href*="/status/"]');
      return timeLink ? timeLink.href : null;
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
        if (href && href.includes('/post/')) {
          return href.startsWith('http') ? href : 'https://bsky.app' + href;
        }
      }
      return null;
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
    }
  },
  reddit: {
    host: ['www.reddit.com'],
    postSelector: 'shreddit-post, [data-testid="post-container"]',
    actionBarSelector: '[slot="post-actions"], [data-testid="post-bottom-bar"]',
    getPostUrl: (post) => {
      const link = post.querySelector('a[href*="/comments/"]');
      return link ? link.href : window.location.href;
    }
  },
  threads: {
    host: ['www.threads.net'],
    postSelector: '[data-pressable-container="true"]',
    actionBarSelector: '[role="button"]',
    getPostUrl: (post) => {
      const link = post.querySelector('a[href*="/post/"]');
      return link ? 'https://www.threads.net' + link.getAttribute('href') : null;
    }
  }
};

// Detect current platform
function getCurrentPlatform() {
  const hostname = window.location.hostname;
  for (const [name, config] of Object.entries(PLATFORMS)) {
    if (config.host.some(h => hostname.includes(h))) {
      if (!enabledPlatforms[name]) return null;
      return { name, ...config };
    }
  }
  return null;
}

// Track processed posts to avoid duplicates
const processedPosts = new WeakSet();

// Simple rate limiter
let requestCount = 0;
let requestResetTime = Date.now();
const MAX_REQUESTS_PER_MINUTE = 20;

function checkRateLimit() {
  const now = Date.now();
  if (now - requestResetTime > 60000) {
    requestCount = 0;
    requestResetTime = now;
  }
  if (requestCount >= MAX_REQUESTS_PER_MINUTE) {
    return false;
  }
  requestCount++;
  return true;
}

// Signal labels for the 5-bar breakdown
const SIGNAL_LABELS = {
  arousal: 'Emotional Arousal',
  enemy: 'Enemy Construction',
  moral: 'Moral Outrage',
  urgency: 'False Urgency',
  tribal: 'Tribal Signaling'
};

// Create the check button
function createCheckButton(postUrl) {
  const btn = document.createElement('button');
  btn.className = 'ragecheck-btn ragecheck-enter';
  btn.innerHTML = `
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
      <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2z"/>
      <path d="M12 6v6l4 2"/>
    </svg>
    <span class="ragecheck-label">Check</span>
  `;

  btn.onclick = async (e) => {
    e.preventDefault();
    e.stopPropagation();

    // If already has result, open full analysis
    if (btn.classList.contains('ragecheck-has-result')) {
      const url = btn.dataset.postUrl;
      window.open(`${API_BASE}?url=${encodeURIComponent(url)}`, '_blank');
      return;
    }

    // If error, allow retry
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
      const response = await fetch(`${API_BASE}/api/analyze`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ url: postUrl })
      });

      if (response.status === 429) {
        showResult(btn, { error: 'Rate limited - please wait before checking more posts' }, postUrl);
        btn.classList.remove('ragecheck-loading');
        return;
      }

      const data = await response.json();

      if (data.success) {
        showResult(btn, {
          score: data.score,
          label: data.label,
          reasons: data.reasons || [],
          signals: data.signals || {}
        }, postUrl);
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

// Show result on button
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

  // Build tooltip content
  let tooltipHTML = `
    <div class="ragecheck-tooltip-score">${score}/100</div>
    <div class="ragecheck-tooltip-label">${levelText} - ${levelDesc}</div>
  `;

  // Add signal bars if available
  if (result.signals && Object.keys(result.signals).length > 0) {
    tooltipHTML += '<div class="ragecheck-tooltip-signals">';
    for (const [key, value] of Object.entries(result.signals)) {
      const signalLabel = SIGNAL_LABELS[key] || key;
      const pct = Math.round((value / 100) * 100);
      tooltipHTML += `
        <div class="ragecheck-signal">
          <span class="ragecheck-signal-name">${signalLabel}</span>
          <div class="ragecheck-signal-bar">
            <div class="ragecheck-signal-fill" style="width:${pct}%"></div>
          </div>
        </div>
      `;
    }
    tooltipHTML += '</div>';
  }

  // Add top reasons if available
  if (result.reasons && result.reasons.length > 0) {
    const topReasons = result.reasons.slice(0, 2);
    tooltipHTML += '<div class="ragecheck-tooltip-reasons">';
    topReasons.forEach(r => {
      tooltipHTML += `<div class="ragecheck-tooltip-reason">${r}</div>`;
    });
    tooltipHTML += '</div>';
  }

  tooltipHTML += `
    <div class="ragecheck-tooltip-cta">Click for full analysis</div>
  `;

  // Add tooltip
  const tooltip = document.createElement('div');
  tooltip.className = 'ragecheck-tooltip';
  tooltip.innerHTML = tooltipHTML;
  btn.appendChild(tooltip);

  // Make button clickable to open full analysis
  btn.classList.add('ragecheck-has-result');
  btn.dataset.postUrl = postUrl;
  btn.title = '';
}

// Process a single post
function processPost(post, platform) {
  if (processedPosts.has(post)) return;
  processedPosts.add(post);

  const postUrl = platform.getPostUrl(post);
  if (!postUrl) return;

  // Find action bar
  let actionBar = null;
  let useFloating = !platform.actionBarSelector;

  if (platform.actionBarSelector) {
    actionBar = post.querySelector(platform.actionBarSelector);

    if (platform.name === 'twitter') {
      const groups = post.querySelectorAll('[role="group"]');
      actionBar = groups[groups.length - 1];
    }

    if (!actionBar) {
      useFloating = true;
    }
  }

  // Check if button already exists
  if (post.querySelector('.ragecheck-btn')) return;

  const btn = createCheckButton(postUrl);

  // Insert button
  const wrapper = document.createElement('div');
  wrapper.className = 'ragecheck-wrapper';
  wrapper.appendChild(btn);

  if (useFloating) {
    wrapper.className = 'ragecheck-wrapper ragecheck-floating';
    post.style.position = 'relative';
    post.appendChild(wrapper);
  } else if (platform.name === 'twitter') {
    actionBar.appendChild(wrapper);
  } else if (platform.name === 'reddit') {
    actionBar.insertBefore(wrapper, actionBar.firstChild);
  } else {
    actionBar.appendChild(wrapper);
  }

  // Auto-check if enabled
  if (autoCheck) {
    btn.click();
  }
}

// Main function to find and process posts
function processAllPosts() {
  const platform = getCurrentPlatform();
  if (!platform) return;

  let posts;
  if (platform.findPosts) {
    posts = platform.findPosts();
  } else if (platform.postSelector) {
    posts = document.querySelectorAll(platform.postSelector);
  } else {
    posts = [];
  }

  posts.forEach(post => processPost(post, platform));
}

// Initialize
function init() {
  const platform = getCurrentPlatform();
  if (!platform) return;

  console.log(`RageCheck: Initialized on ${platform.name}`);

  processAllPosts();

  // Watch for new posts (infinite scroll)
  const observer = new MutationObserver(() => {
    clearTimeout(observer.timeout);
    observer.timeout = setTimeout(processAllPosts, 200);
  });

  observer.observe(document.body, {
    childList: true,
    subtree: true
  });
}

// Start when DOM is ready
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init);
} else {
  init();
}
