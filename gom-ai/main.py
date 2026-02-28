import base64
import json
import logging
import os
import re
import sys

import openai
from dotenv import load_dotenv
from fastapi import FastAPI, File, HTTPException, Query, UploadFile
from pathlib import Path

# google-genai (Gemini)
try:
    from google import genai as google_genai
    from google.genai import types as genai_types
    _GENAI_AVAILABLE = True
except ImportError:
    _GENAI_AVAILABLE = False

# Logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    handlers=[logging.StreamHandler(sys.stdout)],
)
logger = logging.getLogger("gom-ai")

# Environment
load_dotenv(dotenv_path=Path(__file__).resolve().parent / ".env", override=True)

GROQ_API_KEY   = os.getenv("GROQ_API_KEY")
GOOGLE_API_KEY = os.getenv("GOOGLE_API_KEY")

logger.info(
    "API keys -- GROQ:%s  GOOGLE:%s  genai_sdk:%s",
    "OK" if GROQ_API_KEY   else "MISSING",
    "OK" if GOOGLE_API_KEY else "MISSING",
    "OK" if _GENAI_AVAILABLE else "NOT INSTALLED",
)

# App
app = FastAPI()

UPLOAD_FOLDER = "uploads"
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

VALID_LABELS = [
    "Bat Trang", "Bau Truc", "Bien Hoa", "Chu Dau",
    "Dong Trieu", "Lai Thieu", "Phu Lang", "Thanh Ha", "Tho Ha",
]

# -- Model registry -----------------------------------------------------------
# provider: "google" | "groq"
# model_id: actual model name for the provider's API
MODELS: dict[str, dict] = {
    # Google Gemini 2.5 Flash — best free vision, 1M context (default)
    "gemini":      {"provider": "google", "model_id": "gemini-2.5-flash"},
    # Google Gemini 3 Flash Preview — newest, frontier intelligence, free tier
    "gemini3":     {"provider": "google", "model_id": "gemini-3-flash-preview"},
    # Google Gemini 2.5 Flash-Lite — fastest + most cost-efficient, free tier
    "gemini_lite": {"provider": "google", "model_id": "gemini-2.5-flash-lite"},
    # Meta Llama 4 Scout via Groq — only vision model on Groq, 20MB image limit
    "llama4":      {"provider": "groq",   "model_id": "meta-llama/llama-4-scout-17b-16e-instruct"},
}

DEFAULT_MODEL = "gemini"

# Prompts (UTF-8 Vietnamese with full diacritics)
PROMPT_VISION = (
    "Bạn là chuyên gia gốm sứ truyền thống Việt Nam.\n\n"
    "Hãy phân tích ảnh gốm được tải lên.\n\n"
    "— Nếu ảnh KHÔNG phải đồ gốm hoặc gốm sứ: chỉ trả về đúng một dòng JSON sau, "
    "không thêm bất cứ nội dung nào khác:\n"
    '{"predicted_label": "not_pottery", "confidence": 0.0}\n\n'
    "— Nếu là gốm sứ, hãy làm theo đúng thứ tự:\n"
    "1. Viết 2–3 câu mô tả đặc điểm nổi bật: màu sắc men, họa tiết trang trí, "
    "kỹ thuật nung, phong cách nghệ thuật. "
    "TUYỆT ĐỐI không dùng dấu **, không viết tiêu đề ##, không dùng - gạch đầu dòng, "
    "không dùng markdown. Viết thành văn xuôi liền mạch.\n"
    "2. Xác định đúng một làng gốm trong danh sách sau: "
    "Bat Trang, Bau Truc, Bien Hoa, Chu Dau, Dong Trieu, Lai Thieu, Phu Lang, Thanh Ha, Tho Ha.\n"
    "3. Cuối cùng, viết đúng một dòng JSON (không markdown, không giải thích thêm):\n"
    '{"predicted_label": "<tên làng>", "confidence": <số từ 0.0 đến 1.0>}\n\n'
    "Trả lời bằng tiếng Việt có đầy đủ dấu."
)

# Markdown stripper
def _strip_markdown(text: str) -> str:
    # Remove ### headings (keep heading text)
    text = re.sub(r'^#{1,6}\s+', '', text, flags=re.MULTILINE)
    # Remove **bold** and __bold__
    text = re.sub(r'\*{2}(.+?)\*{2}', r'\1', text, flags=re.DOTALL)
    text = re.sub(r'_{2}(.+?)_{2}',   r'\1', text, flags=re.DOTALL)
    # Remove *italic* and _italic_
    text = re.sub(r'\*(.+?)\*', r'\1', text, flags=re.DOTALL)
    text = re.sub(r'_(.+?)_',   r'\1', text, flags=re.DOTALL)
    # Remove leading list markers: "- " or "* " or "1. "
    text = re.sub(r'^\s*[-*]\s+',     '', text, flags=re.MULTILINE)
    text = re.sub(r'^\s*\d+\.\s+',    '', text, flags=re.MULTILINE)
    # Collapse 3+ blank lines → 2
    text = re.sub(r'\n{3,}', '\n\n', text)
    return text.strip()

# Result extraction
def _closest_label(raw: str) -> str:
    raw_lower = raw.lower()
    for label in VALID_LABELS:
        if label.lower() in raw_lower or raw_lower in label.lower():
            return label
    return max(VALID_LABELS, key=lambda lbl: sum(c in raw_lower for c in lbl.lower()))

