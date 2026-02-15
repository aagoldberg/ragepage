# RageCheck Extension — Distilled Model Architecture

## The Problem

Detecting ragebait in social media feeds requires scoring every post as the user scrolls. Current approaches have fundamental tradeoffs:

```
                    Speed          Cost         Quality
                    ─────          ────         ───────
 Rule Engine        <1ms           $0           67% accuracy
 Haiku 4.5          ~2.5s          $0.002       96% accuracy
 Sonnet 4.5         ~6s            $0.005       92% accuracy
 Opus 4.5           ~10s           $0.014       ??? accuracy
```

None of these work for real-time feed scanning. The rule engine is instant but misses half of all ragebait. LLMs are accurate but too slow for inline indicators and too expensive at scale.

## The Solution: Distilled DistilBERT

Train a small transformer model (~67M params) to replicate Sonnet's judgment. Run it directly in the browser via Transformers.js. Zero latency. Zero ongoing cost. Sonnet-grade quality.

```
┌─────────────────────────────────────────────────────────┐
│                    TRAINING PIPELINE                     │
│                    (one-time, ~$50)                      │
│                                                         │
│  ┌──────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │ 10k Posts │───▶│ Sonnet 4.5   │───▶│ Labeled Data │  │
│  │ (tweets,  │    │ "Teacher"    │    │ score 0-100  │  │
│  │  reddit,  │    │ $0.005/post  │    │ + reasons    │  │
│  │  threads) │    └──────────────┘    └──────┬───────┘  │
│  └──────────┘                                │          │
│                                              ▼          │
│                                     ┌──────────────┐    │
│                                     │ Fine-tune     │    │
│                                     │ DistilBERT    │    │
│                                     │ 67M params    │    │
│                                     └──────┬───────┘    │
│                                            │            │
│                                            ▼            │
│                                     ┌──────────────┐    │
│                                     │ Export ONNX   │    │
│                                     │ Quantize q8   │    │
│                                     │ ~30MB model   │    │
│                                     └──────────────┘    │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│                  INFERENCE (in browser)                   │
│                  (free, ~50ms/post)                       │
│                                                          │
│  ┌──────────┐    ┌────────────────┐    ┌─────────────┐  │
│  │ Tweet in  │───▶│ Transformers.js│───▶│ Score: 72   │  │
│  │ user feed │    │ + ONNX Runtime │    │ ● red dot   │  │
│  │           │    │ (service worker│    │             │  │
│  │           │    │  WebAssembly)  │    │             │  │
│  └──────────┘    └────────────────┘    └─────────────┘  │
│                                                          │
│               No API calls. No network. No cost.         │
└──────────────────────────────────────────────────────────┘
```

## Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     Chrome Extension                             │
│                                                                  │
│  ┌────────────────┐   ┌──────────────────┐   ┌──────────────┐  │
│  │  content.js     │   │  background.js    │   │  popup.js    │  │
│  │                 │   │  (service worker) │   │              │  │
│  │ • Detects posts │   │                   │   │ • URL input  │  │
│  │ • Injects dots  │   │ • Loads ONNX      │   │ • Full scan  │  │
│  │ • Injects Check │   │   model on install│   │              │  │
│  │   buttons       │   │ • Runs inference  │   │              │  │
│  │                 │   │ • Returns scores  │   │              │  │
│  │  ┌───┐ ┌───┐   │   │                   │   │              │  │
│  │  │ ● │ │Chk│   │   │  ┌─────────────┐  │   │              │  │
│  │  │dot│ │btn│   │   │  │DistilBERT   │  │   │              │  │
│  │  └─┬─┘ └─┬─┘   │   │  │ONNX q8 30MB│  │   │              │  │
│  │    │      │     │   │  └─────────────┘  │   │              │  │
│  └────┼──────┼─────┘   └────────▲──────────┘   └──────────────┘  │
│       │      │                  │                                 │
│       │      │    ┌─────────────┘                                │
│       │      │    │  chrome.runtime.sendMessage                  │
│       ▼      │    │  { action: 'score', text: '...' }           │
│    Instant   │    │                                              │
│    ~50ms     │                                                   │
│              ▼                                                   │
│         ┌─────────────────────┐                                  │
│         │ ragecheck.com API   │                                  │
│         │ Sonnet 4.5 (full)   │                                  │
│         │ ~6s, $0.005/call    │                                  │
│         └─────────────────────┘                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Two-Tier Scoring

