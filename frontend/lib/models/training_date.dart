/// Training calendar dates belong to Thailand, regardless of device timezone.
DateTime? trainingDate(Object? value) {
  final text = value?.toString() ?? '';
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return null;
  final date =
      parsed.isUtc ? parsed.toUtc().add(const Duration(hours: 7)) : parsed;
  return DateTime(date.year, date.month, date.day);
}

DateTime trainingToday() {
  final today = DateTime.now().toUtc().add(const Duration(hours: 7));
  return DateTime(today.year, today.month, today.day);
}

String? trainingDateKey(Object? value) {
  final date = trainingDate(value);
  if (date == null) return null;
  return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
