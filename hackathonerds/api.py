"""
Bridge FastAPI Backend
Exposes hackathonerds matching + STT + GPT-4o as REST endpoints for the Flutter app.

Run:
    uvicorn api:app --host 0.0.0.0 --port 8000 --reload

Endpoints:
    POST /transcribe        — Audio file → transcript (Tim's faster-whisper)
    POST /extract-profile   — Transcript → SeekerProfile / HelperProfile (GPT-4o)
    POST /match             — SeekerProfile + helpers → ranked matches (Dha's algo)
    POST /discover          — Theme → ranked helpers (Netflix lanes)
    POST /safety-check      — Transcript → risk level (GPT-4o classifier)
    POST /scaffold          — Chat context → helper suggestion (GPT-4o)
"""

import os
import json
import tempfile
import logging
import time
import hashlib
from typing import List, Optional
from collections import OrderedDict
import numpy as np

from dotenv import load_dotenv
load_dotenv()

from fastapi import FastAPI, Request, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("bridge.api")

# ── Import matching engine (fixed import order) ──────────────────────────────
from local_test_matcher import (
    match_seeker_to_helpers,
    discover_by_theme,
    generate_emotion_embedding,
    compute_dha_match_score,
    generate_helper,
    THEMES,
    COPING_STYLES,
    CONVERSATION_PREFERENCES,
    SENTENCE_TRANSFORMERS_AVAILABLE,
)

from stt import transcribe_file

# ── OpenRouter client (for extract-profile, safety-check, scaffold) ────────────
try:
    from openai import OpenAI
    api_key = os.getenv("OPENROUTER_API_KEY")
    if api_key:
        openai_client = OpenAI(
            api_key=api_key,
            base_url="https://openrouter.ai/api/v1",
        )
        GPT_MODEL = "openai/gpt-4o-mini"  # cheapest good model — $0.15/M input
        logger.info("OpenRouter client initialized (model=%s)", GPT_MODEL)
    else:
        openai_client = None
        GPT_MODEL = None
        logger.info("OPENROUTER_API_KEY not set; using mock fallbacks")
except Exception:
    logger.error("Failed to initialize OpenRouter client", exc_info=True)
    openai_client = None
    GPT_MODEL = None


# ── Credit-saving infrastructure ─────────────────────────────────────────────

# LRU response cache — avoids re-calling AI for identical inputs
_CACHE_MAX = 200
_response_cache: OrderedDict = OrderedDict()

def _cache_key(prefix: str, text: str) -> str:
    """Generate a cache key from prefix + first 500 chars of text."""
    return hashlib.md5(f"{prefix}:{text[:500]}".encode()).hexdigest()

def _cache_get(key: str):
    if key in _response_cache:
        _response_cache.move_to_end(key)
        logger.info("Cache HIT — saved 1 AI call")
        return _response_cache[key]
    return None

def _cache_set(key: str, value):
    _response_cache[key] = value
    if len(_response_cache) > _CACHE_MAX:
        _response_cache.popitem(last=False)

# Per-endpoint rate limiter — max N calls per minute
_rate_windows: dict = {}  # endpoint → list of timestamps
RATE_LIMITS = {
    "seeker_chat": 15,      # max 15 chat turns/min
    "extract_seeker": 5,    # max 5 profile extractions/min
    "extract_helper": 5,
    "safety_check": 10,
    "scaffold": 20,         # helpers need suggestions frequently
}

def _rate_ok(endpoint: str) -> bool:
    """Check if we're within rate limit for this endpoint."""
    now = time.time()
    limit = RATE_LIMITS.get(endpoint, 10)
    window = _rate_windows.setdefault(endpoint, [])
    # Prune entries older than 60s
    _rate_windows[endpoint] = [t for t in window if now - t < 60]
    if len(_rate_windows[endpoint]) >= limit:
        logger.warning("Rate limit hit for %s (%d/%d per min) — using fallback", endpoint, len(_rate_windows[endpoint]), limit)
        return False
    _rate_windows[endpoint].append(now)
    return True

# Input truncation — cap input tokens to save credits
MAX_INPUT_CHARS = 2000  # ~500 tokens, plenty for profile extraction