```
User scrolls feed
       │
       ▼
  ┌─────────┐     Tier 1: Distilled Model (automatic)
  │ Post     │     ─────────────────────────────────────
  │ detected │────▶ DistilBERT in service worker
  │          │     • Runs on every post, ~50ms
  │          │     • Shows colored dot (●/●/●)
  └────┬─────┘     • No network, no cost
       │
       │           Tier 2: Full LLM Analysis (on click)
       │           ─────────────────────────────────────
  User clicks ───▶ Sonnet 4.5 via ragecheck.com API
  "Check"          • Detailed reasons + technique breakdown
                   • Sharing patterns + share card
                   • ~6 seconds, $0.005
```

## Training Pipeline

### Phase 1: Data Collection

Collect ~10,000 diverse social media posts across platforms and topics.

```
Data Sources                    Target Distribution
─────────────                   ───────────────────

Twitter/X ────── 3,000 posts    ┌──────────────────────┐
Reddit ───────── 2,500 posts    │ ████████████  40%     │ Not ragebait
Threads ──────── 1,000 posts    │ ████████      30%     │ Borderline
Facebook ─────── 1,000 posts    │ ████████      30%     │ Ragebait
Bluesky ──────── 1,000 posts    └──────────────────────┘
News headlines ─ 1,000 posts
HN/forums ────── 500 posts

Topic Coverage:
├── Politics (left + right) ──────── 25%
├── Culture wars ─────────────────── 15%
├── Health / science ─────────────── 10%
├── Tech / business ──────────────── 10%
├── Crime / safety ───────────────── 10%
├── Personal stories / venting ───── 10%
├── News reporting ───────────────── 10%
└── Wholesome / neutral ──────────── 10%
```

**Data collection strategies:**
- Twitter API (academic access or scrape via Nitter archives)
- Reddit API (pushshift.io archives)
- Existing datasets: TweetEval, HateXplain, GoEmotions, Civil Comments
- Manual curation of edge cases (advocacy vs. manipulation, reporting vs. outrage)

### Phase 2: Teacher Labeling

Score every post with Sonnet 4.5 using the production RageCheck prompt.

```
┌─────────────────────────────────────────────────────┐
│                 Labeling Pipeline                     │
│                                                      │
│  for each post in dataset:                           │
│    1. Run rule engine  ──▶  rule_score, bars         │
│    2. Call Sonnet 4.5  ──▶  llm_score, reasons       │
│    3. Store:                                         │
│       {                                              │
│         text: "...",                                 │
│         rule_score: 44,                              │
│         llm_score: 78,          ◀── training target  │
│         label: "ragebait",                           │
│         reasons: ["..."],                            │
│         bars: { arousal: 50, enemy: 56, ... }        │
│       }                                              │
│                                                      │
│  Cost: 10,000 × $0.005 = $50                        │
│  Time: ~16 hours (3 concurrent)                      │
└─────────────────────────────────────────────────────┘
```

**Why Sonnet and not human labels?**
- Consistent scoring (no inter-rater variability)
- Produces nuanced 0-100 scores (not just binary)
- Already calibrated to the RageCheck scale
- Can label 10k posts for $50 vs. $2000+ for human annotators
- Can re-label cheaply when the scoring criteria evolve

### Phase 3: Model Training

Fine-tune DistilBERT for regression (predict score 0-100).

```
Model Architecture
──────────────────

  Input: "Radical Left Scum destroying our Country"
    │
    ▼
  ┌──────────────────────────┐
  │     Tokenizer            │  WordPiece, max 128 tokens
  │     (pretrained)         │  (tweets are short)
  └────────────┬─────────────┘
               │
               ▼
  ┌──────────────────────────┐
  │     DistilBERT           │  6 layers, 768 hidden
  │     67M parameters       │  12 attention heads
  │     (pretrained on       │
  │      English text)       │
  └────────────┬─────────────┘
               │
               ▼
  ┌──────────────────────────┐
  │     Regression Head      │  768 → 256 → 1
  │     (trained from        │  ReLU activation
  │      scratch)            │  Sigmoid × 100
  └────────────┬─────────────┘
               │
               ▼
  Output: 78.3  (ragebait score)
```

**Training configuration:**

```python
# Hyperparameters
model_name    = "distilbert-base-uncased"
max_length    = 128          # tweets are short
batch_size    = 32
learning_rate = 2e-5
epochs        = 5
warmup_ratio  = 0.1
loss_fn       = MSELoss()    # regression on 0-100 score

# Data split
train         = 8,000 posts  (80%)
validation    = 1,000 posts  (10%)
test          = 1,000 posts  (10%)

# Training time
# ~20 minutes on a single GPU (T4/A10)
# ~2 hours on CPU
# Free on Google Colab
```

