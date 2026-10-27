import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/enums.dart';

final analyticsFilterProvider = StateProvider<TimeFilter>((ref) {
  return TimeFilter.days7;
});
