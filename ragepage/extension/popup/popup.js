const DEFAULT_API_BASE = 'https://ragecheck.com';

const urlInput = document.getElementById('url');
const analyzeBtn = document.getElementById('analyze');
const scanBtn = document.getElementById('scanBtn');
const loadingDiv = document.getElementById('loading');
const resultDiv = document.getElementById('result');
const scoreEl = document.getElementById('score');
const labelEl = document.getElementById('label');
const signalsDiv = document.getElementById('signals');
const resultLinks = document.getElementById('resultLinks');
const fullAnalysisLink = document.getElementById('fullAnalysis');
const retryBtn = document.getElementById('retry');
const openOptions = document.getElementById('openOptions');
const tierStatus = document.getElementById('tierStatus');
const tierText = document.getElementById('tierText');
const scanResult = document.getElementById('scanResult');

const SIGNAL_LABELS = {
  arousal: 'Emotional Arousal',
  enemy: 'Enemy Construction',
  moral: 'Moral Outrage',
  urgency: 'False Urgency',
  tribal: 'Tribal Signaling'
};

let apiBase = DEFAULT_API_BASE;

chrome.storage.sync.get(['apiBase'], (r) => {
  if (r.apiBase) apiBase = r.apiBase;
});

// Get current tab info and show tier
chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
  if (!tabs[0]?.url) return;
  const url = tabs[0].url;

  // Pre-fill URL for social platforms
  const socialHosts = ['twitter.com', 'x.com', 'bsky.app', 'facebook.com', 'reddit.com',
    'threads.net', 'news.ycombinator.com', 'youtube.com', 'stackoverflow.com', 'stackexchange.com'];
  if (socialHosts.some(h => url.includes(h))) {
    urlInput.value = url;
  }

  // Query tier from content script
  chrome.runtime.sendMessage({ action: 'get-tier-from-popup' }, (response) => {
    if (chrome.runtime.lastError) return;
    if (!response) return;

    if (response.tier === 1 || response.tier === 1.5) {
      tierStatus.className = 'tier-status show tier-1';
      tierText.textContent = `Active on ${response.platform || response.hostname}`;
    } else if (response.tier === 2) {
      tierStatus.className = 'tier-status show tier-2';
      tierText.textContent = `Generic detection on ${response.hostname}`;
    } else {
      tierStatus.className = 'tier-status show tier-unknown';
      tierText.textContent = `Not detected — try "Scan page"`;
    }
  });
});

// Open options
openOptions.addEventListener('click', (e) => {
  e.preventDefault();
  chrome.runtime.openOptionsPage();
});

// Analyze URL
async function runAnalysis() {
  const url = urlInput.value.trim();
  if (!url) return;

  analyzeBtn.disabled = true;
  analyzeBtn.textContent = 'Analyzing...';
  loadingDiv.classList.add('show');
  resultDiv.className = 'result';
  signalsDiv.className = 'signals';
  resultLinks.className = 'result-links';
  retryBtn.className = 'retry-btn';
  scanResult.className = 'scan-result';

  try {
    const response = await fetch(`${apiBase}/api/analyze`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ url, source: 'extension' })
    });

    loadingDiv.classList.remove('show');

    if (response.status === 429) {
      showError('Rate limited - please wait a moment and try again');
      return;
    }

    const data = await response.json();

    if (data.success) {
      const score = data.score;
      scoreEl.textContent = score;

      if (score >= 66) {
        resultDiv.className = 'result show high';
        labelEl.textContent = 'High Rage - Likely manipulative';
      } else if (score >= 33) {
        resultDiv.className = 'result show medium';
        labelEl.textContent = 'Medium Rage - Some manipulation';
      } else {
        resultDiv.className = 'result show low';
        labelEl.textContent = 'Low Rage - Appears balanced';
      }

      if (data.signals && Object.keys(data.signals).length > 0) {
        let html = '<div class="signals-title">Signal Breakdown</div>';
        for (const [key, value] of Object.entries(data.signals)) {
          const label = SIGNAL_LABELS[key] || key;
          let cls = 'sv-low';
          if (value >= 66) cls = 'sv-high';
          else if (value >= 33) cls = 'sv-medium';
          html += `
            <div class="signal-row">
              <span class="signal-name">${label}</span>
              <div class="signal-track">
                <div class="signal-value ${cls}" style="width:${value}%"></div>
              </div>
              <span class="signal-num">${value}</span>
            </div>
          `;
        }
        signalsDiv.innerHTML = html;
        signalsDiv.className = 'signals show';
      }

      fullAnalysisLink.href = `${apiBase}?url=${encodeURIComponent(url)}`;
      resultLinks.className = 'result-links show';
    } else {
      showError(data.error || 'Analysis failed');
    }
  } catch (err) {
    loadingDiv.classList.remove('show');
    showError('Connection failed');
  }

  analyzeBtn.disabled = false;
  analyzeBtn.textContent = 'Analyze';
}

function showError(message) {
  resultDiv.className = 'result show error';
  scoreEl.textContent = '!';
  labelEl.textContent = message;
  retryBtn.className = 'retry-btn show';
}

// Scan page for posts (Tier 2)
scanBtn.addEventListener('click', async () => {
  scanBtn.disabled = true;
  scanBtn.textContent = 'Scanning...';
  scanResult.className = 'scan-result';

  chrome.runtime.sendMessage({ action: 'scan-from-popup' }, (response) => {
    scanBtn.disabled = false;
    scanBtn.textContent = 'Scan page';

    if (chrome.runtime.lastError) {
      scanResult.className = 'scan-result show scan-fail';
      scanResult.textContent = 'Could not access this page. Try reloading.';
      return;
    }

    if (!response || response.error) {
      scanResult.className = 'scan-result show scan-fail';
      scanResult.textContent = response?.error === 'injection_failed'
        ? 'Cannot scan this page (restricted by browser).'
        : 'Scan failed. Try a different page.';
      return;
    }

    if (response.count > 0) {
      const tierLabel = response.tier === 1.5 ? 'schema.org' : 'heuristic';
      scanResult.className = 'scan-result show scan-success';
      scanResult.textContent = `Found ${response.count} posts (${tierLabel} detection). Check buttons added.`;

      tierStatus.className = 'tier-status show tier-2';
      tierText.textContent = `Scanning active`;
    } else {
      scanResult.className = 'scan-result show scan-fail';
      const conf = response.confidence ? ` (confidence: ${response.confidence})` : '';
      scanResult.textContent = `No posts detected on this page${conf}. You can still analyze URLs above.`;
    }
  });
});

analyzeBtn.addEventListener('click', runAnalysis);

retryBtn.addEventListener('click', () => {
  retryBtn.className = 'retry-btn';
  runAnalysis();
});

urlInput.addEventListener('keypress', (e) => {
  if (e.key === 'Enter') runAnalysis();
});
