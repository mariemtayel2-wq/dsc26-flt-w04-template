import 'package:flutter/material.dart';

/// Shows how many outcomes are waiting to sync.
///
/// Works, but has problems (see the README, Part B).
class SyncBanner extends StatelessWidget {
  const SyncBanner({super.key, required this.pendingCount});

  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    final message = pendingCount == 0 ? 'Synced' : '$pendingCount pending';
    
    return Semantics(
      key: const Key('sync-banner'), 
      liveRegion: true, 
            child: Container(
        width: double.infinity,
        color: pendingCount == 0 ? Colors.green.shade100 : Colors.orange.shade100,
        padding: const EdgeInsetsDirectional.only(start: 16, top: 8, bottom: 8, end: 16),
        child: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
