import 'package:flutter_test/flutter_test.dart';
import 'package:fixmyroad/utils/repair_estimator.dart';

void main() {
  group('RepairEstimatorAhmedabad', () {
    // ── Severity thresholds ────────────────────────────────────────────
    group('severity classification', () {
      test('returns Shallow when depth < 25 mm', () {
        final est = RepairEstimatorAhmedabad.estimate(
          areaM2: 0.3,
          depthMm: 10,
          repairType: RepairType.properCutAndFillHma,
        );
        expect(est.severity, 'Shallow');
      });

      test('returns Moderate when depth is between 25 and 50 mm', () {
        final est = RepairEstimatorAhmedabad.estimate(
          areaM2: 0.3,
          depthMm: 35,
          repairType: RepairType.properCutAndFillHma,
        );
        expect(est.severity, 'Moderate');
      });

      test('returns Deep when depth >= 50 mm', () {
        final est = RepairEstimatorAhmedabad.estimate(
          areaM2: 0.3,
          depthMm: 60,
          repairType: RepairType.properCutAndFillHma,
        );
        expect(est.severity, 'Deep');
      });

      test('returns Shallow when depth is 0 but area is small', () {
        final est = RepairEstimatorAhmedabad.estimate(
          areaM2: 0.2,
          depthMm: 0,
          repairType: RepairType.properCutAndFillHma,
        );
        expect(est.severity, 'Shallow');
      });

      test('returns Moderate when depth is 0 but area >= 0.5 m²', () {
        final est = RepairEstimatorAhmedabad.estimate(
          areaM2: 0.6,
          depthMm: 0,
          repairType: RepairType.properCutAndFillHma,
        );
        expect(est.severity, 'Moderate');
      });
    });

    // ── Cost sanity checks ─────────────────────────────────────────────
    group('cost computation', () {
      test('returns conservative default when area is near-zero', () {
        final est = RepairEstimatorAhmedabad.estimate(
          areaM2: 0.0,
          depthMm: 40,
          repairType: RepairType.properCutAndFillHma,
        );
        expect(est.costInr, 1800);
      });

      test('returns conservative default for temporary patch when area near-zero', () {
        final est = RepairEstimatorAhmedabad.estimate(
          areaM2: 0.0,
          depthMm: 40,
          repairType: RepairType.temporaryPatch,
        );
        expect(est.costInr, 700);
      });

      test('returns conservative default when depth is near-zero', () {
        final est = RepairEstimatorAhmedabad.estimate(
          areaM2: 0.3,
          depthMm: 0,
          repairType: RepairType.properCutAndFillHma,
        );
        expect(est.costInr, 1800);
      });

      test('cost is always a multiple of 50', () {
        for (final depthMm in [25.0, 40.0, 65.0, 100.0]) {
          final est = RepairEstimatorAhmedabad.estimate(
            areaM2: 0.4,
            depthMm: depthMm,
            repairType: RepairType.properCutAndFillHma,
          );
          expect(est.costInr % 50, 0,
              reason: 'cost ₹${est.costInr} for depth ${depthMm}mm should be multiple of 50');
        }
      });

      test('proper repair costs more than temporary patch', () {
        final proper = RepairEstimatorAhmedabad.estimate(
          areaM2: 0.5,
          depthMm: 40,
          repairType: RepairType.properCutAndFillHma,
        );
        final temp = RepairEstimatorAhmedabad.estimate(
          areaM2: 0.5,
          depthMm: 40,
          repairType: RepairType.temporaryPatch,
        );
        expect(proper.costInr, greaterThan(temp.costInr));
      });

      test('cost stays within min/max bounds', () {
        // Very large pothole
        final big = RepairEstimatorAhmedabad.estimate(
          areaM2: 50,
          depthMm: 300,
          repairType: RepairType.properCutAndFillHma,
        );
        expect(big.costInr, lessThanOrEqualTo(60000));

        // Tiny pothole
        final small = RepairEstimatorAhmedabad.estimate(
          areaM2: 0.1,
          depthMm: 10,
          repairType: RepairType.properCutAndFillHma,
        );
        expect(small.costInr, greaterThanOrEqualTo(500));
      });

      test('non-finite inputs are treated as zero', () {
        final est = RepairEstimatorAhmedabad.estimate(
          areaM2: double.nan,
          depthMm: double.infinity,
          repairType: RepairType.properCutAndFillHma,
        );
        // Both area and depth become 0 → conservative default
        expect(est.costInr, 1800);
        expect(est.severity, 'Shallow');
      });
    });

    // ── Volume field ──────────────────────────────────────────────────
    test('volume equals area × depth/1000', () {
      final est = RepairEstimatorAhmedabad.estimate(
        areaM2: 0.4,
        depthMm: 50,
        repairType: RepairType.properCutAndFillHma,
      );
      expect(est.volumeM3, closeTo(0.4 * 0.050, 1e-9));
    });
  });
}
