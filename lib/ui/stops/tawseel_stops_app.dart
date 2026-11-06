import 'package:flutter/material.dart';

import '../../domain/stop.dart';
import 'stop_tile.dart';
import 'sync_banner.dart';

/// Today's stops for one courier.
class TawseelStopsApp extends StatefulWidget {
  const TawseelStopsApp({
    super.key,
    required this.stops,
    required this.pendingCount,
    this.textDirection = TextDirection.ltr,
  });

  final List<Stop> stops;
  final int pendingCount;
  final TextDirection textDirection;

  @override
  State<TawseelStopsApp> createState() => _TawseelStopsAppState();
}

class _TawseelStopsAppState extends State<TawseelStopsApp> {
  Stop? _selectedStop;

  @override
  Widget build(BuildContext context) {
    if (widget.stops.isNotEmpty && _selectedStop == null) {
      _selectedStop = widget.stops.first;
    }

    return MaterialApp(
      title: 'Tawseel stops',
      debugShowCheckedModeBanner: false,
      builder: (context, child) =>
          Directionality(textDirection: widget.textDirection, child: child!),
      home: Scaffold(
        appBar: AppBar(title: const Text("Today's stops")),
        body: Column(
          children: [
            SyncBanner(
              key: const Key('sync-banner'),
              pendingCount: widget.pendingCount,
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final bool isExpanded = constraints.maxWidth >= 600;

                  if (isExpanded) {
                    return KeyedSubtree(
                      key: const Key('layout-expanded'),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 1,
                            child: ListView.builder(
                              itemCount: widget.stops.length,
                              itemBuilder: (context, i) => StopTile(
                                key: Key('stop-${widget.stops[i].id}'),
                                stop: widget.stops[i],
                                onTap: () {
                                  setState(() {
                                    _selectedStop = widget.stops[i];
                                  });
                                },
                                onCall: () {},
                              ),
                            ),
                          ),
                          const VerticalDivider(width: 1),
                          Expanded(
                            flex: 2,
                            child: Center(
                              child: _selectedStop == null
                                  ? const Text('Select a stop to view details')
                                  : Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Customer: ${_selectedStop!.customerName}',
                                            style: const TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold),
                                          ),
                                          const SizedBox(height: 8),
                                          Text('Address: ${_selectedStop!.address}',
                                              style: const TextStyle(fontSize: 16)),
                                          const SizedBox(height: 8),
                                          Text('Status: ${_selectedStop!.status.name}',
                                              style: const TextStyle(fontSize: 16)),
                                        ],
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    );
                  } else {
                    return KeyedSubtree(
                      key: const Key('layout-compact'),
                      child: ListView.builder(
                        itemCount: widget.stops.length,
                        itemBuilder: (context, i) => StopTile(
                          key: Key('stop-${widget.stops[i].id}'),
                          stop: widget.stops[i],
                          onTap: () {
                          },
                          onCall: () {},
                        ),
                      ),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}