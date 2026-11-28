/// OneSpace Finances (28 Nov 2026, D110+): exact money amounts.
///
/// Amounts are never `double`. An [Amount] is a whole number of
/// ten-thousandths (scale 4), the same scale the database uses
/// (`numeric(15,4)`). That covers currencies with 0, 2 or 3 decimals.
/// Multiplying by a percentage or a fraction is done with whole numbers
/// and rounded once, half away from zero, to the currency's own decimals.
library;

class Amount implements Comparable<Amount> {
  const Amount._(this.units);

  /// Ten-thousandths of the currency unit.
  final BigInt units;

  static const int scale = 4;
  static final BigInt _one = BigInt.from(10000);
  static final Amount zero = Amount._(BigInt.zero);

  factory Amount.units(BigInt units) => Amount._(units);
  factory Amount.whole(int value) => Amount._(BigInt.from(value) * _one);

  /// Parses "1234", "1234.5", "-12.3456", "1,234.50" (thousands commas are
  /// ignored). Also accepts Arabic-Indic digits and the Arabic decimal mark.
  /// Throws [FormatException] for anything else or more than 4 decimals.
  factory Amount.parse(String input) {
    final s = _normalizeDigits(input.trim()).replaceAll(',', '').replaceAll(' ', '');
    final m = RegExp(r'^([+-]?)(\d*)(?:\.(\d*))?$').firstMatch(s);
    if (m == null || ((m.group(2) ?? '').isEmpty && (m.group(3) ?? '').isEmpty)) {
      throw FormatException('Not an amount', input);
    }
    final whole = m.group(2)!.isEmpty ? '0' : m.group(2)!;
    var frac = m.group(3) ?? '';
    if (frac.length > scale) {
      // Postgres may send trailing zeros beyond the scale ("12.50000").
      if (RegExp(r'^0+$').hasMatch(frac.substring(scale))) {
        frac = frac.substring(0, scale);
      } else {
        throw FormatException('Too many decimals', input);
      }
    }
    frac = frac.padRight(scale, '0');
    var units = BigInt.parse(whole) * _one + BigInt.parse(frac);
    if (m.group(1) == '-') units = -units;
    return Amount._(units);
  }

  static Amount? tryParse(String? input) {
    if (input == null || input.trim().isEmpty) return null;
    try {
      return Amount.parse(input);
    } on FormatException {
      return null;
    }
  }

  /// Reads a value as it comes back from the database. Selects cast money
  /// columns to text (`amount::text`), so this is normally a string.
  static Amount? fromDb(Object? value) {
    if (value == null) return null;
    if (value is int) return Amount.whole(value);
    return Amount.parse(value.toString());
  }

  static String _normalizeDigits(String s) {
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    final b = StringBuffer();
    for (final r in s.runes) {
      final c = String.fromCharCode(r);
      final a = arabic.indexOf(c);
      final p = persian.indexOf(c);
      if (a >= 0) {
        b.write(a);
      } else if (p >= 0) {
        b.write(p);
      } else if (c == '٫') {
        b.write('.');
      } else if (c == '٬') {
        b.write(',');
      } else {
        b.write(c);
      }
    }
    return b.toString();
  }

  bool get isZero => units == BigInt.zero;
  bool get isNegative => units < BigInt.zero;
  bool get isPositive => units > BigInt.zero;

  Amount operator +(Amount o) => Amount._(units + o.units);
  Amount operator -(Amount o) => Amount._(units - o.units);
  Amount operator -() => Amount._(-units);
  Amount times(int n) => Amount._(units * BigInt.from(n));
  bool operator <(Amount o) => units < o.units;
  bool operator <=(Amount o) => units <= o.units;
  bool operator >(Amount o) => units > o.units;
  bool operator >=(Amount o) => units >= o.units;

  Amount max(Amount o) => this >= o ? this : o;
  Amount min(Amount o) => this <= o ? this : o;

  @override
  int compareTo(Amount other) => units.compareTo(other.units);
  @override
  bool operator ==(Object other) => other is Amount && other.units == units;
  @override
  int get hashCode => units.hashCode;

  /// Rounds to [decimals] (0–4), half away from zero.
  Amount rounded(int decimals) => Amount._(_roundUnits(units, BigInt.one, decimals));

