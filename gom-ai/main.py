import asyncio
import json
import logging
import os
import re
import sys

import openai
from dotenv import load_dotenv
from fastapi import FastAPI, File, HTTPException, UploadFile
from pathlib import Path

try:
    from google import genai as google_genai
    from google.genai import types as genai_types
    _GENAI_AVAILABLE = True
except ImportError:
    _GENAI_AVAILABLE = False

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    handlers=[logging.StreamHandler(sys.stdout)],
)
logger = logging.getLogger("gom-ai-tadp")

load_dotenv(dotenv_path=Path(__file__).resolve().parent / ".env", override=True)

GOOGLE_API_KEY = os.getenv("GOOGLE_API_KEY", "")
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "")
XAI_API_KEY    = os.getenv("XAI_API_KEY", "")

logger.info(
    "API keys  GOOGLE:%s  OPENAI:%s  XAI:%s  genai_sdk:%s",
    "OK" if GOOGLE_API_KEY else "MISSING",
    "OK" if OPENAI_API_KEY else "MISSING",
    "OK" if XAI_API_KEY    else "MISSING",
    "OK" if _GENAI_AVAILABLE else "NOT INSTALLED",
)

app = FastAPI(title="Gom AI TADP")

UPLOAD_FOLDER = "uploads"
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

# Recognized pottery origin labels accepted by the classifier
VALID_LABELS = [
    "Bat Trang", "Bau Truc", "Bien Hoa", "Chu Dau",
    "Dong Trieu", "Lai Thieu", "Phu Lang", "Thanh Ha", "Tho Ha",
]

# Per-agent timeout (seconds) and total hard cap for the full pipeline
AGENT_TIMEOUT_SEC = 50
TOTAL_TIMEOUT_SEC = 210

GEMINI_MODEL = "gemini-2.5-flash"
OPENAI_MODEL = "gpt-4o-mini"
GROK_MODEL   = "grok-4-latest"
OPENAI_BASE  = "https://api.openai.com/v1"
XAI_BASE     = "https://api.x.ai/v1"

PROMPT_AGENT1_OBSERVER = """\
Bạn là chuyên gia phân tích vật lý gốm sứ cổ Việt Nam với 30 năm kinh nghiệm.

Nhiệm vụ: Quan sát và mô tả THUẦN TÚY vật lý ảnh được tải lên.

QUY TẮC BẮT BUỘC:
- TUYỆT ĐỐI KHÔNG đoán tên làng gốm, vùng sản xuất, hoặc niên đại.
- Chỉ mô tả những gì bạn NHÌN THẤY: màu sắc men, họa tiết trang trí, kỹ thuật tạo hình, độ dày thành, loại xương gốm, vết nung, màu đế.
- Nếu ảnh KHÔNG phải đồ gốm: chỉ trả về đúng một dòng JSON: {"is_pottery": false}
- Nếu là gốm: trả về văn xuôi mô tả chi tiết (3–5 câu, không dùng markdown, không dùng dấu gạch đầu dòng). Cuối cùng mới trả về: {"is_pottery": true}

Trả lời bằng tiếng Việt có đầy đủ dấu.\
"""

PROMPT_AGENT2_HISTORIAN = """\
Bạn là sử gia chuyên về gốm sứ cổ Việt Nam.

Bạn vừa nhận được bản mô tả vật lý của một hiện vật gốm từ chuyên gia quan sát:

--- MÔ TẢ ---
{observation}
---

Nhiệm vụ: Dựa HOÀN TOÀN vào bản mô tả trên, hãy đưa ra ĐÚNG HAI giả thuyết về làng gốm và niên đại.

Mỗi giả thuyết phải:
1. Đặt tên: "Giả thuyết A" hoặc "Giả thuyết B"
2. Nêu tên làng gốm trong danh sách: Bat Trang, Bau Truc, Bien Hoa, Chu Dau, Dong Trieu, Lai Thieu, Phu Lang, Thanh Ha, Tho Ha
3. Nêu lý do dựa trên đặc điểm vật lý đã mô tả
4. Ước tính niên đại (thế kỷ)

Kết thúc bằng một dòng JSON:
{{"hypothesis_a": "<tên làng A>", "hypothesis_b": "<tên làng B>", "preferred": "<A hoặc B>"}}

Không dùng markdown. Trả lời bằng tiếng Việt có đầy đủ dấu.\
"""

