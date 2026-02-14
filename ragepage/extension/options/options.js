const autoCheckEl = document.getElementById('autoCheck');
const apiBaseEl = document.getElementById('apiBase');
const statusEl = document.getElementById('status');

const platformEls = {
  twitter: document.getElementById('plt-twitter'),
  bluesky: document.getElementById('plt-bluesky'),
  facebook: document.getElementById('plt-facebook'),
  reddit: document.getElementById('plt-reddit'),
  threads: document.getElementById('plt-threads')
};

// Load saved settings
chrome.storage.sync.get(['autoCheck', 'enabledPlatforms', 'apiBase'], (result) => {
  if (result.autoCheck) autoCheckEl.checked = result.autoCheck;

  if (result.enabledPlatforms) {
    for (const [key, el] of Object.entries(platformEls)) {
      el.checked = result.enabledPlatforms[key] !== false;
    }
  }

  if (result.apiBase) apiBaseEl.value = result.apiBase;
});

// Save on change
function save() {
  const enabledPlatforms = {};
  for (const [key, el] of Object.entries(platformEls)) {
    enabledPlatforms[key] = el.checked;
  }

  const settings = {
    autoCheck: autoCheckEl.checked,
    enabledPlatforms,
    apiBase: apiBaseEl.value.trim() || undefined
  };

  // Remove undefined keys so defaults apply
  if (!settings.apiBase) delete settings.apiBase;

  chrome.storage.sync.set(settings, () => {
    statusEl.classList.add('show');
    setTimeout(() => statusEl.classList.remove('show'), 1500);
  });
}

autoCheckEl.addEventListener('change', save);
apiBaseEl.addEventListener('change', save);
for (const el of Object.values(platformEls)) {
  el.addEventListener('change', save);
}
