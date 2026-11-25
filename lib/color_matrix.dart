import 'model.dart';

/// Composes two 4×5 colour matrices (a applied after b).
List<double> _multiply(List<double> a, List<double> b) {
  final List<double> out = List<double>.filled(20, 0);
  for (int r = 0; r < 4; r++) {
    for (int col = 0; col < 5; col++) {
      double sum = 0;
      for (int k = 0; k < 4; k++) {
        sum += a[r * 5 + k] * b[k * 5 + col];
      }
      if (col == 4) sum += a[r * 5 + 4];
      out[r * 5 + col] = sum;
    }
  }
  return out;
}

const List<double> _identity = <double>[
  1, 0, 0, 0, 0,
  0, 1, 0, 0, 0,
  0, 0, 1, 0, 0,
  0, 0, 0, 1, 0,
];

List<double> _saturation(double s) {
  const double lr = 0.2126, lg = 0.7152, lb = 0.0722;
  return <double>[
    lr * (1 - s) + s, lg * (1 - s), lb * (1 - s), 0, 0,
    lr * (1 - s), lg * (1 - s) + s, lb * (1 - s), 0, 0,
    lr * (1 - s), lg * (1 - s), lb * (1 - s) + s, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

/// Approximation of a filter preset, for live preview only.
List<double> previewMatrix(FilterPreset p, double strength) {
  final double s = (1 + p.saturation).clamp(0.0, 2.0);
  final double c = (1 + p.contrast).clamp(0.4, 2.0);
  final double sr = p.mono > 0 ? 0.0 : s;
  final double tR = 1 + p.temperature * 0.45;
  final double tG = 1 + p.tint * 0.25 - p.temperature * 0.05;
  final double tB = 1 - p.temperature * 0.45;

  final List<double> sat = _saturation(sr);
  final List<double> scaled = <double>[
    sat[0] * c * tR, sat[1] * c * tR, sat[2] * c * tR, 0, 0,
    sat[5] * c * tG, sat[6] * c * tG, sat[7] * c * tG, 0, 0,
    sat[10] * c * tB, sat[11] * c * tB, sat[12] * c * tB, 0, 0,
    0, 0, 0, 1, 0,
  ];
  final double pivot = 128 * (1 - c);
  final List<double> full = <double>[
    scaled[0], scaled[1], scaled[2], 0,
    pivot + p.exposure * 255 + p.fade * 30 + p.lift[0] * 255,
    scaled[5], scaled[6], scaled[7], 0,
    pivot + p.exposure * 255 + p.fade * 30 + p.lift[1] * 255,
    scaled[10], scaled[11], scaled[12], 0,
    pivot + p.exposure * 255 + p.fade * 30 + p.lift[2] * 255,
    0, 0, 0, 1, 0,
  ];
  final double k = strength.clamp(0.0, 1.0);
  return <double>[
    for (int i = 0; i < 20; i++) _identity[i] + (full[i] - _identity[i]) * k
  ];
}

/// Approximation of the adjustment sliders, for live preview only.
List<double> matrixForAdjustments(Adjustments a) {
  final double s = (1 + a['saturation'] / 100).clamp(0.0, 2.0);
  final double c = (1 + a['contrast'] / 100 * 0.9).clamp(0.4, 2.0);
  final double tR = 1 + a['temperature'] / 100 * 0.30;
  final double tG = 1 - a['tint'] / 100 * 0.20;
  final double tB = 1 - a['temperature'] / 100 * 0.30;
  final List<double> sat = _saturation(s);
  final List<double> scaled = <double>[
    sat[0] * c * tR, sat[1] * c * tR, sat[2] * c * tR, 0, 0,
    sat[5] * c * tG, sat[6] * c * tG, sat[7] * c * tG, 0, 0,
    sat[10] * c * tB, sat[11] * c * tB, sat[12] * c * tB, 0, 0,
    0, 0, 0, 1, 0,
  ];
  final double pivot = 128 * (1 - c);
  final double lift = a['exposure'] / 100 * 42 + a['brightness'] / 100 * 38 +
      a['fade'] / 100 * 26;
  return <double>[
    scaled[0], scaled[1], scaled[2], 0, pivot + lift,
    scaled[5], scaled[6], scaled[7], 0, pivot + lift,
    scaled[10], scaled[11], scaled[12], 0, pivot + lift,
    0, 0, 0, 1, 0,
  ];
}

/// Adjustments then filter, as one matrix for the live video preview.
List<double> projectMatrix(Adjustments a, FilterPreset p, double amount) {
  final List<double> adj = matrixForAdjustments(a);
  if (p.id == 'none' || amount <= 0) return adj;
  return _multiply(previewMatrix(p, amount), adj);
}
