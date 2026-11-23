import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/model.dart';

void main() {
  test('adjustments default to neutral and copy independently', () {
    final Adjustments a = Adjustments.zero();
    expect(a.isNeutral, isTrue);
    final Adjustments b = a.withValue('exposure', 40);
    expect(b['exposure'], 40);
    expect(a['exposure'], 0);
  });

  test('cover scale grows with rotation and is 1 at zero', () {
    expect(coverScale(100, 100, 0), 1);
    expect(coverScale(100, 100, 45) > 1.3, isTrue);
    expect(coverScale(100, 50, 90) > 1.9, isTrue);
  });

  test('project copy does not share mutable state', () {
    final Project p = Project()
      ..crop = CropRect(x: 0, y: 0, w: 200, h: 100)
      ..layers = <Layer>[Layer(id: 'a', type: LayerType.text, text: 'hi')];
    final Project q = p.copy();
    q.crop.angle = 12;
    q.layers.first.text = 'changed';
    expect(p.crop.angle, 0);
    expect(p.layers.first.text, 'hi');
  });

  test('filter lookup falls back to the first preset', () {
    expect(filterById('vivid').id, 'vivid');
    expect(filterById('nope').id, kFilters.first.id);
  });
}