def _truncate(text: str, max_chars: int = MAX_INPUT_CHARS) -> str:
    if len(text) <= max_chars:
        return text
    logger.info("Truncating input from %d to %d chars", len(text), max_chars)
    return text[:max_chars] + "..."


app = FastAPI(title="Bridge API", version="1.0.0")

# Allow Flutter web to call us
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Request logging middleware (shows frontend ↔ backend connection) ─────────
@app.middleware("http")
async def log_requests(request: Request, call_next):
    start = time.time()
    logger.info("⬅️  %s %s from %s", request.method, request.url.path, request.client.host)
    response = await call_next(request)
    elapsed = (time.time() - start) * 1000
    logger.info("➡️  %s %s → %s (%.0fms)", request.method, request.url.path, response.status_code, elapsed)
    # Skip ngrok browser warning page for API calls
    response.headers["ngrok-skip-browser-warning"] = "true"
    return response

# ── In-memory helper pool (seeded on startup) ────────────────────────────────
from local_test_matcher import generate_helper
helper_pool: list = [generate_helper() for _ in range(30)]
logger.info("Helper pool seeded: %d helpers — IDs: %s",
            len(helper_pool), [h['user_id'] for h in helper_pool])


# ── Request / Response Models ────────────────────────────────────────────────

class TranscribeRequest(BaseModel):
    audio_url: str  # local path or Firebase Storage URL

class TranscribeResponse(BaseModel):
    transcript: str

class ThemeItem(BaseModel):
    name: str
    intensity: float

class SeekerProfileRequest(BaseModel):
    transcript: Optional[str] = None
    mode: str = "extract_seeker"  # extract_seeker | extract_helper | seeker_chat
    messages: Optional[List[dict]] = None  # for seeker_chat mode
    narrative: Optional[str] = None  # for extract_helper mode
    selected_themes: Optional[List[str]] = None  # for extract_helper mode
    theme_narratives: Optional[dict] = None  # per-theme story text {"Exam Stress": "I went through..."}

class SeekerProfileResponse(BaseModel):
    themes: List[dict]
    coping_style_preference: dict
    conversation_preference: dict
    energy_level: str
    distress_level: str
    urgency: float

class MatchRequest(BaseModel):
    seeker_profile: dict
    helper_ids: Optional[List[str]] = None

class MatchResponse(BaseModel):
    matches: List[dict]

class DiscoverRequest(BaseModel):
    theme_name: str
    top_k: int = 10

class SafetyRequest(BaseModel):
    transcript: str

class SafetyResponse(BaseModel):
    risk_level: str  # low | medium | high

class ScaffoldRequest(BaseModel):
    mode: str
    system_prompt: str
    messages: List[dict]

class ScaffoldResponse(BaseModel):
    suggestion: str


# ── Endpoints ────────────────────────────────────────────────────────────────

@app.post("/transcribe", response_model=TranscribeResponse)
async def transcribe(file: UploadFile = File(None), body: TranscribeRequest = None):
    """Transcribe audio file → text using faster-whisper."""
    logger.info("/transcribe requested (file=%s, url=%s)", bool(file), getattr(body, "audio_url", None))
    if file:
        # Uploaded file
        suffix = ".m4a" if file.filename and file.filename.endswith(".m4a") else ".wav"
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
            content = await file.read()
            tmp.write(content)
            tmp_path = tmp.name
        transcript = transcribe_file(tmp_path)
        os.unlink(tmp_path)
    elif body and body.audio_url:
        transcript = transcribe_file(body.audio_url)
    else:
        logger.error("/transcribe missing file or audio_url")
        raise HTTPException(400, "Provide audio file or audio_url")
    logger.info("/transcribe completed (chars=%s)", len(transcript))
    return TranscribeResponse(transcript=transcript)