**Alternative models to evaluate:**

```
Model              Params    Size (q8)   Speed (WASM)   Notes
─────              ──────    ─────────   ────────────   ─────
DistilBERT         67M       ~30MB       ~50ms          Best balance
TinyBERT           14M       ~8MB        ~15ms          Faster, less accurate
MobileBERT         25M       ~12MB       ~25ms          Mobile-optimized
ALBERT-base        12M       ~6MB        ~20ms          Smallest
DeBERTa-v3-small   44M       ~20MB       ~40ms          Best at NLU tasks
```

### Phase 4: Export and Quantize

```
PyTorch Model (267MB)
    │
    ▼  torch.onnx.export()
ONNX Model (267MB)
    │
    ▼  quantize_dynamic(weight_type=QUInt8)
ONNX Quantized (30MB)    ◀── ships in extension
    │
    ▼  Optional: quantize to q4
ONNX q4 (18MB)           ◀── if size is critical
```

```bash
# Export pipeline
optimum-cli export onnx \
  --model ./ragebait-distilbert \
  --task text-classification \
  ./onnx-model/

# Quantize
python -c "
from onnxruntime.quantization import quantize_dynamic, QuantType
quantize_dynamic(
    'onnx-model/model.onnx',
    'onnx-model/model_q8.onnx',
    weight_type=QuantType.QUInt8
)
"
```

### Phase 5: Browser Integration

```
Extension Package Structure
───────────────────────────

ragepage/
├── extension/
│   ├── manifest.json
│   ├── content.js           # Post detection + dot injection
│   ├── content.css
│   ├── background.js        # Service worker: loads model, runs inference
│   ├── popup/
│   │   ├── popup.html
│   │   └── popup.js
│   ├── model/               # Bundled DistilBERT
│   │   ├── model_q8.onnx    # ~30MB quantized model
│   │   ├── tokenizer.json   # WordPiece tokenizer
│   │   └── config.json      # Model config
│   └── icons/
├── training/                 # Model training pipeline
│   ├── collect_data.py       # Data collection scripts
│   ├── label_with_sonnet.py  # Teacher labeling
│   ├── train.py              # Fine-tuning script
│   ├── export_onnx.py        # Export + quantize
│   └── evaluate.py           # Test against held-out set
└── README.md
```

**Service worker model loading:**

```javascript
// background.js
import { pipeline } from '@xenova/transformers';

let classifier = null;

// Load model on extension install/startup
async function loadModel() {
  classifier = await pipeline(
    'text-classification',
    'ragecheck/distilbert-ragebait-v1',  // hosted on HuggingFace
    { quantized: true }                   // use q8 ONNX
  );
}

// Handle scoring requests from content script
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg.action === 'score' && classifier) {
    classifier(msg.text).then(result => {
      sendResponse({ score: Math.round(result[0].score * 100) });
    });
    return true; // async response
  }
});

loadModel();
```

**Content script integration:**

```javascript
// content.js (simplified)
async function scorePost(text) {
  return new Promise((resolve) => {
    chrome.runtime.sendMessage(
      { action: 'score', text },
      (response) => resolve(response?.score ?? 0)
    );
  });
}

async function processPost(post) {
  const text = getPostText(post);
  const score = await scorePost(text);  // ~50ms, local

  if (score >= 10) {
    placeDot(post, score);  // yellow or red dot, instant
  }
}
```

## Performance Projections

```
                      Current (API)           Distilled (Local)
                      ─────────────           ─────────────────
Latency per post      2,500-6,000ms           30-80ms
Cost per post         $0.002-0.005            $0.000
Works offline         No                      Yes
Privacy               Text sent to server     All local
Concurrent scoring    Limited by API          Unlimited
Posts/second          0.2-0.5                 15-30
Feed scan (20 posts)  10-30 seconds           ~1 second
```

### Cost Comparison at Scale

```
                   1K users    10K users    100K users
                   ────────    ─────────    ──────────
Haiku dots         $60/mo      $600/mo      $6,000/mo
Sonnet dots        $300/mo     $3,000/mo    $30,000/mo
Distilled dots     $0/mo       $0/mo        $0/mo      ◀──
                   ──────      ───────      ──────────
Sonnet on-click    $150/mo     $1,500/mo    $15,000/mo
(same for all)
```

