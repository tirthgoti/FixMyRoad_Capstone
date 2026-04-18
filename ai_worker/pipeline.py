import io
import cv2
import torch
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib import cm
from pathlib import Path

_depth_model = None
_yolo_model  = None

def _get_depth_model():
    global _depth_model
    if _depth_model is None:
        from depth_anything_v2.dpt import DepthAnythingV2
        cfg = {"encoder":"vitl","features":256,"out_channels":[256,512,1024,1024]}
        model = DepthAnythingV2(**cfg)
        ckpt  = Path("checkpoints/depth_anything_v2_vitl.pth")
        model.load_state_dict(torch.load(ckpt, map_location="cpu"))
        device = "cuda" if torch.cuda.is_available() else "cpu"
        _depth_model = model.to(device).eval()
        print(f"[Pipeline] Depth model loaded on {device}")
    return _depth_model

def _get_yolo_model():
    global _yolo_model
    if _yolo_model is None:
        from ultralytics import YOLO
        _yolo_model = YOLO("checkpoints/pothole_seg.pt")
        print("[Pipeline] YOLO model loaded")
    return _yolo_model


def _infer_depth(model, image_bgr: np.ndarray) -> np.ndarray:
    image_rgb = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2RGB)
    with torch.no_grad():
        depth = model.infer_image(image_rgb)
    d_min, d_max = depth.min(), depth.max()
    normalized = ((depth - d_min) / (d_max - d_min + 1e-8)).astype(np.float32)
    print(f"[Pipeline] Depth map: min={d_min:.4f} max={d_max:.4f}")
    return normalized


def _run_yolo(model, image_bgr: np.ndarray, conf: float = 0.15):
    """Lower confidence threshold to 0.15 to catch more potholes."""
    h, w = image_bgr.shape[:2]
    results = model(image_bgr, conf=conf, verbose=False)[0]
    detections = []

    if results.masks is None:
        print("[Pipeline] YOLO: no masks returned")
        return detections

    print(f"[Pipeline] YOLO: found {len(results.masks.data)} detection(s)")
    for i in range(len(results.masks.data)):
        raw  = results.masks.data[i].cpu().numpy()
        mask = cv2.resize(raw, (w, h), interpolation=cv2.INTER_NEAREST)
        mask = (mask > 0.5).astype(np.uint8) * 255
        box  = results.boxes[i]
        x1, y1, x2, y2 = map(int, box.xyxy[0].cpu().numpy())
        conf_score = float(box.conf[0].cpu().numpy())
        area = int(np.sum(mask == 255))
        print(f"[Pipeline]   Detection {i}: conf={conf_score:.3f} area={area}px")
        contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        detections.append({
            "mask": mask, "bbox": (x1,y1,x2,y2),
            "conf": conf_score, "contours": contours,
            "source": "yolo"
        })
    return detections