@app.post("/extract-profile")
async def extract_profile(req: SeekerProfileRequest):
    """Use AI to extract a structured profile from vent/narrative text."""
    logger.info("/extract-profile requested (mode=%s, ai=%s)", req.mode, openai_client is not None)

    # ── seeker_chat mode: conversational follow-up ──
    if req.mode == "seeker_chat":
        if not openai_client or not _rate_ok("seeker_chat"):
            logger.info("/extract-profile seeker_chat using scripted fallback")
            return _seeker_chat_fallback(req.messages or [])

        # Debounce: cache by last user message
        msgs = req.messages or []
        last_user = next((m["content"] for m in reversed(msgs) if m.get("role") == "user"), "")
        ck = _cache_key("seeker_chat", last_user)
        cached = _cache_get(ck)
        if cached:
            return cached

        try:
            system_msg = (
                "You are a warm, empathetic mental-health onboarding assistant called Bridge. "
                "Your goal is to gently understand the user's situation in 3-4 exchanges, "
                "then say you'll find them someone who understands. Keep replies short (2-3 sentences)."
            )
            # Only send last 6 messages to save tokens
            recent = msgs[-6:]
            api_msgs = [{"role": "system", "content": system_msg}] + recent
            resp = openai_client.chat.completions.create(
                model=GPT_MODEL, messages=api_msgs,
                temperature=0.7, max_tokens=150,
            )
            result = {"reply": resp.choices[0].message.content.strip()}
            _cache_set(ck, result)
            logger.info("/extract-profile seeker_chat completed")
            return result
        except Exception:
            logger.error("/extract-profile seeker_chat AI failed, using fallback", exc_info=True)
            return _seeker_chat_fallback(msgs)

    # ── extract_helper mode ──
    if req.mode == "extract_helper":
        if not openai_client or not _rate_ok("extract_helper"):
            logger.info("/extract-profile extract_helper using fallback profile")
            return _extract_helper_fallback(req.selected_themes, req.theme_narratives)

        user_content = ""
        if req.theme_narratives:
            for theme_name, story in req.theme_narratives.items():
                if story and story.strip():
                    user_content += f"\n\n## {theme_name}\n{_truncate(story.strip(), 400)}"
        elif req.narrative:
            user_content = _truncate(req.narrative)
        if req.selected_themes:
            user_content += f"\n\nSelected themes: {', '.join(req.selected_themes)}"

        ck = _cache_key("extract_helper", user_content)
        cached = _cache_get(ck)
        if cached:
            return cached

        try:
            system_prompt = f"""You are an expert psychometric profiler for a peer-support matching platform.
Analyze the helper's per-theme narratives and score them on MIRRORED METRICS that match how seekers are scored.

Return ONLY valid JSON with this structure:
{{
  "themes": [{{"name": "<one of {THEMES}>", "intensity": 0.0-1.0}}],
  "coping_style": "<one of {list(COPING_STYLES)}>",
  "communication_style": "<one of {list(CONVERSATION_PREFERENCES)}>",
  "bio": "1-2 sentence bio summarizing their experience",
  "theme_scores": {{
    "<theme_name>": {{
      "emotional_depth": 0.0-1.0,
      "resilience_demonstrated": 0.0-1.0,
      "approach_style": "introvert|extrovert|balanced",
      "coping_method": "<one of {list(COPING_STYLES)}>",
      "communication_tone": "<one of {list(CONVERSATION_PREFERENCES)}>",
      "empathy_signal": 0.0-1.0,
      "actionability": 0.0-1.0,
      "self_awareness": 0.0-1.0
    }}
  }}
}}"""

            resp = openai_client.chat.completions.create(
                model=GPT_MODEL,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_content},
                ],
                temperature=0.3, max_tokens=600,
            )
            text = resp.choices[0].message.content.strip()
            if text.startswith("```"):
                text = text.split("\n", 1)[1].rsplit("```", 1)[0]
            try:
                parsed = json.loads(text)
                _cache_set(ck, parsed)
            except Exception:
                logger.error("/extract-profile extract_helper JSON parse failed", exc_info=True)
                return _extract_helper_fallback(req.selected_themes, req.theme_narratives)
            logger.info("/extract-profile extract_helper completed")
            return parsed
        except Exception:
            logger.error("/extract-profile extract_helper AI failed, using fallback", exc_info=True)
            return _extract_helper_fallback(req.selected_themes, req.theme_narratives)

    # ── extract_seeker mode (default) ──
    if not openai_client or not _rate_ok("extract_seeker"):
        logger.info("/extract-profile extract_seeker using fallback profile")
        return _extract_seeker_fallback()

    transcript_text = _truncate(req.transcript or "")
    ck = _cache_key("extract_seeker", transcript_text)
    cached = _cache_get(ck)
    if cached:
        return cached

    try:
        system_prompt = f"""Extract a structured profile from this vent/narrative. Return ONLY valid JSON with:
- themes: list of {{"name": "<one of {THEMES}>", "intensity": 0.0-1.0}}
- coping_style_preference: {{"problem_focused": 0-1, "emotion_focused": 0-1, "social_support": 0-1, "avoidant": 0-1, "meaning_making": 0-1}}
- conversation_preference: {{"direct_advice": 0-1, "reflective_listening": 0-1, "collaborative_problem_solving": 0-1, "validation_focused": 0-1}}
- energy_level: one of ["depleted", "low", "moderate", "high"]
- distress_level: one of ["Low", "Medium", "High"]
- urgency: 0-1 float"""

        resp = openai_client.chat.completions.create(
            model=GPT_MODEL,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": transcript_text},
            ],
            temperature=0.3, max_tokens=400,
        )
        text = resp.choices[0].message.content.strip()
        if text.startswith("```"):
            text = text.split("\n", 1)[1].rsplit("```", 1)[0]
        try:
            parsed = json.loads(text)
            _cache_set(ck, parsed)
        except Exception:
            logger.error("/extract-profile extract_seeker JSON parse failed", exc_info=True)
            return _extract_seeker_fallback()
        logger.info("/extract-profile extract_seeker completed")
        return parsed
    except Exception:
        logger.error("/extract-profile extract_seeker AI failed, using fallback", exc_info=True)
        return _extract_seeker_fallback()


