import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/delivery_outcome.dart';
import 'local_store.dart';

const String outboxStorageKey = 'tawseel.outbox.v1';

enum EntryStatus { pending, rejected }

final class OutboxEntry {
  const OutboxEntry({
    required this.id,
    required this.outcome,
    this.attempts = 0,
    this.status = EntryStatus.pending,
    this.rejectionReason,
  });

  final String id;
  final DeliveryOutcome outcome;
  final int attempts;
  final EntryStatus status;
  final String? rejectionReason;

  OutboxEntry copyWith({
    DeliveryOutcome? outcome,
    int? attempts,
    EntryStatus? status,
    String? rejectionReason,
  }) =>
      OutboxEntry(
        id: id,
        outcome: outcome ?? this.outcome,
        attempts: attempts ?? this.attempts,
        status: status ?? this.status,
        rejectionReason: rejectionReason ?? this.rejectionReason,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'outcome': outcome.toJson(),
        'attempts': attempts,
        'status': status.name,
        'rejectionReason': rejectionReason,
      };

  factory OutboxEntry.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final outcome = json['outcome'];
    final attempts = json['attempts'];
    final status = json['status'];
    final reason = json['rejectionReason'];
    if (id is! String || outcome is! Map || attempts is! int ||
        status is! String || (reason != null && reason is! String)) {
      throw FormatException('bad outbox entry: $json');
    }
    return OutboxEntry(
      id: id,
      outcome: DeliveryOutcome.fromJson(outcome.cast<String, Object?>()),
      attempts: attempts,
      status: EntryStatus.values.byName(status),
      rejectionReason: reason as String?,
    );
  }

  @override
  String toString() =>
      'OutboxEntry($id, ${outcome.parcelId}, attempts: $attempts, ${status.name})';
}

final class SyncReport {
  const SyncReport({
    required this.sent,
    required this.rejected,
    required this.remaining,
    this.authRequired = false,
    this.retryAfter,
  });

  final int sent;
  final int rejected;
  final int remaining;
  final bool authRequired;
  final Duration? retryAfter;

  @override
  String toString() => 'SyncReport(sent: $sent, rejected: $rejected, '
      'remaining: $remaining, authRequired: $authRequired, '
      'retryAfter: $retryAfter)';
}

Duration retryDelay(int consecutiveFailures) {
  if (consecutiveFailures < 1) {
    throw ArgumentError('consecutiveFailures must be at least 1');
  } else {
    final seconds = 5 * (1 << (consecutiveFailures - 1));
    final delay = Duration(seconds: seconds);
    return delay > const Duration(seconds: 300) 
        ? const Duration(seconds: 300) 
        : delay;
  }
}

class Outbox {
  Outbox({
    required LocalStore store,
    required http.Client client,
    required Uri baseUrl,
    required String Function() newId,
  })  : _store = store,
        _client = client,
        _baseUrl = baseUrl,
        _newId = newId;

  final LocalStore _store;
  final http.Client _client;
  final Uri _baseUrl;
  final String Function() _newId;

  Future<OutboxEntry> record(DeliveryOutcome outcome) async {
    if (outcome.parcelId.isEmpty) {
      throw ArgumentError('parcelId cannot be empty');
    }
    bool isDelivered = (outcome.reason == null || outcome.reason!.index == 0);

    if (outcome.status == OutcomeStatus.delivered) {
      if (outcome.codCollectedPiasters < 0 || !isDelivered) {
        throw ArgumentError('Invalid delivery outcome details');
      }
    } else if (outcome.status == OutcomeStatus.failed) {
      if (outcome.codCollectedPiasters != 0 || isDelivered) {
        throw ArgumentError('Failed delivery must have a reason and 0 piasters');
      }
    } else {
      throw ArgumentError('Invalid outcome status');
    }

    List<OutboxEntry> queue = await _store.read(outboxStorageKey).then((jsonString) {
      if (jsonString == null) {
        return <OutboxEntry>[];
      }
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList.map((json) => OutboxEntry.fromJson(json)).toList();
    });

    int existingIndex = queue.indexWhere(
      (entry) => entry.outcome.parcelId == outcome.parcelId && entry.attempts == 0,
    );

    OutboxEntry entryToSave;

    if (existingIndex != -1) {
      var oldEntry = queue[existingIndex];
      entryToSave = OutboxEntry(
        id: oldEntry.id,
        outcome: outcome,
        attempts: 0,
        status: EntryStatus.pending,
      );
      queue[existingIndex] = entryToSave;
    } else {
      entryToSave = OutboxEntry(
        id: _newId(),
        outcome: outcome,
        attempts: 0,
        status: EntryStatus.pending,
      );
      queue.add(entryToSave);
    }

    await _store.write(outboxStorageKey, jsonEncode(queue.map((entry) => entry.toJson()).toList()));

    return entryToSave;
  }

