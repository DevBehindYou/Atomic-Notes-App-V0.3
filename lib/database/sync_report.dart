/// Which work belongs to this caller, rather than another concurrent sync.
enum SyncAttemptActivity { notStarted, started, joined, retired }

/// The Server's historical totals for one request, not a debit per HTTP retry.
class SyncOperationReport {
  const SyncOperationReport({required this.requestId, required this.instant,
    required this.recovered, this.charged, this.refunded});
  final String requestId;
  final bool instant;
  final bool recovered;
  final int? charged;
  final int? refunded;
}

/// Immutable, caller-owned observations. Unknown receipts stay unknown.
class SyncAttemptReport {
  SyncAttemptReport({required this.completed, required this.activity,
    Iterable<SyncOperationReport> operations = const [], this.errorMessage})
      : operations = List.unmodifiable(operations);
  final bool completed;
  final SyncAttemptActivity activity;
  final List<SyncOperationReport> operations;
  final String? errorMessage;

  int? _total(int? Function(SyncOperationReport) amount) {
    if (activity != SyncAttemptActivity.started ||
        operations.any((operation) => amount(operation) == null)) return null;
    return operations.fold<int>(0, (total, operation) => total + amount(operation)!);
  }

  int? get charged => _total((operation) => operation.charged);
  int? get refunded => _total((operation) => operation.refunded);
  int? get netCharge => charged == null || refunded == null ? null : charged! - refunded!;
}
