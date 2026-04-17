// ── repair_estimator.dart ──────────────────────────────────────────────────
// Ahmedabad-specific pothole repair cost + severity estimator.
//
// All rates are "demo-realistic" ballpark figures for Ahmedabad, Gujarat.
// They can be adjusted in the const section below without changing any logic.
//
// Inputs expected in SI units:
//   areaM2  – pothole surface area in square metres  (e.g. 0.3)
//   depthMm – pothole depth in millimetres           (e.g. 40)
//
// Pixel/depth conversions (same calibration used by ai_worker/cost_estimator.py):
//   area_m2  = pothole_area_px / 8000
//   depth_mm = relative_depth  * 150      (DEPTH_SCALE=0.15 → depth_m → ×1000)
// ─────────────────────────────────────────────────────────────────────────────

/// Two supported repair strategies.
enum RepairType {
  /// Full cut-and-fill with hot-mix asphalt (HMA) — recommended default.
  properCutAndFillHma,

  /// Cold-mix / emergency temporary patch.
  temporaryPatch,
}

// ── Value object returned by the estimator ────────────────────────────────
class RepairEstimate {
  /// 'Shallow', 'Moderate', or 'Deep'
  final String severity;

  /// Clamped surface area that was used for computation (m²)
  final double areaM2;

  /// Clamped depth used for computation (mm)
  final double depthMm;

  /// Volume = areaM2 × (depthMm / 1000)  (m³)
  final double volumeM3;

  /// Single rounded cost in INR (nearest ₹50)
  final int costInr;

  const RepairEstimate({
    required this.severity,
    required this.areaM2,
    required this.depthMm,
    required this.volumeM3,
    required this.costInr,
  });
}

// ── Estimator ─────────────────────────────────────────────────────────────
class RepairEstimatorAhmedabad {
  // ── Ahmedabad repair rates (INR) ─────────────────────────────────────
  // Base cost covers mobilisation, equipment, traffic management, etc.
  static const int _baseProper    = 2500; // proper cut-and-fill
  static const int _baseTemporary = 900;  // cold-mix patch

  // Volume-based rates (₹ per m³).
  // Proper = HMA + compaction; temporary = cold-mix only.
  static const int _rateProperPerM3    = 24000;
  static const int _rateTemporaryPerM3 = 14000;

  // Hard limits so that unreliable measurements can't produce nonsense.
  static const int    _minCost     = 500;
  static const int    _maxCost     = 60000;
  static const double _maxAreaM2   = 50.0;  // sanity clamp on area
  static const double _maxDepthMm  = 300.0; // sanity clamp on depth

  // ── Severity depth thresholds (mm) ───────────────────────────────────
  static const double _shallowDepthMm  = 25.0;
  static const double _moderateDepthMm = 50.0;

  // ── Severity volume thresholds (m³) ──────────────────────────────────
  // Used as fallback when measured depth is zero / unreliable.
  static const double _shallowVolM3  = 0.003; // ~3 litres
  static const double _moderateVolM3 = 0.010; // ~10 litres

  // If area or depth is essentially zero we cannot compute a meaningful
  // volume-based cost, so return a conservative default rather than ₹0.
  static const int _defaultCostProper    = 1800;
  static const int _defaultCostTemporary = 700;
  static const double _minReliableAreaM2  = 0.05; // < 5 cm × 5 cm → unreliable
  static const double _minReliableDepthMm = 5.0;  // < 5 mm → unreliable

  /// Compute a [RepairEstimate] for a pothole with the given measurements.
  ///
  /// Convert the raw fields from [AiResult] before calling:
  /// ```dart
  /// final ai = report.aiResult;
  /// final est = RepairEstimatorAhmedabad.estimate(
  ///   areaM2:     (ai?.potholeAreaPx ?? 0) / 8000,
  ///   depthMm:    (ai?.relativeDepth ?? 0) * 150,
  ///   repairType: RepairType.properCutAndFillHma,
  /// );
  /// ```
  static RepairEstimate estimate({
    required double areaM2,
    required double depthMm,
    required RepairType repairType,
  }) {
    // Sanitise and clamp inputs to prevent edge-case outputs.
    final a   = areaM2.isFinite  ? areaM2.clamp(0.0, _maxAreaM2)  : 0.0;
    final dMm = depthMm.isFinite ? depthMm.clamp(0.0, _maxDepthMm) : 0.0;

    final depthM = dMm / 1000.0;
    final vol    = (a * depthM).isFinite ? (a * depthM) : 0.0;

    final severity = _severityFrom(a, dMm, vol);

    // If measurements are near-zero/missing, skip the formula and return a
    // conservative default so we never display ₹0 or an absurdly low cost.
    if (a < _minReliableAreaM2 || dMm < _minReliableDepthMm) {
      final defaultCost = repairType == RepairType.properCutAndFillHma
          ? _defaultCostProper
          : _defaultCostTemporary;
      return RepairEstimate(
        severity: severity,
        areaM2:   a,
        depthMm:  dMm,
        volumeM3: vol,
        costInr:  defaultCost,
      );
    }

    // Cost = base mobilisation + volume × material+labour rate.
    final base      = repairType == RepairType.properCutAndFillHma
        ? _baseProper
        : _baseTemporary;
    final ratePerM3 = repairType == RepairType.properCutAndFillHma
        ? _rateProperPerM3
        : _rateTemporaryPerM3;

    var cost = (base + vol * ratePerM3).round();

    // Clamp to absolute limits.
    cost = cost.clamp(_minCost, _maxCost);

    // Round to the nearest ₹50 for a cleaner display (e.g. ₹2,550 → ₹2,550).
    cost = ((cost / 50).round() * 50).clamp(_minCost, _maxCost);

    return RepairEstimate(
      severity: severity,
      areaM2:   a,
      depthMm:  dMm,
      volumeM3: vol,
      costInr:  cost,
    );
  }

  // ── Severity classification ────────────────────────────────────────────
  static String _severityFrom(
      double areaM2, double depthMm, double volumeM3) {
    // Prefer depth-based classification when depth is available.
    if (depthMm >= _moderateDepthMm) return 'Deep';
    if (depthMm >= _shallowDepthMm)  return 'Moderate';
    if (depthMm > 0)                 return 'Shallow';

    // Depth is zero / unreliable → fall back to volume, then area.
    if (volumeM3 >= _moderateVolM3) return 'Deep';
    if (volumeM3 >= _shallowVolM3)  return 'Moderate';

    // Last resort: area-only classification.
    if (areaM2 >= 0.5) return 'Moderate';
    return 'Shallow';
  }
}
