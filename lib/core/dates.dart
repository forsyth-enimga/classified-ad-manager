/// Small date helpers. Dates are stored as yyyy-MM-dd strings.
String fmtDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

bool isValidDate(String s) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return false;
  final d = DateTime.tryParse(s);
  return d != null && fmtDate(d) == s;
}

DateTime? parseDate(String s) => isValidDate(s) ? DateTime.parse(s) : null;