def _heuristic_detect(depth_map: np.ndarray, image_bgr: np.ndarray):
    """
    Improved heuristic: combines depth + edge analysis.
    Returns None if the image doesn't look like it has a pothole.
    """
    h, w = depth_map.shape

    # Edge detection — potholes have strong edges
    gray  = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2GRAY)
    edges = cv2.Canny(gray, 50, 150)
    edge_density = np.sum(edges > 0) / (h * w)
    print(f"[Pipeline] Heuristic: edge_density={edge_density:.4f}")

    # Find regions that are dark in the depth map (deeper = further from camera)
    # Use adaptive threshold based on image statistics
    p10 = np.percentile(depth_map, 10)
    p90 = np.percentile(depth_map, 90)
    depth_range = p90 - p10

    # Only proceed if there is meaningful depth variation
    if depth_range < 0.05:
        print("[Pipeline] Heuristic: insufficient depth variation — skipping")
        return None

    # Threshold: bottom 20% of depth values
    threshold = np.percentile(depth_map, 20)
    binary    = (depth_map < threshold).astype(np.uint8) * 255

    # Morphological cleanup
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (11, 11))
    binary = cv2.morphologyEx(binary, cv2.MORPH_CLOSE, kernel)
    binary = cv2.morphologyEx(binary, cv2.MORPH_OPEN,  kernel)

    contours, _ = cv2.findContours(binary, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return None

    # Filter out contours that are too small or too large (noise vs whole image)
    valid = [c for c in contours
             if (h * w * 0.001) < cv2.contourArea(c) < (h * w * 0.6)]
    if not valid:
        print("[Pipeline] Heuristic: no valid contours after size filter")
        return None

    largest = max(valid, key=cv2.contourArea)
    area    = cv2.contourArea(largest)
    print(f"[Pipeline] Heuristic: best contour area={area:.0f}px")

    mask = np.zeros_like(binary)
    cv2.drawContours(mask, [largest], -1, 255, cv2.FILLED)
    x, y, bw, bh = cv2.boundingRect(largest)

    # Confidence based on depth range and edge density — not a fixed 1.0
    heuristic_conf = min(0.5, depth_range * 2 + edge_density * 0.5)
    return {
        "mask": mask, "bbox": (x, y, x+bw, y+bh),
        "conf": heuristic_conf, "contours": [largest],
        "source": "heuristic"
    }


def _compute_metrics(depth_map: np.ndarray, mask: np.ndarray) -> dict:
    pothole_px = depth_map[mask == 255]
    road_px    = depth_map[mask == 0]
    if pothole_px.size < 50 or road_px.size < 50:
        return {}

    mean_d   = float(np.mean(pothole_px))
    min_d    = float(np.min(pothole_px))
    road_lvl = float(np.percentile(road_px, 85))

    # Normalised depth differences (typically ~0..1)
    rel_d = max(road_lvl - mean_d, 0.0)  # mean-based depth
    max_d = max(road_lvl - min_d,  0.0)  # worst-point depth

    # Combined score — more stable than rel_d alone.
    # Old thresholds (<0.05/<0.15) made almost everything "deep" because they
    # treated normalised 0..1 values as metres.  Tuned thresholds below
    # match the observed Supabase distribution (rel_d ~ 0.31–0.79).
    score = 0.6 * rel_d + 0.4 * max_d
    if score < 0.35:
        severity = "shallow"
    elif score < 0.65:
        severity = "moderate"
    else:
        severity = "deep"

    # Convert to mm for display/storage — consistent with cost_estimator.py
    # DEPTH_SCALE = 0.15 m/unit  →  DEPTH_MM_PER_UNIT = 150 mm/unit
    DEPTH_MM_PER_UNIT = 150.0
    rel_mm = rel_d * DEPTH_MM_PER_UNIT
    max_mm = max_d * DEPTH_MM_PER_UNIT

    print(
        f"[Pipeline] Metrics: rel_depth={rel_d:.4f} max_depth={max_d:.4f} "
        f"score={score:.4f} severity={severity} "
        f"rel_mm={rel_mm:.1f} max_mm={max_mm:.1f} area={pothole_px.size}px"
    )

    return {
        "relative_depth":    rel_d,
        "max_depth":         max_d,
        "road_level":        road_lvl,
        "severity":          severity,
        "pothole_area_px":   int(pothole_px.size),
        # mm estimates — add columns to ai_results in Supabase to persist these
        "relative_depth_mm": rel_mm,
        "max_depth_mm":      max_mm,
        "depth_mm_per_unit": DEPTH_MM_PER_UNIT,
    }


def _fig_to_bytes(fig) -> bytes:
    buf = io.BytesIO()
    fig.savefig(buf, format="png", dpi=100, bbox_inches="tight",
                facecolor=fig.get_facecolor())
    plt.close(fig)
    buf.seek(0)
    return buf.read()


def _make_depth_map(image_bgr, depth_map):
    fig, ax = plt.subplots(figsize=(7, 5))
    fig.patch.set_facecolor("#111827")
    ax.imshow(depth_map, cmap="magma")
    ax.axis("off")
    ax.set_title("Depth Map", color="#f9fafb", fontsize=12, fontweight="bold")
    return _fig_to_bytes(fig)


def _make_heatmap(image_bgr, depth_map, det):
    image_rgb = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2RGB).astype(np.float32)
    mask      = det["mask"]
    depth_inv = 1.0 - depth_map
    pot_vals  = depth_inv[mask == 255]
    if pot_vals.size == 0:
        return None
    d_min = pot_vals.min()
    d_max = pot_vals.max()
    norm  = ((depth_inv - d_min) / (d_max - d_min + 1e-8)).clip(0, 1)
    heatmap = (cm.get_cmap("RdYlGn_r")(norm)[:, :, :3] * 255).astype(np.float32)
    result  = image_rgb.copy()
    for c in range(3):
        result[:, :, c] = np.where(
            mask == 255,
            result[:, :, c] * 0.35 + heatmap[:, :, c] * 0.65,
            result[:, :, c]
        )
    result = result.clip(0, 255).astype(np.uint8)
    cv2.drawContours(result, det["contours"], -1, (255, 255, 255), 2)
    fig, axes = plt.subplots(1, 2, figsize=(13, 5))
    fig.patch.set_facecolor("#111827")
    axes[0].imshow(image_rgb.astype(np.uint8))
    axes[0].set_title("Original", color="#f9fafb", fontsize=11, fontweight="bold")
    axes[0].axis("off")
    axes[1].imshow(result)
    axes[1].set_title("Severity Heatmap", color="#f9fafb", fontsize=11, fontweight="bold")
    axes[1].axis("off")
    plt.tight_layout()
    return _fig_to_bytes(fig)