  /// `this * numerator / denominator`, rounded once to [decimals].
  Amount mulDiv(BigInt numerator, BigInt denominator, int decimals) {
    if (denominator == BigInt.zero) throw ArgumentError('denominator is zero');
    return Amount._(_roundUnits(units * numerator, denominator, decimals));
  }

  /// Rounds `value / den` (value in units) to [decimals], half away from zero.
  static BigInt _roundUnits(BigInt value, BigInt den, int decimals) {
    final d = decimals.clamp(0, scale);
    if (den.isNegative) {
      value = -value;
      den = -den;
    }
    final step = BigInt.from(10).pow(scale - d) * den; // one smallest coin, in value terms
    final neg = value.isNegative;
    final abs = neg ? -value : value;
    var q = abs ~/ step;
    final r = abs - q * step;
    if (r * BigInt.two >= step) q += BigInt.one;
    final out = q * BigInt.from(10).pow(scale - d);
    return neg ? -out : out;
  }

  /// Plain text for the database or an input field, e.g. "1234.50".
  String toDb() => _plain(scale);

  /// Text with exactly [decimals] decimals and thousands separators,
  /// e.g. "1,234.50". Rounds first.
  String format(int decimals, {bool group = true}) {
    final r = rounded(decimals);
    return r._plain(decimals, group: group);
  }

  /// For an editable field: no grouping, trailing zeros removed.
  String toInput() {
    var s = _plain(scale);
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+$'), '');
      if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    }
    return s;
  }

  String _plain(int decimals, {bool group = false}) {
    final neg = units.isNegative;
    final abs = neg ? -units : units;
    final whole = (abs ~/ _one).toString();
    final frac = (abs % _one).toString().padLeft(scale, '0').substring(0, decimals);
    final w = group ? _group(whole) : whole;
    return '${neg ? '-' : ''}$w${decimals > 0 ? '.$frac' : ''}';
  }

  static String _group(String digits) {
    final b = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) b.write(',');
      b.write(digits[i]);
    }
    return b.toString();
  }

  @override
  String toString() => toDb();
}

/// An exact rate such as a yearly percentage change (+10, -2.5).
/// Stored as ten-thousandths of a percent point (scale 4), like [Amount].
class Percent {
  const Percent._(this.units);
  final BigInt units;
  static final Percent zero = Percent._(BigInt.zero);
  factory Percent.parse(String input) => Percent._(Amount.parse(input).units);
  static Percent? fromDb(Object? v) => v == null ? null : Percent.parse(v.toString());
  String toDb() => Amount.units(units).toDb();
  String toInput() => Amount.units(units).toInput();
  bool get isZero => units == BigInt.zero;
  @override
  bool operator ==(Object other) => other is Percent && other.units == units;
  @override
  int get hashCode => units.hashCode;
}

/// Currency decimals (ISO 4217 minor units) for the currencies that do not
/// use 2. Anything not listed uses 2.
int currencyDecimals(String code) {
  const zero = {'BIF', 'CLP', 'DJF', 'GNF', 'ISK', 'JPY', 'KMF', 'KRW', 'PYG', 'RWF', 'UGX',
    'UYI', 'VND', 'VUV', 'XAF', 'XOF', 'XPF'};
  const three = {'BHD', 'IQD', 'JOD', 'KWD', 'LYD', 'OMR', 'TND'};
  final c = code.toUpperCase();
  if (zero.contains(c)) return 0;
  if (three.contains(c)) return 3;
  return 2;
}

/// A sum per currency. Finances never adds different currencies together
/// (conversion comes in a later iteration, A13).
class CurrencyTotals {
  final Map<String, Amount> _byCurrency = {};

  void add(String currency, Amount amount) {
    final c = currency.toUpperCase();
    _byCurrency[c] = (_byCurrency[c] ?? Amount.zero) + amount;
  }

  Amount of(String currency) => _byCurrency[currency.toUpperCase()] ?? Amount.zero;
  Iterable<String> get currencies => _byCurrency.keys.toList()..sort();
  bool get isEmpty => _byCurrency.values.every((a) => a.isZero);
  Map<String, Amount> get asMap => Map.unmodifiable(_byCurrency);
}
