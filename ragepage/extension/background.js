// RageCheck Background Service Worker
// Handles context menu, badge, and notifications

const DEFAULT_API_BASE = 'https://ragecheck.com';

async function getApiBase() {
  return new Promise((resolve) => {
    chrome.storage.sync.get(['apiBase'], (result) => {
      resolve(result.apiBase || DEFAULT_API_BASE);
    });
  });
}

// Create context menu and show welcome on install
chrome.runtime.onInstalled.addListener((details) => {
  chrome.contextMenus.create({
    id: 'ragecheck-selection',
    title: 'Check with RageCheck',
    contexts: ['selection']
  });

  chrome.contextMenus.create({
    id: 'ragecheck-link',
    title: 'Check link with RageCheck',
    contexts: ['link']
  });

  chrome.contextMenus.create({
    id: 'ragecheck-page',
    title: 'Check this page with RageCheck',
    contexts: ['page']
  });

  // Welcome notification on first install
  if (details.reason === 'install') {
    chrome.notifications.create('ragecheck-welcome', {
      type: 'basic',
      iconUrl: 'icons/icon128.png',
      title: 'RageCheck Installed',
      message: 'Browse Twitter, Bluesky, Reddit, Facebook, or Threads. Click "Check" on any post to see its rage score. You can also right-click any text or link.'
    });
  }
});

// Handle context menu clicks
chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  if (info.menuItemId === 'ragecheck-selection') {
    const selectedText = info.selectionText;
    if (selectedText && selectedText.trim().length > 0) {
      await analyzeText(selectedText, tab);
    }
  } else if (info.menuItemId === 'ragecheck-link') {
    const linkUrl = info.linkUrl;
    if (linkUrl) {
      await analyzeUrl(linkUrl, tab);
    }
  } else if (info.menuItemId === 'ragecheck-page') {
    const pageUrl = info.pageUrl || tab.url;
    if (pageUrl) {
      await analyzeUrl(pageUrl, tab);
    }
  }
});

// Analyze text content directly
async function analyzeText(text, tab) {
  await showNotification('analyzing', 'Analyzing...', 'Checking content for rage bait...');

  try {
    const apiBase = await getApiBase();
    const response = await fetch(`${apiBase}/api/analyze`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text })
    });

    const data = await response.json();

    if (data.success) {
      showResultNotification(data.score, data.label, text.substring(0, 100));
      updateBadge(data.score, tab?.id);
    } else {
      showNotification('error', 'Analysis Failed', data.error || 'Could not analyze content');
    }
  } catch (err) {
    showNotification('error', 'Connection Error', 'Could not reach RageCheck API');
  }
}

// Analyze URL
async function analyzeUrl(url, tab) {
  await showNotification('analyzing', 'Analyzing...', 'Checking URL for rage bait...');

  try {
    const apiBase = await getApiBase();
    const response = await fetch(`${apiBase}/api/analyze`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ url })
    });

    const data = await response.json();

    if (data.success) {
      showResultNotification(data.score, data.label, url);
      updateBadge(data.score, tab?.id);
    } else {
      showNotification('error', 'Analysis Failed', data.error || 'Could not analyze URL');
    }
  } catch (err) {
    showNotification('error', 'Connection Error', 'Could not reach RageCheck API');
  }
}

// Update extension icon badge with score
function updateBadge(score, tabId) {
  let color;
  if (score >= 66) {
    color = '#ef4444';
  } else if (score >= 33) {
    color = '#f59e0b';
  } else {
    color = '#10b981';
  }

  const opts = {};
  if (tabId) opts.tabId = tabId;

  chrome.action.setBadgeText({ text: String(score), ...opts });
  chrome.action.setBadgeBackgroundColor({ color, ...opts });
}

// Show result notification with formatting
function showResultNotification(score, label, content) {
  let level, emoji;
  if (score >= 66) {
    level = 'High Rage';
    emoji = '🔴';
  } else if (score >= 33) {
    level = 'Medium Rage';
    emoji = '🟡';
  } else {
    level = 'Low Rage';
    emoji = '🟢';
  }

  const title = `${emoji} ${score}/100 - ${level}`;
  const preview = content.length > 80 ? content.substring(0, 80) + '...' : content;

  showNotification('result', title, preview);
}

// Show browser notification
async function showNotification(id, title, message) {
  chrome.notifications.clear('ragecheck-' + id);

  chrome.notifications.create('ragecheck-' + id, {
    type: 'basic',
    iconUrl: 'icons/icon128.png',
    title,
    message
  });
}

// Open full analysis when notification clicked
chrome.notifications.onClicked.addListener(async (notificationId) => {
  if (notificationId.startsWith('ragecheck-')) {
    const apiBase = await getApiBase();
    chrome.tabs.create({ url: apiBase });
  }
});
