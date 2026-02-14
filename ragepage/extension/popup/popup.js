const DEFAULT_API_BASE = 'https://ragecheck.com';

const urlInput = document.getElementById('url');
const analyzeBtn = document.getElementById('analyze');
const loadingDiv = document.getElementById('loading');
const resultDiv = document.getElementById('result');
const scoreEl = document.getElementById('score');
const labelEl = document.getElementById('label');
const signalsDiv = document.getElementById('signals');
const resultLinks = document.getElementById('resultLinks');
const fullAnalysisLink = document.getElementById('fullAnalysis');
const retryBtn = document.getElementById('retry');
const openOptions = document.getElementById('openOptions');

const SIGNAL_LABELS = {
  arousal: 'Emotional Arousal',
  enemy: 'Enemy Construction',
  moral: 'Moral Outrage',
  urgency: 'False Urgency',
  tribal: 'Tribal Signaling'
};

let apiBase = DEFAULT_API_BASE;

// Load settings
chrome.storage.sync.get(['apiBase'], (result) => {
  if (result.apiBase) apiBase = result.apiBase;
});

// Try to get current tab URL
chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
  if (tabs[0]?.url) {
    const url = tabs[0].url;
    if (url.includes('twitter.com') ||
        url.includes('x.com') ||
        url.includes('bsky.app') ||
        url.includes('facebook.com') ||
        url.includes('reddit.com') ||
        url.includes('threads.net')) {
      urlInput.value = url;
    }
  }
});

// Open options page
openOptions.addEventListener('click', (e) => {
  e.preventDefault();
  chrome.runtime.openOptionsPage();
});

// Analyze
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

  try {
    const response = await fetch(`${apiBase}/api/analyze`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ url })
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

      // Show signal breakdown
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

      // Show full analysis link
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

analyzeBtn.addEventListener('click', runAnalysis);

retryBtn.addEventListener('click', () => {
  retryBtn.className = 'retry-btn';
  runAnalysis();
});

urlInput.addEventListener('keypress', (e) => {
  if (e.key === 'Enter') runAnalysis();
});
