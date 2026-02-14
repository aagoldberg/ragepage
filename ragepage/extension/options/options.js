const autoCheckEl = document.getElementById('autoCheck');
const telemetryEl = document.getElementById('telemetry');
const apiBaseEl = document.getElementById('apiBase');
const statusEl = document.getElementById('status');

const platformEls = {
  twitter: document.getElementById('plt-twitter'),
  bluesky: document.getElementById('plt-bluesky'),
  facebook: document.getElementById('plt-facebook'),
  reddit: document.getElementById('plt-reddit'),
  threads: document.getElementById('plt-threads'),
  hackernews: document.getElementById('plt-hackernews'),
  youtube: document.getElementById('plt-youtube'),
  stackoverflow: document.getElementById('plt-stackoverflow')
};

// Load saved settings
chrome.storage.sync.get(['autoCheck', 'enabledPlatforms', 'apiBase', 'telemetry'], (result) => {
  if (result.autoCheck) autoCheckEl.checked = result.autoCheck;
  if (result.telemetry) telemetryEl.checked = result.telemetry;

  if (result.enabledPlatforms) {
    for (const [key, el] of Object.entries(platformEls)) {
      if (el) el.checked = result.enabledPlatforms[key] !== false;
    }
  }

  if (result.apiBase) apiBaseEl.value = result.apiBase;
});

// Save on change
function save() {
  const enabledPlatforms = {};
  for (const [key, el] of Object.entries(platformEls)) {
    if (el) enabledPlatforms[key] = el.checked;
  }

  const settings = {
    autoCheck: autoCheckEl.checked,
    telemetry: telemetryEl.checked,
    enabledPlatforms,
    apiBase: apiBaseEl.value.trim() || undefined
  };

  if (!settings.apiBase) delete settings.apiBase;

  chrome.storage.sync.set(settings, () => {
    statusEl.classList.add('show');
    setTimeout(() => statusEl.classList.remove('show'), 1500);
  });
}

autoCheckEl.addEventListener('change', save);
telemetryEl.addEventListener('change', save);
apiBaseEl.addEventListener('change', save);
for (const el of Object.values(platformEls)) {
  if (el) el.addEventListener('change', save);
}