PROMPT_AGENT3_SKEPTIC = """\
Bạn là nhà nghiên cứu hoài nghi, chuyên tìm điểm yếu trong luận điểm của các sử gia.

Bản mô tả vật lý gốm:
--- MÔ TẢ ---
{observation}
---

Hai giả thuyết của sử gia:
--- GIẢ THUYẾT ---
{hypotheses}
---

Nhiệm vụ: Hãy phân tích nghiêm khắc:
1. Chỉ ra ÍT NHẤT 2 điểm yếu hoặc mâu thuẫn trong từng giả thuyết.
2. Đề xuất liệu có nguy cơ đây là gốm GIẢ CỔ (forgery) không và tại sao.
3. Sau khi phản biện, cho biết bạn nghiêng về giả thuyết nào hơn (A hay B) và tại sao.
4. Đánh giá mức độ rủi ro làm giả: một trong ["rất thấp", "thấp", "trung bình", "cao", "rất cao"]

Kết thúc bằng một dòng JSON:
{{"leans_towards": "<tên làng>", "forgery_risk": "<mức độ rủi ro>"}}

Không dùng markdown. Trả lời bằng tiếng Việt có đầy đủ dấu.\
"""

PROMPT_META_COUNCIL = """\
Bạn là Hội đồng chuyên gia gốm sứ Việt Nam. Sau đây là biên bản tranh luận đầy đủ:

=== AGENT 1 – QUAN SÁT VIÊN (Gemini 2.5 Flash) ===
{agent1_output}

=== AGENT 2 – SỬ GIA (GPT-4o mini) ===
{agent2_output}

=== AGENT 3 – NGƯỜI HOÀI NGHI (Grok 4 Latest) ===
{agent3_output}

Nhiệm vụ: Tổng hợp toàn bộ tranh luận và đưa ra PHÁN QUYẾT CUỐI CÙNG:
1. Viết 2–3 câu tóm tắt bằng chứng và lý luận chính (văn xuôi, không markdown).
2. Xác định ĐÚNG MỘT làng gốm từ danh sách: Bat Trang, Bau Truc, Bien Hoa, Chu Dau, Dong Trieu, Lai Thieu, Phu Lang, Thanh Ha, Tho Ha.
3. Cuối cùng, trả về ĐÚNG MỘT dòng JSON:
{{"predicted_label": "<tên làng>", "confidence": <0.0–1.0>, "forgery_risk": "<rất thấp|thấp|trung bình|cao|rất cao>"}}

Không dùng markdown. Trả lời bằng tiếng Việt có đầy đủ dấu.\
"""


def _strip_markdown(text: str) -> str:
    text = re.sub(r'^#{1,6}\s+', '', text, flags=re.MULTILINE)
    text = re.sub(r'\*{2}(.+?)\*{2}', r'\1', text, flags=re.DOTALL)
    text = re.sub(r'_{2}(.+?)_{2}',   r'\1', text, flags=re.DOTALL)
    text = re.sub(r'\*(.+?)\*',       r'\1', text, flags=re.DOTALL)
    text = re.sub(r'_(.+?)_',         r'\1', text, flags=re.DOTALL)
    text = re.sub(r'^\s*[-*]\s+',     '', text, flags=re.MULTILINE)
    text = re.sub(r'^\s*\d+\.\s+',    '', text, flags=re.MULTILINE)
    text = re.sub(r'\n{3,}', '\n\n', text)
    return text.strip()


