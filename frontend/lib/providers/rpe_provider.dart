import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';
import '../services/rpe_api.dart';

final rpeApiProvider = Provider<RpeApi>(
  (ref) => RpeApi(ref.read(apiClientProvider)),
);
