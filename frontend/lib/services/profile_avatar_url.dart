String? profileAvatarUrl(Object? raw, String baseUrl) {
  final text = raw?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  final uri = Uri.tryParse(text);
  if (uri == null) return null;
  final resolved = uri.hasScheme ? uri : Uri.parse('$baseUrl/').resolveUri(uri);
  return ['http', 'https'].contains(resolved.scheme) && resolved.host.isNotEmpty
      ? resolved.toString()
      : null;
}
