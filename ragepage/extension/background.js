// RageCheck Background Service Worker
// Handles context menu, badge, notifications, remote config, programmatic injection, diagnostics

const DEFAULT_API_BASE = 'https://ragecheck.com';
const CONFIG_CACHE_DURATION = 24 * 60 * 60 * 1000; // 24 hours

async function getApiBase() {
  return new Promise((resolve) => {
    chrome.storage.sync.get(['apiBase'], (r) => resolve(r.apiBase || DEFAULT_API_BASE));
  });
}

// ============================================================
// Remote selector config
// ============================================================

async function fetchRemoteConfig() {
  const apiBase = await getApiBase();
  const cached = await chrome.storage.local.get(['selectorConfig', 'configTimestamp']);

  // Use cache if fresh
  if (cached.selectorConfig && cached.configTimestamp &&
      Date.now() - cached.configTimestamp < CONFIG_CACHE_DURATION) {
    return cached.selectorConfig;
  }

  try {
    const response = await fetch(`${apiBase}/api/selectors`);
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const config = await response.json();
    await chrome.storage.local.set({
      selectorConfig: config,
      configTimestamp: Date.now()
    });
    return config;
  } catch (e) {
    console.log('RageCheck: Remote config fetch failed, using cached/defaults', e.message);
    return cached.selectorConfig || { version: 0, engines: {} };
  }
}

// Fetch config on startup
fetchRemoteConfig();

// Refresh config periodically (service worker may restart)
chrome.alarms.create('config-refresh', { periodInMinutes: 60 * 6 }); // every 6h
chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === 'config-refresh') fetchRemoteConfig();
});

// ============================================================
// Context menu and install
// ============================================================

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

  chrome.contextMenus.create({
    id: 'ragecheck-scan',
    title: 'Scan page for posts with RageCheck',
    contexts: ['page']
  });

  if (details.reason === 'install') {
    chrome.notifications.create('ragecheck-welcome', {
      type: 'basic',
      iconUrl: 'icons/icon128.png',
      title: 'RageCheck Installed',
      message: 'Check buttons appear on Twitter, Reddit, Bluesky, Facebook, Threads, HN, YouTube, and Stack Overflow. Right-click any text or link to check it. Use "Scan page" on forums.'
    });
    // Fetch config immediately on install
    fetchRemoteConfig();
  }
});

chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  if (info.menuItemId === 'ragecheck-selection') {
    if (info.selectionText?.trim()) await analyzeText(info.selectionText, tab);
  } else if (info.menuItemId === 'ragecheck-link') {
    if (info.linkUrl) await analyzeUrl(info.linkUrl, tab);
  } else if (info.menuItemId === 'ragecheck-page') {
    const url = info.pageUrl || tab.url;
    if (url) await analyzeUrl(url, tab);
  } else if (info.menuItemId === 'ragecheck-scan') {
    await scanPage(tab);
  }
});

// ============================================================
// Programmatic injection for Tier 2 (non-content_scripts sites)
// ============================================================

async function scanPage(tab) {
  if (!tab?.id) return { error: 'No active tab' };

  try {
    // Try sending message to already-injected content script
    const response = await chrome.tabs.sendMessage(tab.id, { action: 'scan-page' });
    return response;
  } catch (e) {
    // Content script not injected — inject it programmatically
    // This uses activeTab permission (granted by user clicking extension/context menu)
    try {
      await chrome.scripting.insertCSS({ target: { tabId: tab.id }, files: ['content.css'] });
      await chrome.scripting.executeScript({ target: { tabId: tab.id }, files: ['content.js'] });
      // Give it a moment to init, then scan
      await new Promise(r => setTimeout(r, 300));
      const response = await chrome.tabs.sendMessage(tab.id, { action: 'scan-page' });
      return response;
    } catch (injectErr) {
      console.log('RageCheck: Could not inject into tab', injectErr.message);
      showNotification('error', 'Cannot scan this page', 'RageCheck cannot access this page. Try a different site.');
      return { error: 'injection_failed' };
    }
  }
}

// ============================================================
// Analysis functions
// ============================================================

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

// ============================================================
// Badge
// ============================================================

function updateBadge(score, tabId) {
  let color;
  if (score >= 66) color = '#ef4444';
  else if (score >= 33) color = '#f59e0b';
  else color = '#10b981';

  const opts = {};
  if (tabId) opts.tabId = tabId;

  chrome.action.setBadgeText({ text: String(score), ...opts });
  chrome.action.setBadgeBackgroundColor({ color, ...opts });
}

// ============================================================
// Notifications
// ============================================================

function showResultNotification(score, label, content) {
  let level, emoji;
  if (score >= 66) { level = 'High Rage'; emoji = '🔴'; }
  else if (score >= 33) { level = 'Medium Rage'; emoji = '🟡'; }
  else { level = 'Low Rage'; emoji = '🟢'; }

  const title = `${emoji} ${score}/100 - ${level}`;
  const preview = content.length > 80 ? content.substring(0, 80) + '...' : content;
  showNotification('result', title, preview);
}

async function showNotification(id, title, message) {
  chrome.notifications.clear('ragecheck-' + id);
  chrome.notifications.create('ragecheck-' + id, {
    type: 'basic',
    iconUrl: 'icons/icon128.png',
    title,
    message
  });
}

chrome.notifications.onClicked.addListener(async (notificationId) => {
  if (notificationId.startsWith('ragecheck-')) {
    const apiBase = await getApiBase();
    chrome.tabs.create({ url: apiBase });
  }
});

// ============================================================
// Tier 3: Diagnostic collection
// ============================================================

let diagnosticBatch = [];
const DIAGNOSTIC_FLUSH_INTERVAL = 5 * 60 * 1000; // 5 minutes
const DIAGNOSTIC_BATCH_SIZE = 20;

// Collect diagnostics from content scripts
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg.type === 'diagnostic') {
    diagnosticBatch.push({
      domain: msg.domain,
      engine: msg.engine,
      outcome: msg.outcome,
      selector: msg.selector,
      timestamp: msg.timestamp
    });

    if (diagnosticBatch.length >= DIAGNOSTIC_BATCH_SIZE) {
      flushDiagnostics();
    }
    sendResponse({ ok: true });
  }

  // Handle scan-page request from popup
  if (msg.action === 'scan-from-popup') {
    (async () => {
      const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
      const result = await scanPage(tab);
      sendResponse(result);
    })();
    return true; // keep channel open
  }

  // Handle get-tier request from popup
  if (msg.action === 'get-tier-from-popup') {
    (async () => {
      const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
      if (!tab?.id) { sendResponse({ tier: null }); return; }
      try {
        const result = await chrome.tabs.sendMessage(tab.id, { action: 'get-tier' });
        sendResponse(result);
      } catch (e) {
        sendResponse({ tier: null, hostname: new URL(tab.url || '').hostname });
      }
    })();
    return true;
  }
});

async function flushDiagnostics() {
  if (diagnosticBatch.length === 0) return;

  const batch = [...diagnosticBatch];
  diagnosticBatch = [];

  try {
    const apiBase = await getApiBase();
    await fetch(`${apiBase}/api/diagnostics`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ reports: batch })
    });
  } catch (e) {
    // If flush fails, put items back (up to limit)
    diagnosticBatch.push(...batch.slice(0, DIAGNOSTIC_BATCH_SIZE));
  }
}

// Periodic flush
chrome.alarms.create('diagnostic-flush', { periodInMinutes: 5 });
chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === 'diagnostic-flush') flushDiagnostics();
});