@app.post("/match", response_model=MatchResponse)
async def match(req: MatchRequest):
    """Match seeker profile to helpers using Dha's algorithm."""
    seeker = req.seeker_profile
    logger.info("/match requested (helper_ids=%s)", bool(req.helper_ids))

    # Generate embedding from vent text if not already present
    if "emotion_embedding" not in seeker or seeker["emotion_embedding"] is None:
        vent = seeker.get("vent_text", "")
        seeker["emotion_embedding"] = generate_emotion_embedding(vent, use_openai=False)

    # Use full helper pool or filter by IDs
    pool = helper_pool
    if req.helper_ids:
        pool = [h for h in helper_pool if h["user_id"] in req.helper_ids]

    results = match_seeker_to_helpers(seeker, pool, top_k=5, use_learned=True)

    matches = []
    for i, (score, helper_id, breakdown, helper) in enumerate(results):
        themes = helper.get("themes_experience", {})
        top_theme = max(themes, key=themes.get) if themes else "General Support"
        matches.append({
            "match_id": f"match_{i+1:03d}",
            "helper_id": helper_id,
            "score": score,
            "breakdown": breakdown,
            "top_theme": top_theme,
            "explanation": _generate_explanation(breakdown, helper),
            "helper": {
                "user_id": helper.get("user_id", ""),
                "display_name": helper.get("display_name", "Anonymous Helper"),
                "age_decade": helper.get("age_decade", "30s"),
                "themes_experience": helper.get("themes_experience", {}),
                "coping_style_expertise": helper.get("coping_style_expertise", {}),
                "conversation_style": helper.get("conversation_style", {}),
                "energy_level": helper.get("energy_level", "moderate"),
                "reliability_score": helper.get("reliability_score", 0.8),
                "response_rate": helper.get("response_rate", 0.8),
                "completion_rate": helper.get("completion_rate", 0.8),
                "experience_narrative": helper.get("experience_narrative"),
            },
        })

    logger.info("/match completed (matches=%s)", len(matches))
    return MatchResponse(matches=_sanitize(matches))


def _sanitize(obj):
    """Recursively convert numpy types to native Python types for JSON serialization."""
    if isinstance(obj, dict):
        return {k: _sanitize(v) for k, v in obj.items()}
    if isinstance(obj, (list, tuple)):
        return [_sanitize(v) for v in obj]
    if isinstance(obj, (np.floating, np.float32, np.float64)):
        return float(obj)
    if isinstance(obj, (np.integer, np.int32, np.int64)):
        return int(obj)
    if isinstance(obj, np.ndarray):
        return obj.tolist()
    return obj