def extract_result(text: str) -> dict:
    text = text.strip().removeprefix("```json").removeprefix("```").removesuffix("```").strip()

    match = re.search(r'\{[^{}]*"predicted_label"[^{}]*\}', text, re.DOTALL)
    data: dict | None = None
    raw_text = ""

    if match:
        raw_text = _strip_markdown(text[: match.start()].strip())
        try:
            data = json.loads(match.group())
        except json.JSONDecodeError:
            logger.warning("JSON parse error on: %s", match.group()[:80])

    if data is None:
        logger.warning("No valid JSON in response, raw: %s", text[:120])
        raw_text = _strip_markdown(text)
        not_pottery_hints = ("not_pottery", "không phải gốm", "khong phai gom", "not pottery")
        if any(h in text.lower() for h in not_pottery_hints):
            return {"predicted_label": "not_pottery", "confidence": 0.0, "raw_text": raw_text}
        data = {"predicted_label": "Bat Trang", "confidence": 0.5}

    raw_label = str(data.get("predicted_label", ""))

    if raw_label == "not_pottery":
        return {
            "predicted_label": "not_pottery",
            "confidence": 0.0,
            "raw_text": raw_text or "Ảnh này không phải gốm Việt Nam.",
        }

    if raw_label not in VALID_LABELS:
        corrected = _closest_label(raw_label)
        logger.warning("Label '%s' not in list -> corrected to '%s'", raw_label, corrected)
        data["predicted_label"] = corrected

    try:
        data["confidence"] = max(0.0, min(1.0, float(data.get("confidence", 0.5))))
    except (TypeError, ValueError):
        data["confidence"] = 0.5

    data["raw_text"] = raw_text or data["predicted_label"]
    return data

# Gemini helper (Google AI)
async def _call_gemini(model_key: str, image_bytes: bytes) -> dict:
    if not GOOGLE_API_KEY:
        raise HTTPException(status_code=500, detail="GOOGLE_API_KEY is not set in .env")
    if not _GENAI_AVAILABLE:
        raise HTTPException(status_code=500, detail="google-genai SDK not installed. Run: pip install google-genai")

    model_id = MODELS[model_key]["model_id"]
    logger.info("[Gemini/%s] Calling %s ...", model_key, model_id)

    try:
        client = google_genai.Client(api_key=GOOGLE_API_KEY)
        response = await client.aio.models.generate_content(
            model=model_id,
            contents=[
                genai_types.Part.from_bytes(data=image_bytes, mime_type="image/jpeg"),
                genai_types.Part.from_text(text=PROMPT_VISION),
            ],
        )
        raw = response.text or ""
        logger.info("[Gemini/%s] Response: %s", model_key, raw[:300])
        return extract_result(raw)
    except HTTPException:
        raise
    except Exception as exc:
        logger.error("[Gemini/%s] Error: %s", model_key, exc)
        raise HTTPException(status_code=502, detail=f"Gemini error ({model_id}): {exc}")

# Groq helper
async def _call_groq(model_key: str, image_bytes: bytes) -> dict:
    if not GROQ_API_KEY:
        raise HTTPException(status_code=500, detail="GROQ_API_KEY is not set in .env")

    model_id = MODELS[model_key]["model_id"]
    logger.info("[Groq/%s] Calling %s ...", model_key, model_id)

    client = openai.OpenAI(api_key=GROQ_API_KEY, base_url="https://api.groq.com/openai/v1")
    b64 = base64.b64encode(image_bytes).decode()

    def _vision_messages() -> list:
        return [{"role": "user", "content": [
            {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{b64}"}},
            {"type": "text", "text": PROMPT_VISION},
        ]}]

    try:
        resp = client.chat.completions.create(
            model=model_id, messages=_vision_messages(), max_tokens=512
        )
        raw = resp.choices[0].message.content or ""
        logger.info("[Groq/%s] Response: %s", model_key, raw[:300])
        return extract_result(raw)
    except HTTPException:
        raise
    except Exception as exc:
        logger.error("[Groq/%s] Error: %s", model_key, exc)
        raise HTTPException(status_code=502, detail=f"Groq error: {exc}")


# -- Endpoint -----------------------------------------------------------------
@app.post("/predict")
async def predict(
    file: UploadFile = File(...),
    model: str = Query(
        default=DEFAULT_MODEL,
        description="Model key: gemini | gemini3 | gemini_lite | llama4",
    ),
):
    image_bytes = await file.read()
    logger.info(
        "POST /predict  model=%s  file=%s  size=%d bytes",
        model, file.filename, len(image_bytes),
    )

    safe_name = Path(file.filename).name if file.filename else "upload.jpg"
    with open(os.path.join(UPLOAD_FOLDER, safe_name), "wb") as f:
        f.write(image_bytes)

    model_key = model.lower().strip()
    if model_key not in MODELS:
        logger.warning("Unknown model key '%s', falling back to '%s'", model, DEFAULT_MODEL)
        model_key = DEFAULT_MODEL

    provider = MODELS[model_key]["provider"]

    try:
        if provider == "google":
            result = await _call_gemini(model_key, image_bytes)
        else:
            result = await _call_groq(model_key, image_bytes)
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("Unexpected prediction error:")
        raise HTTPException(status_code=502, detail=f"AI model error: {exc}")

    logger.info("Result: %s", result)
    return result
