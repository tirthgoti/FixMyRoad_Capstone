import 'package:flutter_test/flutter_test.dart';
import 'package:fixmyroad/utils/repair_estimator.dart';

void main() {
  group('RepairEstimatorAhmedabad', () {
    test('shallow with defaults returns lower cost than deep', () {
      final shallow = RepairEstimatorAhmedabad(severity: 'shallow');
      final deep    = RepairEstimatorAhmedabad(severity: 'deep');
      expect(shallow.costInr, lessThan(deep.costInr));
    });

    test('moderate cost is between shallow and deep', () {
      final shallow  = RepairEstimatorAhmedabad(severity: 'shallow');
      final moderate = RepairEstimatorAhmedabad(severity: 'moderate');
      final deep     = RepairEstimatorAhmedabad(severity: 'deep');
      expect(moderate.costInr, greaterThan(shallow.costInr));
      expect(moderate.costInr, lessThan(deep.costInr));
    });

    test('costLabel starts with ₹', () {
      final est = RepairEstimatorAhmedabad(severity: 'moderate');
      expect(est.costLabel, startsWith('₹'));
    });

    test('costLabel uses k suffix for values >= 1000', () {
      final est = RepairEstimatorAhmedabad(severity: 'deep');
      expect(est.costInr, greaterThanOrEqualTo(1000));
      expect(est.costLabel, contains('k'));
    });

    test('larger area increases cost', () {
      final small = RepairEstimatorAhmedabad(
          severity: 'moderate', areaPx: 1000);
      final large = RepairEstimatorAhmedabad(
          severity: 'moderate', areaPx: 10000);
      expect(large.costInr, greaterThan(small.costInr));
    });

    test('deeper relative depth increases cost', () {
      final shallow = RepairEstimatorAhmedabad(
          severity: 'moderate', relativeDepth: 0.1);
      final deeper  = RepairEstimatorAhmedabad(
          severity: 'moderate', relativeDepth: 0.8);
      expect(deeper.costInr, greaterThan(shallow.costInr));
    });

    test('depthMm is null when relativeDepth is null', () {
      final est = RepairEstimatorAhmedabad(severity: 'shallow');
      expect(est.depthMm, isNull);
    });

    test('depthMm is 150 * relativeDepth', () {
      final est = RepairEstimatorAhmedabad(
          severity: 'moderate', relativeDepth: 0.4);
      expect(est.depthMm, closeTo(0.4 * 150, 0.001));
    });

    test('areaM2 is null when areaPx is null', () {
      final est = RepairEstimatorAhmedabad(severity: 'shallow');
      expect(est.areaM2, isNull);
    });

    test('areaM2 is areaPx / 8000', () {
      final est = RepairEstimatorAhmedabad(severity: 'moderate', areaPx: 8000);
      expect(est.areaM2, closeTo(1.0, 0.001));
    });
  });
}
