/// Ahmedabad-calibrated single-value pothole repair cost estimator.
///
/// Uses the same calibration constants as the Python backend
/// (cost_estimator.py) so Flutter-computed costs align with the AI worker.
class RepairEstimatorAhmedabad {
  // Calibration constants — keep in sync with ai_worker/cost_estimator.py
  static const double _pixelsPerM2    = 8000;  // typical phone at ~1 m height
  static const double _depthScale     = 0.15;  // normalized depth (0-1) → meters
  static const double _asphaltDensity = 1.8;   // kg / litre
  static const double _labourRateInr  = 500;   // INR / hour
  static const double _asphaltCostPerKg = 15;  // INR / kg
  static const double _overheadFactor = 1.3;   // 30 % overhead

  // Fallback defaults when actual measurements are unavailable
  static const Map<String, double> _areaDefaults  = {
    'shallow': 0.3, 'moderate': 0.6, 'deep': 1.2,
  };
  static const Map<String, double> _depthDefaults = {
    'shallow': 0.02, 'moderate': 0.05, 'deep': 0.12,
  };
  static const Map<String, double> _labourDefaults = {
    'shallow': 0.5, 'moderate': 1.5, 'deep': 4.0,
  };

  final String severity;
  final double? areaPx;
  final double? relativeDepth;

  const RepairEstimatorAhmedabad({
    required this.severity,
    this.areaPx,
    this.relativeDepth,
  });

  double get _areaM2 {
    if (areaPx != null && areaPx! > 0) return areaPx! / _pixelsPerM2;
    return _areaDefaults[severity] ?? 0.5;
  }

  double get _depthM {
    if (relativeDepth != null && relativeDepth! > 0) {
      return relativeDepth! * _depthScale;
    }
    return _depthDefaults[severity] ?? 0.05;
  }

  /// Single INR cost estimate.
  double get costInr {
    final volumeL  = _areaM2 * _depthM * 1000;
    final asphaltKg = volumeL * _asphaltDensity;
    final labourHrs = _labourDefaults[severity] ?? 1.5;
    final raw = asphaltKg * _asphaltCostPerKg + labourHrs * _labourRateInr;
    return (raw * _overheadFactor).roundToDouble();
  }

  /// Formatted cost string, e.g. "₹1.5k" or "₹850".
  String get costLabel {
    final c = costInr;
    if (c >= 1000) return '₹${(c / 1000).toStringAsFixed(1)}k';
    return '₹${c.toStringAsFixed(0)}';
  }

  /// Estimated depth in mm from normalised [relativeDepth].
  double? get depthMm =>
      relativeDepth != null ? relativeDepth! * _depthScale * 1000 : null;

  /// Estimated area in m² from [areaPx].
  double? get areaM2 => areaPx != null && areaPx! > 0 ? areaPx! / _pixelsPerM2 : null;
}
