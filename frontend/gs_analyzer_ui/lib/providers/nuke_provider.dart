import 'package:flutter_riverpod/legacy.dart';

final nukeProgressProvider = StateProvider<double>((ref) => 0.0);
final nukeTargetProvider = StateProvider<String>((ref) => '');
final nukeCompletedProvider = StateProvider<int>((ref) => 0);
final nukeTotalProvider = StateProvider<int>((ref) => 0);
final isNukeActiveProvider = StateProvider<bool>((ref) => false);