@app.post("/discover")
async def discover(req: DiscoverRequest):
    """Netflix-style discovery: browse helpers by theme."""
    logger.info("/discover requested (theme=%s, top_k=%s)", req.theme_name, req.top_k)
    results = discover_by_theme(req.theme_name, helper_pool, top_k=req.top_k)
    return {"helpers": [{"helper_id": hid, "score": sc} for sc, hid in results]}


@app.post("/safety-check", response_model=SafetyResponse)
async def safety_check(req: SafetyRequest):
    """AI risk classifier — screens vent before matching."""
    logger.info("/safety-check requested (ai=%s)", openai_client is not None)

    # Skip AI for very short texts — not enough signal
    if len(req.transcript.strip()) < 20:
        logger.info("/safety-check text too short, defaulting to low")
        return SafetyResponse(risk_level="low")

    if not openai_client or not _rate_ok("safety_check"):
        logger.info("/safety-check using default risk level")
        return SafetyResponse(risk_level="low")

    # Cache safety checks
    truncated = _truncate(req.transcript, 1000)
    ck = _cache_key("safety", truncated)
    cached = _cache_get(ck)
    if cached:
        return SafetyResponse(risk_level=cached)

    try:
        system_prompt = (
            "You are a mental health risk classifier. Assess the following text for self-harm, "
            "suicidal ideation, or crisis indicators. Respond with ONLY one word: low, medium, or high."
        )
        resp = openai_client.chat.completions.create(
            model=GPT_MODEL,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": truncated},
            ],
            temperature=0.0, max_tokens=5,
        )
        level = resp.choices[0].message.content.strip().lower()
        if level not in ("low", "medium", "high"):
            logger.error("/safety-check invalid model output: %s", level)
            level = "low"
        _cache_set(ck, level)
        logger.info("/safety-check completed (risk_level=%s)", level)
        return SafetyResponse(risk_level=level)
    except Exception:
        logger.error("/safety-check AI failed, defaulting to low", exc_info=True)
        return SafetyResponse(risk_level="low")


@app.post("/scaffold", response_model=ScaffoldResponse)
async def scaffold(req: ScaffoldRequest):
    """Generate in-chat helper suggestion based on conversation mode."""
    logger.info("/scaffold requested (mode=%s, ai=%s)", req.mode, openai_client is not None)

    if not openai_client or not _rate_ok("scaffold"):
        logger.info("/scaffold using fallback suggestion")
        return ScaffoldResponse(suggestion=_scaffold_fallback(req.mode))

    # Only send last 4 messages to save tokens
    context_msgs = req.messages[-4:]
    user_content = (
        "Conversation so far:\n" +
        "\n".join(f"{m['role']}: {_truncate(m['content'], 200)}" for m in context_msgs) +
        "\n\nSuggest ONE short, warm response the helper could say. Start with 'Try: '"
    )

    ck = _cache_key("scaffold", user_content)
    cached = _cache_get(ck)
    if cached:
        return ScaffoldResponse(suggestion=cached)

    try:
        resp = openai_client.chat.completions.create(
            model=GPT_MODEL,
            messages=[
                {"role": "system", "content": req.system_prompt},
                {"role": "user", "content": user_content},
            ],
            temperature=0.7, max_tokens=80,
        )
        suggestion = resp.choices[0].message.content.strip()
        _cache_set(ck, suggestion)
        logger.info("/scaffold completed")
        return ScaffoldResponse(suggestion=suggestion)
    except Exception:
        logger.error("/scaffold AI failed, using fallback", exc_info=True)
        return ScaffoldResponse(suggestion=_scaffold_fallback(req.mode))


# ── Fallback Functions (when AI is unavailable) ──────────────────────────────

# Scripted onboarding questions — drives conversation without AI
_SEEKER_CHAT_SCRIPT = [
    "What's been on your mind lately? Take your time — there's no rush here.",
    "That sounds really heavy to carry. Can you tell me a bit more about what's been making it feel so overwhelming?",
    "I hear you. It takes courage to even say that out loud. How long has this been weighing on you?",
    "Thank you for sharing that with me. I'm going to find someone who truly understands what you're going through.",
]

