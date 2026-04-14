/// Transfer statistics and ETA calculation.
///
/// Tracks bytes transferred, transfer rate, and estimated time remaining.
library;

/// Tracks transfer progress and computes statistics.
class TransferStats {
  final Stopwatch _stopwatch = Stopwatch();
  int _totalBytes = 0;
  int _transferredBytes = 0;
  int _totalItems = 0;
  int _completedItems = 0;

  /// Rolling window for rate calculation (last N samples).
  final List<_RateSample> _samples = [];
  static const _maxSamples = 20;
  static const _sampleInterval = Duration(milliseconds: 500);
  DateTime _lastSample = DateTime.now();

  /// Start tracking.
  void start({required int totalBytes, required int totalItems}) {
    _totalBytes = totalBytes;
    _totalItems = totalItems;
    _transferredBytes = 0;
    _completedItems = 0;
    _samples.clear();
    _stopwatch
      ..reset()
      ..start();
  }

  /// Record bytes transferred.
  void addBytes(int bytes) {
    _transferredBytes += bytes;
    _recordSample();
  }

  /// Record an item completed.
  void completeItem() {
    _completedItems++;
  }

  /// Elapsed time since start.
  Duration get elapsed => _stopwatch.elapsed;

  /// Total bytes to transfer.
  int get totalBytes => _totalBytes;

  /// Bytes transferred so far.
  int get transferredBytes => _transferredBytes;

  /// Completion fraction (0.0 to 1.0).
  double get progress {
    if (_totalBytes == 0) {
      return _totalItems == 0 ? 1.0 : _completedItems / _totalItems;
    }
    return _transferredBytes / _totalBytes;
  }

  /// Current transfer rate in bytes/second (rolling average).
  double get bytesPerSecond {
    if (_samples.length < 2) {
      final secs = _stopwatch.elapsedMilliseconds / 1000;
      return secs > 0 ? _transferredBytes / secs : 0;
    }
    final first = _samples.first;
    final last = _samples.last;
    final dt = last.time.difference(first.time).inMilliseconds / 1000;
    if (dt <= 0) return 0;
    return (last.bytes - first.bytes) / dt;
  }

  /// Human-readable transfer rate.
  String get rateString {
    final rate = bytesPerSecond;
    if (rate < 1024) return '${rate.toStringAsFixed(0)} B/s';
    if (rate < 1024 * 1024) return '${(rate / 1024).toStringAsFixed(1)} KB/s';
    return '${(rate / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  /// Estimated time remaining.
  Duration? get eta {
    final rate = bytesPerSecond;
    if (rate <= 0) return null;
    final remaining = _totalBytes - _transferredBytes;
    if (remaining <= 0) return Duration.zero;
    return Duration(seconds: (remaining / rate).ceil());
  }

  /// Human-readable ETA.
  String get etaString {
    final e = eta;
    if (e == null) return '--:--';
    if (e.inHours > 0) {
      return '${e.inHours}h ${e.inMinutes.remainder(60)}m';
    }
    if (e.inMinutes > 0) {
      return '${e.inMinutes}m ${e.inSeconds.remainder(60)}s';
    }
    return '${e.inSeconds}s';
  }

  /// Human-readable transferred / total.
  String get progressString {
    return '${_formatBytes(_transferredBytes)} / ${_formatBytes(_totalBytes)}';
  }

  /// Items progress.
  String get itemsString => '$_completedItems / $_totalItems items';

  void _recordSample() {
    final now = DateTime.now();
    if (now.difference(_lastSample) < _sampleInterval) return;
    _lastSample = now;
    _samples.add(_RateSample(now, _transferredBytes));
    if (_samples.length > _maxSamples) {
      _samples.removeAt(0);
    }
  }

  /// Stop tracking.
  void stop() {
    _stopwatch.stop();
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

class _RateSample {
  final DateTime time;
  final int bytes;
  _RateSample(this.time, this.bytes);
}
