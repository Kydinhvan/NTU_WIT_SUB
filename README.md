# Bridge — Peer Support Matching Platform

**Human-first peer support for university communities.**

Bridge connects students seeking emotional support with peers who've navigated similar challenges. Using AI-powered psychometric profiling and semantic embeddings, we match people based on deep emotional resonance — not just keywords.

---

## 🎯 What Bridge Does

- **Seeker onboarding**: Conversational AI guides venting → extracts psychological profile
- **Helper onboarding**: Per-theme narrative collection → mirrored scoring on 8+ metrics
- **Smart matching**: Cosine similarity on emotion embeddings + coping style + conversation preference + theme narratives
- **Safety screening**: AI risk classifier flags crisis indicators before matching
- **In-chat scaffolding**: Real-time conversation suggestions for helpers

---

## 🏗️ Architecture

```
NTU_WH/
├── bridge/              # Flutter frontend (web + mobile)
│   ├── lib/
│   │   ├── features/    # Seeker & Helper flows
│   │   ├── models/      # Profile, Match, User models
│   │   └── shared/      # Services (AI, Matching, Firebase)
│   └── web/             # Web build output
│
├── hackathonerds/       # FastAPI backend
│   ├── api.py           # REST endpoints (OpenRouter + STT + Matching)
│   ├── local_test_matcher.py  # DHA matching algorithm + embeddings
│   ├── stt.py           # Faster-whisper transcription
│   └── .env             # API keys (YOU NEED TO CREATE THIS)
│
└── .venv/               # Python virtual environment
```

**Tech Stack:**
- **Frontend**: Flutter 3.x (Dart), Riverpod, go_router, http
- **Backend**: FastAPI (Python), sentence-transformers, faster-whisper, OpenRouter/OpenAI SDK
- **Embeddings**: all-MiniLM-L6-v2 (384D, local, free)
- **AI**: OpenRouter (gpt-4o-mini) with caching, rate limiting, fallbacks

---

## 🚀 Quick Start (Local Setup)

### Prerequisites