# Extracts the last JSON object from a model response, stripping code fences
def _extract_json(text: str) -> dict:
    text = text.strip().removeprefix("```json").removeprefix("```").removesuffix("```").strip()
    matches = list(re.finditer(r'\{[^{}]*\}', text, re.DOTALL))
    if matches:
        try:
            return json.loads(matches[-1].group())
        except json.JSONDecodeError:
            pass
    return {}


# Returns the prose section before the final JSON block in a model response
def _text_before_json(text: str) -> str:
    match = re.search(r'\{[^{}]*\}(?!.*\{)', text, re.DOTALL)
    if match:
        return _strip_markdown(text[:match.start()].strip())
    return _strip_markdown(text)


def _closest_label(raw: str) -> str:
    raw_lower = raw.lower()
    for label in VALID_LABELS:
        if label.lower() in raw_lower or raw_lower in label.lower():
            return label
    return max(VALID_LABELS, key=lambda lbl: sum(c in raw_lower for c in lbl.lower()))



async def _agent1_observer(image_bytes: bytes) -> dict:
    if not GOOGLE_API_KEY:
        raise HTTPException(500, detail="GOOGLE_API_KEY chưa được thiết lập trong .env")
    if not _GENAI_AVAILABLE:
        raise HTTPException(500, detail="Thư viện google-genai chưa được cài đặt.")
    logger.info("[Agent1] Calling %s", GEMINI_MODEL)
    try:
        client = google_genai.Client(api_key=GOOGLE_API_KEY)
        response = await asyncio.wait_for(
            client.aio.models.generate_content(
                model=GEMINI_MODEL,
                contents=[
                    genai_types.Part.from_bytes(data=image_bytes, mime_type="image/jpeg"),
                    genai_types.Part.from_text(text=PROMPT_AGENT1_OBSERVER),
                ],
            ),
            timeout=AGENT_TIMEOUT_SEC,
        )
        raw = response.text or ""
        logger.info("[Agent1] Response: %s", raw[:250])
        data = _extract_json(raw)
        if data.get("is_pottery") is False:
            return {"is_pottery": False, "observation": ""}
        observation = _text_before_json(raw)
        return {"is_pottery": True, "observation": observation, "raw": raw}
    except asyncio.TimeoutError:
        raise HTTPException(504, detail="Agent 1 (Quan sát viên) hết thời gian chờ.")
    except HTTPException:
        raise
    except Exception as exc:
        logger.error("[Agent1] Error: %s", exc)
        raise HTTPException(502, detail=f"Lỗi Agent 1 (Gemini Vision): {exc}")



async def _agent2_historian(observation: str) -> dict:
    if not OPENAI_API_KEY:
        raise HTTPException(500, detail="OPENAI_API_KEY chưa được thiết lập trong .env")
    logger.info("[Agent2] Calling %s", OPENAI_MODEL)
    prompt = PROMPT_AGENT2_HISTORIAN.format(observation=observation)
    try:
        client = openai.AsyncOpenAI(api_key=OPENAI_API_KEY, base_url=OPENAI_BASE)
        resp = await asyncio.wait_for(
            client.chat.completions.create(
                model=OPENAI_MODEL,
                messages=[{"role": "user", "content": prompt}],
                max_tokens=800,
                temperature=0.4,
            ),
            timeout=AGENT_TIMEOUT_SEC,
        )
        raw = resp.choices[0].message.content or ""
        logger.info("[Agent2] Response: %s", raw[:250])
        data = _extract_json(raw)
        hypotheses_text = _text_before_json(raw)
        return {
            "hypotheses_text": hypotheses_text,
            "hypothesis_a":    data.get("hypothesis_a", ""),
            "hypothesis_b":    data.get("hypothesis_b", ""),
            "preferred":       data.get("preferred", "A"),
            "raw":             raw,
        }
    except asyncio.TimeoutError:
        raise HTTPException(504, detail="Agent 2 (Sử gia) hết thời gian chờ.")
    except HTTPException:
        raise
    except Exception as exc:
        logger.error("[Agent2] Error: %s", exc)
        raise HTTPException(502, detail=f"Lỗi Agent 2 (OpenAI GPT-4o mini): {exc}")



