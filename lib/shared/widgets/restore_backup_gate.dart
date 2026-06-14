import 'package:flutter/material.dart';

import '../../core/services/backup_service.dart';

class RestoreBackupGate extends StatefulWidget {
  const RestoreBackupGate({super.key, required this.child});

  final Widget child;

  @override
  State<RestoreBackupGate> createState() => _RestoreBackupGateState();
}

class _RestoreBackupGateState extends State<RestoreBackupGate> {
  var _checked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showRestoreToastIfNeeded());
  }

  Future<void> _showRestoreToastIfNeeded() async {
    if (_checked) return;
    _checked = true;

    final hasMarker = await BackupService.instance.hasPendingRestoreMarker();
    if (!mounted || !hasMarker) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.showSnackBar(
      const SnackBar(
        content: Text('Backup restored successfully.'),
        duration: Duration(seconds: 3),
      ),
    );
    await BackupService.instance.clearRestoreMarker();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