*Assumes 20 checks/day per active user, 30% of posts trigger on-click analysis*

## Quality Assurance

### Evaluation Framework

```
┌──────────────────────────────────────────────────────────┐
│                    Eval Pipeline                          │
│                                                          │
│  Test Set: 1,000 held-out posts (never seen in training) │
│                                                          │
│  Metrics:                                                │
│  ├── MAE (Mean Absolute Error vs Sonnet scores)          │
│  ├── Classification accuracy (3-class: low/mid/high)     │
│  ├── Precision/Recall on ragebait class                  │
│  ├── Correlation (Pearson r with Sonnet scores)          │
│  └── Edge case audit (50 hand-picked hard examples)      │
│                                                          │
│  Acceptance Criteria:                                    │
│  ├── MAE < 10 points                                    │
│  ├── Classification accuracy > 85%                       │
│  ├── Ragebait recall > 90% (don't miss rage bait)        │
│  └── False positive rate < 10%                           │
└──────────────────────────────────────────────────────────┘
```

### Continuous Improvement Loop

```
  ┌──────────┐
  │ Users    │
  │ click    │──── "Check" on posts where dot seems wrong
  │ "Check"  │
  └────┬─────┘
       │
       ▼
  ┌──────────┐
  │ Sonnet   │──── Produces authoritative score
  │ scores   │
  │ the post │
  └────┬─────┘
       │
       ▼
  ┌──────────────┐
  │ Compare      │──── dot score vs Sonnet score
  │ dot vs LLM   │     If gap > 20 points, flag for retraining
  └────┬─────────┘
       │
       ▼
  ┌──────────────┐
  │ Add to       │──── Grows training set organically
  │ training data│     Focuses on posts the model gets wrong
  └────┬─────────┘
       │
       ▼
  ┌──────────────┐
  │ Retrain      │──── Monthly or when accuracy dips
  │ model v2     │     Push update via Chrome Web Store
  └──────────────┘
```

## Implementation Roadmap

```
Week 1: Data Collection
├── Set up scraping pipeline (Twitter API, Reddit API, pushshift)
├── Collect 10K posts with topic diversity
├── Manual review of 200 edge cases
└── Split into train/val/test

Week 2: Teacher Labeling
├── Run all 10K posts through Sonnet via RageCheck API
├── Store scores + reasons + signal breakdowns
├── Analyze label distribution, rebalance if needed
└── Cost: ~$50

Week 3: Model Training
├── Set up training environment (Colab or local GPU)
├── Fine-tune DistilBERT regression model
├── Hyperparameter sweep (learning rate, epochs, max_length)
├── Evaluate on test set, compare to Sonnet agreement
└── Try alternative base models (TinyBERT, DeBERTa-small)

Week 4: Export + Integration
├── Export best model to ONNX
├── Quantize to q8 (and q4 for comparison)
├── Integrate Transformers.js into extension service worker
├── Wire up content.js → background.js scoring pipeline
├── A/B test: distilled dots vs no dots
└── Ship to Chrome Web Store
```

## Risks and Mitigations

```
Risk                              Mitigation
────                              ──────────
Model too large for extension     Use TinyBERT (8MB) or q4 quantization
  (Chrome Web Store 50MB limit)     DistilBERT q8 is ~30MB, well within limit

Model accuracy degrades on        Include diverse platforms in training data
  unseen platforms/topics           Monthly retraining with new labeled data

Transformers.js too slow on       Fall back to rule engine on low-end devices
  low-end devices                   Use Web Workers to avoid blocking UI

Users don't trust local model     Show "Verified by AI" badge on Check click
  scores without explanation        Dots are indicators; Check gives details

Training data becomes stale       Continuous learning loop from Check clicks
  as ragebait tactics evolve        Automated retraining pipeline
```

## Alternative: Chrome Built-in AI (Gemini Nano)

Chrome 130+ ships with Gemini Nano on-device. This is a zero-effort alternative:

```javascript
// No model bundling needed — Chrome provides the model
const session = await ai.languageModel.create({
  systemPrompt: "Score text 0-100 for ragebait manipulation."
});

const result = await session.prompt(postText);
const score = parseInt(result);
```

**Pros:** No model to train, no ONNX export, no storage cost, always up-to-date
**Cons:** Only works in Chrome (not Firefox/Safari), Google controls the model, less customizable, requires user opt-in to download Gemini Nano (~1.7GB)

**Recommendation:** Build the distilled model as primary, add Gemini Nano as an optional enhancer or fallback.