async def _agent3_skeptic(observation: str, hypotheses_text: str) -> dict:
    if not XAI_API_KEY:
        raise HTTPException(500, detail="XAI_API_KEY chưa được thiết lập trong .env")
    logger.info("[Agent3] Calling %s", GROK_MODEL)
    prompt = PROMPT_AGENT3_SKEPTIC.format(
        observation=observation, hypotheses=hypotheses_text
    )
    try:
        client = openai.AsyncOpenAI(api_key=XAI_API_KEY, base_url=XAI_BASE)
        resp = await asyncio.wait_for(
            client.chat.completions.create(
                model=GROK_MODEL,
                messages=[
                    {
                        "role": "system",
                        "content": (
                            "Bạn là nhà nghiên cứu hoài nghi, sắc bén và thẳng thắn. "
                            "Trả lời bằng tiếng Việt có đầy đủ dấu."
                        ),
                    },
                    {"role": "user", "content": prompt},
                ],
                max_tokens=800,
                temperature=0.5,
            ),
            timeout=AGENT_TIMEOUT_SEC,
        )
        raw = resp.choices[0].message.content or ""
        logger.info("[Agent3] Response: %s", raw[:250])
        data = _extract_json(raw)
        skeptic_text = _text_before_json(raw)
        return {
            "skeptic_text":  skeptic_text,
            "leans_towards": data.get("leans_towards", ""),
            "forgery_risk":  data.get("forgery_risk", "thấp"),
            "raw":           raw,
        }
    except asyncio.TimeoutError:
        raise HTTPException(504, detail="Agent 3 (Người hoài nghi) hết thời gian chờ.")
    except HTTPException:
        raise
    except Exception as exc:
        logger.error("[Agent3] Error: %s", exc)
        raise HTTPException(502, detail=f"Lỗi Agent 3 (Grok 4 Latest – xAI): {exc}")



async def _meta_council(
    agent1_output: str,
    agent2_output: str,
    agent3_output: str,
) -> dict:
    if not GOOGLE_API_KEY:
        raise HTTPException(500, detail="GOOGLE_API_KEY chưa được thiết lập trong .env")
    if not _GENAI_AVAILABLE:
        raise HTTPException(500, detail="Thư viện google-genai chưa được cài đặt.")
    logger.info("[Meta] Calling %s", GEMINI_MODEL)
    prompt = PROMPT_META_COUNCIL.format(
        agent1_output=agent1_output,
        agent2_output=agent2_output,
        agent3_output=agent3_output,
    )
    try:
        client = google_genai.Client(api_key=GOOGLE_API_KEY)
        response = await asyncio.wait_for(
            client.aio.models.generate_content(
                model=GEMINI_MODEL,
                contents=[genai_types.Part.from_text(text=prompt)],
            ),
            timeout=AGENT_TIMEOUT_SEC,
        )
        raw = response.text or ""
        logger.info("[Meta] Verdict: %s", raw[:300])
        data      = _extract_json(raw)
        rationale = _text_before_json(raw)

        raw_label = str(data.get("predicted_label", ""))
        if raw_label not in VALID_LABELS:
            raw_label = _closest_label(raw_label)

        try:
            confidence = max(0.0, min(1.0, float(data.get("confidence", 0.5))))
        except (TypeError, ValueError):
            confidence = 0.5

        return {
            "predicted_label": raw_label,
            "confidence":      confidence,
            "rationale":       rationale,
            "forgery_risk":    data.get("forgery_risk", "thấp"),
        }
    except asyncio.TimeoutError:
        raise HTTPException(504, detail="Meta-Agent (Hội đồng) hết thời gian chờ.")
    except HTTPException:
        raise
    except Exception as exc:
        logger.error("[Meta] Error: %s", exc)
        raise HTTPException(502, detail=f"Lỗi Meta-Agent (Gemini): {exc}")



