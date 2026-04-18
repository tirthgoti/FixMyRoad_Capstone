import time
import httpx
import numpy as np
from pathlib import Path
from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import torch

from pipeline import run_full_pipeline
from supabase_client import supabase, upload_image, get_public_url
from cost_estimator import estimate_cost, estimate_materials
from pdf_generator import generate_monthly_report

app = FastAPI(title="FixMyRoad AI Worker", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

class AnalyzeRequest(BaseModel):
    report_id: str
    image_url: str

class AnalyzeResponse(BaseModel):
    report_id:           str
    severity:            str | None
    relative_depth:      float | None
    max_depth:           float | None
    pothole_area_px:     float | None
    confidence:          float | None
    repair_cost_min:     float | None
    repair_cost_max:     float | None
    asphalt_kg:          float | None
    labour_hours:        float | None
    material_cost_est:   float | None
    depth_map_url:       str | None
    heatmap_url:         str | None
    before_after_url:    str | None
    processing_time_s:   float
    relative_depth_mm:   float | None
    max_depth_mm:        float | None
    depth_mm_per_unit:   float | None

class PdfRequest(BaseModel):
    year:  int
    month: int

@app.get("/health")
def health():
    return {
        "status": "ok",
        "gpu": torch.cuda.is_available(),
        "gpu_name": torch.cuda.get_device_name(0) if torch.cuda.is_available() else None,
    }

@app.post("/analyze", response_model=AnalyzeResponse)
async def analyze(req: AnalyzeRequest):
    start = time.time()

    print(f"[AI] Starting analysis for report: {req.report_id}")
    print(f"[AI] Image URL: {req.image_url}")

    # 1. Download image
    async with httpx.AsyncClient() as client:
        response = await client.get(req.image_url, timeout=30)
        if response.status_code != 200:
            raise HTTPException(status_code=400,
                detail=f"Could not download image. Status: {response.status_code}")
        image_bytes = response.content
    print(f"[AI] Image downloaded: {len(image_bytes)} bytes")

    # 2. Run AI pipeline
    try:
        results = run_full_pipeline(image_bytes, req.report_id)
        print(f"[AI] Pipeline complete: severity={results.get('severity')}, depth={results.get('relative_depth')}")
    except Exception as e:
        print(f"[AI] Pipeline error: {e}")
        raise HTTPException(status_code=500, detail=f"AI pipeline failed: {e}")

    processing_time = time.time() - start

    # 3. Estimate cost and materials
    severity   = results.get("severity")
    area_px    = results.get("pothole_area_px")
    rel_depth  = results.get("relative_depth")
    cost_range = estimate_cost(severity)
    materials  = estimate_materials(severity, area_px, rel_depth)

    print(f"[AI] Cost estimate: {cost_range}")
    print(f"[AI] Materials: {materials}")

    # 4. Upload output images
    depth_map_url    = None
    heatmap_url      = None
    before_after_url = None

    if results.get("depth_map_bytes"):
        path = f"{req.report_id}_depth.png"
        upload_image(path, results["depth_map_bytes"])
        depth_map_url = get_public_url("depth-maps", path)

    if results.get("heatmap_bytes"):
        path = f"{req.report_id}_heatmap.png"
        upload_image(path, results["heatmap_bytes"])
        heatmap_url = get_public_url("depth-maps", path)

    if results.get("before_after_bytes"):
        path = f"{req.report_id}_before_after.png"
        upload_image(path, results["before_after_bytes"])
        before_after_url = get_public_url("depth-maps", path)

    # 5. Write ai_results — use INSERT with ON CONFLICT DO UPDATE
    ai_row = {
        "report_id":         req.report_id,
        "relative_depth":    results.get("relative_depth"),
        "max_depth":         results.get("max_depth"),
        "severity":          severity,
        "pothole_area_px":   area_px,
        "confidence":        results.get("confidence"),
        "repair_cost_min":   cost_range["min"],
        "repair_cost_max":   cost_range["max"],
        "asphalt_kg":        materials["asphalt_kg"],
        "labour_hours":      materials["labour_hours"],
        "material_cost_est": materials["material_cost_est"],
        "depth_map_url":     depth_map_url,
        "heatmap_url":       heatmap_url,
        "before_after_url":  before_after_url,
        "model_encoder":     "vitl",
        "processing_time_s": processing_time,
        "relative_depth_mm": results.get("relative_depth_mm"),
        "max_depth_mm":      results.get("max_depth_mm"),
        "depth_mm_per_unit": results.get("depth_mm_per_unit"),
    }

    try:
        # Try insert first
        supabase.table("ai_results").insert(ai_row).execute()
        print("[AI] ai_results inserted")
    except Exception:
        # If already exists, update instead
        try:
            supabase.table("ai_results").update(ai_row).eq(
                "report_id", req.report_id).execute()
            print("[AI] ai_results updated")
        except Exception as e2:
            print(f"[AI] ai_results write error: {e2}")

    # 6. Update report status — bypass the trigger by using service role
    # The trigger fails because auth.uid() is null for service role
    # So we directly insert into status_history with the system user
    try:
        # Get the citizen_id for this report to use as changed_by
        report_data = supabase.table("reports").select(
            "citizen_id").eq("id", req.report_id).single().execute()
        citizen_id = report_data.data.get("citizen_id")

        # Update status
        supabase.table("reports").update(
            {"status": "under_review",
             "updated_at": "now()"}
        ).eq("id", req.report_id).execute()
        print("[AI] Report status updated to under_review")

        # Manually insert status history (bypass trigger)
        supabase.table("status_history").insert({
            "report_id":  req.report_id,
            "changed_by": citizen_id,  # use citizen as placeholder
            "old_status": "submitted",
            "new_status": "under_review",
            "note":       "Auto-updated by AI analysis",
        }).execute()
        print("[AI] Status history inserted")

    except Exception as e:
        print(f"[AI] Status update error (non-critical): {e}")

    print(f"[AI] Done in {processing_time:.1f}s")
    return AnalyzeResponse(**{**ai_row, "processing_time_s": processing_time})

@app.post("/generate-pdf")
async def generate_pdf(req: PdfRequest):
    try:
        pdf_path = generate_monthly_report(req.year, req.month)
        bucket_path = f"reports/{req.year}_{req.month:02d}_council_report.pdf"
        with open(pdf_path, "rb") as f:
            supabase.storage.from_("depth-maps").upload(
                bucket_path, f.read(),
                file_options={"content-type": "application/pdf"}
            )
        url = get_public_url("depth-maps", bucket_path)
        return {"url": url}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/results/{report_id}")
def get_results(report_id: str):
    data = supabase.table("ai_results") \
        .select("*") \
        .eq("report_id", report_id) \
        .single() \
        .execute()
    if not data.data:
        raise HTTPException(status_code=404, detail="Results not found")
    return data.data