def _seeker_chat_fallback(messages: list) -> dict:
    """Return the next scripted question based on conversation progress."""
    user_count = sum(1 for m in messages if m.get("role") == "user")
    idx = min(user_count, len(_SEEKER_CHAT_SCRIPT) - 1)
    return {"reply": _SEEKER_CHAT_SCRIPT[idx]}


def _extract_helper_fallback(selected_themes: list = None, theme_narratives: dict = None) -> dict:
    """Build a reasonable helper profile with mirrored theme_scores from selected themes."""
    themes = []
    if selected_themes:
        themes = [{"name": t, "intensity": 0.7} for t in selected_themes]
    if not themes:
        themes = [{"name": "Family Problems", "intensity": 0.7}]

    # Build per-theme mirrored scores (defaults or slightly varied based on narrative length)
    theme_scores = {}
    for t in (selected_themes or ["Family Problems"]):
        narrative_len = 0
        if theme_narratives and t in theme_narratives:
            narrative_len = len(theme_narratives[t].strip())
        # Score higher if they wrote more (crude but fair for fallback)
        depth = min(0.9, 0.4 + narrative_len / 500)
        theme_scores[t] = {
            "emotional_depth": round(depth, 2),
            "resilience_demonstrated": round(depth * 0.9, 2),
            "approach_style": "balanced",
            "coping_method": "emotion_focused",
            "communication_tone": "reflective_listening",
            "empathy_signal": round(depth * 0.85, 2),
            "actionability": round(depth * 0.7, 2),
            "self_awareness": round(depth * 0.8, 2),
        }

    return {
        "themes": themes,
        "coping_style": "emotion_focused",
        "communication_style": "reflective_listening",
        "bio": "I've been through something similar and I'm here to listen.",
        "theme_scores": theme_scores,
    }


def _extract_seeker_fallback() -> dict:
    """Return a balanced default seeker profile."""
    return {
        "themes": [{"name": "Family Problems", "intensity": 0.7}],
        "coping_style_preference": {s: 0.5 for s in COPING_STYLES},
        "conversation_preference": {p: 0.5 for p in CONVERSATION_PREFERENCES},
        "energy_level": "low",
        "distress_level": "Medium",
        "urgency": 0.6,
    }


def _scaffold_fallback(mode: str) -> str:
    """Return a pre-written helper suggestion for the given conversation mode."""
    fallbacks = {
        "vent": 'Try: "I\'m here. Take all the time you need."',
        "reflect": 'Try: "It sounds like you\'re feeling really unseen. Is that right?"',
        "clarity": 'Try: "What feels most urgent to you right now?"',
        "growth": 'Try: "What\'s one small thing that might make tomorrow slightly better?"',
    }
    return fallbacks.get(mode, fallbacks["vent"])


# ── Helpers ──────────────────────────────────────────────────────────────────

def _generate_explanation(breakdown: dict, helper: dict) -> str:
    """Generate a human-readable match explanation."""
    parts = []
    if breakdown.get("emotional_similarity", 0) > 0.6:
        parts.append("deeply resonates with your emotional experience")
    if breakdown.get("experience_overlap", 0) > 0.5:
        parts.append("has walked a similar path")
    if breakdown.get("coping_style_match", 0) > 0.5:
        parts.append("supports the way you prefer to cope")
    if breakdown.get("reliability_score", 0) > 0.8:
        parts.append("is a consistent and reliable listener")
    if not parts:
        parts.append("has relevant experience to share")
    return "This person " + ", ".join(parts) + "."


@app.get("/health")
async def health():
    return {
        "status": "ok",
        "helpers_loaded": len(helper_pool),
        "ai_available": openai_client is not None,
        "ai_model": GPT_MODEL,
        "cache_size": len(_response_cache),
        "embedding_mode": "sentence_transformers" if SENTENCE_TRANSFORMERS_AVAILABLE else "synthetic",
    }


@app.get("/helpers")
async def list_helpers():
    """List all helpers in the pool (debug endpoint)."""
    return {
        "count": len(helper_pool),
        "helpers": [
            {
                "user_id": h["user_id"],
                "energy_level": h["energy_level"],
                "reliability_score": round(h["reliability_score"], 2),
                "top_themes": sorted(
                    h["themes_experience"].items(), key=lambda x: x[1], reverse=True
                )[:3],
            }
            for h in helper_pool
        ],
    }