  Future<List<OutboxEntry>> pending() async {
    final read = await _store.read(outboxStorageKey);
    final List<OutboxEntry> queue = read == null
        ? <OutboxEntry>[]
        : (jsonDecode(read) as List<dynamic>)
            .map((json) => OutboxEntry.fromJson(json as Map<String, dynamic>))
            .toList();
    return queue.where((entry) => entry.status == EntryStatus.pending).toList();
  }

  Future<List<OutboxEntry>> rejected() async {
    final read = await _store.read(outboxStorageKey);
    final List<OutboxEntry> queue = read == null
        ? <OutboxEntry>[]
        : (jsonDecode(read) as List<dynamic>)
            .map((json) => OutboxEntry.fromJson(json as Map<String, dynamic>))
            .toList();
    return queue.where((entry) => entry.status == EntryStatus.rejected).toList();
  }

  Future<int> pendingCount() async {
    final read = await _store.read(outboxStorageKey);
    final List<OutboxEntry> queue = read == null
        ? <OutboxEntry>[]
        : (jsonDecode(read) as List<dynamic>)
            .map((json) => OutboxEntry.fromJson(json as Map<String, dynamic>))
            .toList();
    return queue.where((entry) => entry.status == EntryStatus.pending).length;
  }

  Future<SyncReport>? _runningSyncFuture;

  Future<SyncReport> sync() async {
    return _runningSyncFuture ??= _executeSync().whenComplete(() {
      _runningSyncFuture = null;
    });
  }

  Future<SyncReport> _executeSync() async {
    int syncedCount = 0;
    int failedCount = 0;
    
    List<OutboxEntry> queue = await _store.read(outboxStorageKey).then((jsonString) {
      if (jsonString == null) {
        return <OutboxEntry>[];
      }
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList.map((json) => OutboxEntry.fromJson(json)).toList();
    });

    final List<OutboxEntry> pendingEntries = queue.where((entry) => entry.status == EntryStatus.pending).toList();

    for (var entry in pendingEntries) {
      try {
        final updatedAttempts = entry.attempts + 1;
        final entryWithNewAttempt = entry.copyWith(attempts: updatedAttempts);
        
        int index = queue.indexWhere((e) => e.id == entry.id);
        if (index != -1) {
          queue[index] = entryWithNewAttempt;
        }

        final response = await _client.post(
          _baseUrl.resolve('v1/outcomes'),
          headers: {
            'Content-Type': 'application/json',
            'Idempotency-Key': entry.id,
          },
          body: jsonEncode(entry.outcome.toJson()),
        );

        if (response.statusCode == 200 || response.statusCode == 201 || response.statusCode == 409) {
          syncedCount++;
          queue.removeWhere((e) => e.id == entry.id);
        } else if (response.statusCode == 400 || response.statusCode == 422) {
          failedCount++;
          int idx = queue.indexWhere((e) => e.id == entry.id);
          if (idx != -1) {
            queue[idx] = queue[idx].copyWith(
              status: EntryStatus.rejected,
              rejectionReason: response.body,
            );
          }
        } else if (response.statusCode == 401) {
          await _store.write(outboxStorageKey, jsonEncode(queue.map((e) => e.toJson()).toList()));
          return SyncReport(
            sent: syncedCount,
            rejected: failedCount,
            remaining: queue.where((e) => e.status == EntryStatus.pending).length,
            authRequired: true,
          );
        } else {
          await _store.write(outboxStorageKey, jsonEncode(queue.map((e) => e.toJson()).toList()));
          return SyncReport(
            sent: syncedCount,
            rejected: failedCount,
            remaining: queue.where((e) => e.status == EntryStatus.pending).length,
            retryAfter: retryDelay(entryWithNewAttempt.attempts),
          );
        }
      } catch (e) {
        await _store.write(outboxStorageKey, jsonEncode(queue.map((e) => e.toJson()).toList()));
        return SyncReport(
          sent: syncedCount,
          rejected: failedCount,
          remaining: queue.where((e) => e.status == EntryStatus.pending).length,
          retryAfter: retryDelay(entry.attempts + 1),
        );
      }
    }

    await _store.write(outboxStorageKey, jsonEncode(queue.map((entry) => entry.toJson()).toList()));

    return SyncReport(
      sent: syncedCount,
      rejected: failedCount,
      remaining: queue.where((entry) => entry.status == EntryStatus.pending).length,
    );
  }
}