def _make_before_after(image_bgr, depth_map, detections):
    image_rgb = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2RGB)
    after     = image_rgb.copy().astype(np.float32)
    depth_color = (cm.get_cmap("magma")(depth_map)[:, :, :3] * 255).astype(np.float32)
    after = after * 0.75 + depth_color * 0.25
    COLORS = [(255, 60, 60), (60, 200, 255), (60, 255, 120), (255, 200, 60)]
    for idx, det in enumerate(detections):
        color = COLORS[idx % len(COLORS)]
        mask  = det["mask"]
        for c in range(3):
            after[:, :, c] = np.where(
                mask == 255, after[:, :, c] * 0.3 + color[c] * 0.7, after[:, :, c])
    after_u8 = after.clip(0, 255).astype(np.uint8)
    for idx, det in enumerate(detections):
        color = COLORS[idx % len(COLORS)]
        x1, y1, x2, y2 = det["bbox"]
        cv2.drawContours(after_u8, det["contours"], -1, color, 2)
        cv2.rectangle(after_u8, (x1, y1), (x2, y2), color, 2)
        label = f"#{idx+1} {det['conf']:.2f}"
        cv2.putText(after_u8, label, (x1+4, y1+18),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.5, color, 2, cv2.LINE_AA)
    fig, axes = plt.subplots(1, 2, figsize=(14, 6))
    fig.patch.set_facecolor("#111827")
    axes[0].imshow(image_rgb)
    axes[0].set_title("Before", color="#f9fafb", fontsize=12, fontweight="bold")
    axes[0].axis("off")
    axes[1].imshow(after_u8)
    axes[1].set_title("After — Analysis", color="#f9fafb", fontsize=12, fontweight="bold")
    axes[1].axis("off")
    plt.tight_layout()
    return _fig_to_bytes(fig)


def run_full_pipeline(image_bytes: bytes, report_id: str) -> dict:
    print(f"[Pipeline] Starting for report: {report_id}")

    # Decode image
    arr   = np.frombuffer(image_bytes, np.uint8)
    image = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if image is None:
        raise ValueError("Could not decode image — invalid format")

    # Resize very large images to max 1280px for speed
    h, w = image.shape[:2]
    if max(h, w) > 1280:
        scale = 1280 / max(h, w)
        image = cv2.resize(image, (int(w*scale), int(h*scale)))
        print(f"[Pipeline] Resized image to {image.shape[1]}x{image.shape[0]}")

    # Depth inference
    depth_model = _get_depth_model()
    depth_map   = _infer_depth(depth_model, image)

    # YOLO segmentation
    detections = []
    try:
        yolo       = _get_yolo_model()
        detections = _run_yolo(yolo, image)
    except Exception as e:
        print(f"[Pipeline] YOLO failed: {e}")

    # Heuristic fallback only if YOLO found nothing
    used_fallback = False
    if not detections:
        print("[Pipeline] YOLO found nothing — trying heuristic fallback")
        det = _heuristic_detect(depth_map, image)
        if det:
            detections = [det]
            used_fallback = True
        else:
            print("[Pipeline] Heuristic also found nothing")

    if not detections:
        print("[Pipeline] No detections at all — returning minimal result")
        depth_bytes = _make_depth_map(image, depth_map)
        return {
            "severity":         "shallow",
            "relative_depth":   0.0,
            "max_depth":        0.0,
            "pothole_area_px":  0,
            "confidence":       0.0,
            "depth_map_bytes":  depth_bytes,
            "heatmap_bytes":    None,
            "before_after_bytes": None,
            "used_fallback":    True,
        }

    # Use the highest-confidence detection
    best    = max(detections, key=lambda d: d["conf"])
    metrics = _compute_metrics(depth_map, best["mask"])

    if not metrics:
        print("[Pipeline] Metrics computation failed")
        return {
            "severity": "shallow", "relative_depth": 0.0,
            "max_depth": 0.0, "pothole_area_px": 0, "confidence": best["conf"],
            "depth_map_bytes": _make_depth_map(image, depth_map),
            "heatmap_bytes": None, "before_after_bytes": None,
        }

    # Generate visualisations
    print("[Pipeline] Generating visualisations...")
    depth_bytes        = _make_depth_map(image, depth_map)
    heatmap_bytes      = _make_heatmap(image, depth_map, best)
    before_after_bytes = _make_before_after(image, depth_map, detections)

    print(f"[Pipeline] Done — severity={metrics.get('severity')} "
          f"rel_depth={metrics.get('relative_depth', 0):.4f} "
          f"fallback={used_fallback}")

    return {
        "relative_depth":     metrics.get("relative_depth"),
        "max_depth":          metrics.get("max_depth"),
        "severity":           metrics.get("severity"),
        "pothole_area_px":    metrics.get("pothole_area_px"),
        "confidence":         best["conf"],
        "depth_map_bytes":    depth_bytes,
        "heatmap_bytes":      heatmap_bytes,
        "before_after_bytes": before_after_bytes,
        "used_fallback":      used_fallback,
        "relative_depth_mm":  metrics.get("relative_depth_mm"),
        "max_depth_mm":       metrics.get("max_depth_mm"),
        "depth_mm_per_unit":  metrics.get("depth_mm_per_unit"),
    }