- **Flutter SDK** 3.2.0+ ([Install Flutter](https://flutter.dev/docs/get-started/install))
- **Python** 3.10+ ([Download Python](https://www.python.org/downloads/))
- **Chrome** (for web demo) or Android Studio (for mobile)

### 1. Clone & Navigate

```bash
git clone https://github.com/Kydinhvan/NTU_WIT_SUB.git
cd NTU_WIT_SUB
```

### 2. Backend Setup

#### a) Create virtual environment & install dependencies

```bash
# Windows PowerShell
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r hackathonerds/requirements.txt
```

```bash
# macOS/Linux
python3 -m venv .venv
source .venv/bin/activate
pip install -r hackathonerds/requirements.txt
```

#### b) Configure environment variables

Create `hackathonerds/.env` file:

```bash
# Copy the example
cp hackathonerds/.env.example hackathonerds/.env

# Edit .env and add your OpenRouter API key
# Get a free key at https://openrouter.ai/keys
```

Your `.env` should look like:

```
OPENROUTER_API_KEY=sk-or-v1-YOUR_KEY_HERE
```

> **Note**: OpenRouter has a free tier with $1 credit. The app uses `gpt-4o-mini` ($0.15/M tokens) with aggressive caching and rate limiting to minimize costs.

#### c) Start the backend server

```bash
cd hackathonerds
uvicorn api:app --host 0.0.0.0 --port 8000 --reload
```

You should see:
```
INFO:     Helper pool seeded: 30 helpers
INFO:     OpenRouter client initialized (model=openai/gpt-4o-mini)
INFO:     Uvicorn running on http://0.0.0.0:8000
```

Leave this terminal running and open a new one for the frontend.

### 3. Frontend Setup

#### a) Install Flutter dependencies

```bash
cd bridge
flutter pub get
```

#### b) Run the app

**For web demo:**

```bash
flutter run -d chrome
```

**For mobile (Android emulator must be running):**

```bash
flutter run -d android
```

**For Windows desktop:**

```bash
flutter run -d windows
```

The app will open automatically. Backend must be running on `localhost:8000`.

---

## 🎮 Demo Flow

### As a Seeker:

1. **Start** → Choose **"I need support"**
2. **Vent** → Record or type how you're feeling (AI chat guide available)
3. **Safety check** → AI screens for crisis indicators
4. **Processing** → Profile extraction + embedding generation
5. **Match results** → See ranked helpers with match explanations
6. **Chat** → Connect with matched helper (real-time suggestions for helper)

### As a Helper:

1. **Start** → Choose **"I want to help"**
2. **Select themes** → Pick experiences you've navigated (e.g., Exam Stress, Loneliness)
3. **Share stories** → Write 2-3 min narrative for each theme (AI analyzes emotional depth, resilience, coping methods)
4. **Choose style** → How you prefer to help (listen, advise, explore together)
5. **Set energy** → Current capacity level
6. **Ready** → Enter helper pool, available for matching

---

## 🔧 Configuration

### Backend API Constants

Edit `bridge/lib/core/constants/api_constants.dart`:

```dart
static const baseUrl = "http://localhost:8000";  // Change for deployment
static const useMock = false;  // Set true to disable backend (uses scripted responses)
```

### AI Model & Rate Limits

Edit `hackathonerds/api.py`:

```python
GPT_MODEL = "openai/gpt-4o-mini"  # Change model here

RATE_LIMITS = {
    "seeker_chat": 15,      # chat turns per minute
    "extract_seeker": 5,    # profile extractions per minute
    "extract_helper": 5,
    "safety_check": 10,
    "scaffold": 20,
}

MAX_INPUT_CHARS = 2000  # Truncate inputs to save tokens
```

### Embedding Model

Edit `hackathonerds/local_test_matcher.py`:

```python
USE_OPENAI = False  # True = OpenAI embeddings (costs $$), False = sentence-transformers (free)
```

---

## 📡 API Endpoints

All endpoints on `http://localhost:8000`:

| Endpoint | Method | Purpose | AI Used |
|----------|--------|---------|---------|
| `/transcribe` | POST | Audio → text (faster-whisper) | ❌ Local |
| `/extract-profile` | POST | Text → Profile (3 modes) | ✅ Cached |
| `/match` | POST | Seeker → Ranked helpers | ❌ Local |
| `/discover` | POST | Browse by theme (Netflix-style) | ❌ Local |
| `/safety-check` | POST | Risk classification (low/med/high) | ✅ Cached |
| `/scaffold` | POST | Helper chat suggestions | ✅ Cached |
| `/health` | GET | Server status & cache stats | ❌ |
| `/helpers` | GET | List all helpers (debug) | ❌ |

**Credit optimization:**
- Response cache hits save AI calls (200-entry LRU)
- Rate limits enforce per-minute caps per endpoint
- Fallback scripts activate when AI unavailable or rate-limited
- Short inputs skip AI entirely (e.g., safety check < 20 chars)

---

## 🧪 Testing without AI Credits

Set `useMock = true` in `api_constants.dart`. The app will:
- Use scripted 4-question seeker chat
- Generate profiles from selected themes only (no AI analysis)
- Skip safety checks (always "low")
- Use pre-written scaffold suggestions

Alternatively, just don't set `OPENROUTER_API_KEY` in `.env` — the backend falls back gracefully.

---

## 🏆 Key Features for Judges

### 1. **Per-Theme Narrative Analysis** (NEW!)
Helpers write stories for each theme they've experienced. AI scores 8 mirrored metrics:
- Emotional depth
- Resilience demonstrated
- Approach style (intro/extro/balanced)
- Coping method used
- Communication tone
- Empathy signal
- Actionability
- Self-awareness

These feed into the matcher as a +10% bonus, enabling **personality-aware** seeker↔helper alignment.

### 2. **DHA Matching Algorithm**
Weighted formula with learned model fallback:
```
score = 0.35·emotional_sim + 0.25·experience_overlap + 
        0.15·coping_match + 0.10·availability + 
        0.10·narrative_bonus + 0.10·conversation + 0.05·energy
```

### 3. **Credit-Saving Infrastructure**
- LRU cache for all AI responses
- Per-endpoint rate limiting
- Input truncation (2000 chars max)
- Output token caps (150 for chat, 5 for safety)
- Message windowing (last 4-6 only)
- Model: gpt-4o-mini ($0.15/M vs $2.50/M for gpt-4o)

**Expected cost for demo:** <$0.10 for 20 full seeker+helper onboardings with matching.

### 4. **Graceful Degradation**
Every AI endpoint has a fallback:
- Seeker chat → 4-question script
- Profile extraction → defaults from selected themes
- Safety check → "low" default
- Scaffold → mode-based pre-written suggestions

The app never breaks when AI is unavailable.

---

## 📁 Project Structure Details

### Frontend Key Files

```
bridge/lib/
├── features/
│   ├── onboarding/
│   │   ├── seeker/
│   │   │   └── screens/chat_screen.dart        # AI chat onboarding
│   │   └── helper/
│   │       └── screens/helper_chat_screen.dart # Per-theme narratives
│   ├── seeker/
│   │   ├── screens/processing_screen.dart      # Match processing
│   │   └── screens/match_results_screen.dart   # Ranked helpers
│   └── helper/
│       └── screens/active_chat_screen.dart     # Helper chat w/ scaffolding
│
├── shared/services/
│   ├── ai_chat_service.dart        # /extract-profile API wrapper
│   ├── matching_service.dart       # /match API wrapper
│   └── transcription_service.dart  # /transcribe with blob upload
│
└── models/
    ├── seeker_profile.dart  # Themes, coping, conversation, energy, distress
    ├── helper_profile.dart  # + theme_scores (8 metrics per theme)
    └── match_result.dart    # Score, breakdown, explanation, helper
```

### Backend Key Files

```
hackathonerds/
├── api.py                      # FastAPI app, all endpoints, caching, rate limiting
├── local_test_matcher.py       # DHA matching + embeddings + theme_narrative_match_score()
├── stt.py                      # faster-whisper file transcription
├── requirements.txt            # Python dependencies
└── .env                        # OPENROUTER_API_KEY (create this)
```

---

## 🐛 Troubleshooting

### Backend won't start

**Error:** `ModuleNotFoundError: No module named 'fastapi'`
- **Fix:** Activate venv and reinstall: `pip install -r hackathonerds/requirements.txt`

**Error:** `OPENROUTER_API_KEY not set; using mock fallbacks`
- **Fix:** Create `hackathonerds/.env` with your API key

### Frontend can't connect to backend

**Error:** `ClientException: Failed to fetch, uri=http://localhost:8000/...`
- **Fix:** Ensure backend is running (check terminal with `uvicorn` command)
- **Fix:** Check `api_constants.dart` has correct `baseUrl`

### Match returns 500 error

**Error:** `Unable to serialize unknown type: <class 'numpy.float32'>`
- **Fix:** Already fixed — `_sanitize()` converts numpy types. Restart backend.

### OpenRouter 429 quota exceeded

- **Solution 1:** Backend automatically falls back to scripted responses
- **Solution 2:** Wait 1 minute (rate limit resets)
- **Solution 3:** Set `useMock = true` in Flutter to bypass AI entirely

### Transcription not working on web

- **Expected:** Web uses blob URLs. `transcription_service.dart` fetches blob bytes and POSTs as multipart.
- **Fallback:** If backend STT fails, mock transcript is used automatically.

---

## 📊 Performance Benchmarks

**Backend:**
- Profile extraction: ~800ms (w/ AI), ~5ms (cached), ~2ms (fallback)
- Matching (30 helpers): ~15ms (embeddings already computed)
- Safety check: ~600ms (w/ AI), ~3ms (cached), ~1ms (fallback)

**Frontend:**
- Seeker onboarding: 3-4 chat turns (~8s total with thinking time)
- Helper onboarding: 2-5 min per theme narrative writing
- Match results render: <100ms

**AI Costs (OpenRouter gpt-4o-mini):**
- Seeker profile: 400 tokens in, 250 out = **$0.0001**
- Helper profile: 600 tokens in, 400 out = **$0.0002**
- Chat turn: 150 tokens in, 100 out = **$0.00003**
- With caching: **60-80% cache hit rate** in typical usage

---

## 🎨 Design Philosophy

**Human-first, not tech-first:**
- Warm serif fonts (EB Garamond) for storytelling
- Earthy color palette (sage, cream, amber)
- No clinical language — "vent", "themes", "energy", "vibe"
- Privacy-first messaging ("No one will read this — only AI for matching")

**AI as invisible infrastructure:**
- Users never see "GPT" or "embeddings"
- Fallbacks are indistinguishable from AI responses
- Matching "just works" — algorithm is explained, not exposed

---

## 👥 Team

- **Wenting** — Flutter frontend, UX design
- **Tim** — STT integration (faster-whisper)
- **Dha** — Matching algorithm, embeddings, learned model
- **All** — Backend integration, AI orchestration, deployment

Built for **NTU Hackathon 2026**.

---

## 📄 License

This project is for hackathon demonstration purposes. Not for production use without privacy/security audit.

---

## 🙏 Acknowledgments

- **sentence-transformers** for free local embeddings
- **OpenRouter** for affordable AI routing
- **Flutter** team for cross-platform excellence
- **FastAPI** for delightful Python web APIs
- Every student who trusted us with their story 💚
