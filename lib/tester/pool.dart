import 'dart:async';
import 'dart:collection';

/// Runs async jobs with a concurrency limit (default 16 in the tester).
class TaskPool {
  final int limit;
  int _running = 0;
  final _queue = Queue<Completer<void>>();
  bool _cancelled = false;

  TaskPool(this.limit) : assert(limit > 0);

  bool get cancelled => _cancelled;

  Future<T?> run<T>(Future<T> Function() job) async {
    if (_cancelled) return null;
    if (!_acquire()) {
      final c = Completer<void>();
      _queue.add(c);
      // The releasing task reserves the slot for us, so the freed capacity is
      // never observable: a task started concurrently used to see `_running`
      // below the limit and push us over it.
      await c.future;
      if (_cancelled) return null;
    }
    try {
      return await job();
    } finally {
      _release();
    }
  }

  /// Reserves a slot, or returns false when the limit is already reached.
  bool _acquire() {
    if (_running >= limit) return false;
    _running++;
    return true;
  }

  /// Frees a slot, handing it straight to the next queued task if there is one.
  void _release() {
    if (_queue.isNotEmpty) {
      _queue.removeFirst().complete();
      return;
    }
    _running--;
  }

  void cancel() {
    _cancelled = true;
    while (_queue.isNotEmpty) {
      _queue.removeFirst().complete();
    }
  }
}
