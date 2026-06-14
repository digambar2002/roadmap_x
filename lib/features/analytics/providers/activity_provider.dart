import 'package:hooks_riverpod/hooks_riverpod.dart';

final activityTickProvider = StateProvider<int>((_) => 0);

void bumpActivityTick(WidgetRef ref) {
  ref.read(activityTickProvider.notifier).state++;
}