# Runs the four agents sequentially; each agent receives the prior agent's output
async def _run_tadp_pipeline(image_bytes: bytes) -> dict:
    debate_trail: list[dict] = []

    a1 = await _agent1_observer(image_bytes)

    # Short-circuit: non-pottery images skip the remaining three agents
    if not a1.get("is_pottery", True):
        return {
            "predicted_label": "not_pottery",
            "confidence":      0.0,
            "raw_text":        "Ảnh này không phải gốm Việt Nam.",
            "evidence":        "",
            "rationale":       "",
            "forgery_risk":    "không áp dụng",
            "debate_trail": [{
                "step":    1,
                "agent":   "Quan sát viên",
                "model":   GEMINI_MODEL,
                "role":    "Phân tích hình ảnh",
                "content": "Ảnh không chứa đồ gốm. Pipeline dừng tại đây.",
            }],
        }

    observation = a1["observation"]
    debate_trail.append({
        "step": 1, "agent": "Quan sát viên",
        "model": GEMINI_MODEL, "role": "Mô tả vật lý",
        "content": observation,
    })
    logger.info("[TADP] Step 1 done, observation: %d chars", len(observation))

    a2 = await _agent2_historian(observation)
    debate_trail.append({
        "step": 2, "agent": "Sử gia",
        "model": OPENAI_MODEL, "role": "Phân tích lịch sử & Giả thuyết",
        "content": a2["hypotheses_text"],
    })
    logger.info("[TADP] Step 2 done, A=%s B=%s", a2["hypothesis_a"], a2["hypothesis_b"])

    a3 = await _agent3_skeptic(observation, a2["hypotheses_text"])
    debate_trail.append({
        "step": 3, "agent": "Người hoài nghi",
        "model": GROK_MODEL, "role": "Phản biện & Đánh giá rủi ro",
        "content": a3["skeptic_text"],
    })
    logger.info("[TADP] Step 3 done, leans=%s forgery=%s", a3["leans_towards"], a3["forgery_risk"])

    meta = await _meta_council(
        agent1_output=a1["raw"],
        agent2_output=a2["raw"],
        agent3_output=a3["raw"],
    )
    debate_trail.append({
        "step": 4, "agent": "Hội đồng",
        "model": GEMINI_MODEL, "role": "Phán quyết cuối cùng",
        "content": meta["rationale"],
    })
    logger.info(
        "[TADP] Step 4 done, label=%s confidence=%.1f%% forgery=%s",
        meta["predicted_label"], meta["confidence"] * 100, meta["forgery_risk"],
    )

    return {
        "predicted_label": meta["predicted_label"],
        "confidence":      meta["confidence"],
        "raw_text":        meta["rationale"],
        "evidence":        observation,
        "rationale":       a2["hypotheses_text"],
        "forgery_risk":    meta["forgery_risk"],
        "debate_trail":    debate_trail,
    }



@app.post("/predict")
async def predict(file: UploadFile = File(...)):
    image_bytes = await file.read()
    logger.info(
        "POST /predict  pipeline=TADP  file=%s  size=%d bytes",
        file.filename, len(image_bytes),
    )
    safe_name = Path(file.filename).name if file.filename else "upload.jpg"
    with open(os.path.join(UPLOAD_FOLDER, safe_name), "wb") as f:
        f.write(image_bytes)

    try:
        result = await asyncio.wait_for(
            _run_tadp_pipeline(image_bytes),
            timeout=TOTAL_TIMEOUT_SEC,
        )
    except asyncio.TimeoutError:
        raise HTTPException(504, detail="Pipeline TADP hết thời gian chờ tổng thể (210 giây).")
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("Lỗi không xác định trong TADP pipeline:")
        raise HTTPException(502, detail=f"Lỗi hệ thống AI: {exc}")

    logger.info(
        "Final result: label=%s  confidence=%.2f  forgery=%s",
        result["predicted_label"], result["confidence"], result.get("forgery_risk"),
    )
    return result
