import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/scan_services.dart';
import '../domain/scanned_code.dart';

class QrScanState extends Equatable {
  const QrScanState({this.current, this.busy = false, this.notice});

  /// The code on show; the camera ignores others until it is dismissed.
  final ScannedCode? current;
  final bool busy;

  /// A line to show once, such as "No code found in that picture".
  final String? notice;

  @override
  List<Object?> get props => [current?.raw, busy, notice];
}

class QrScanCubit extends Cubit<QrScanState> {
  QrScanCubit({required ScanHistory history, required CodeImageReader reader, DateTime Function()? now})
    : _history = history,
      _reader = reader,
      _now = now ?? DateTime.now,
      super(const QrScanState());

  final ScanHistory _history;
  final CodeImageReader _reader;
  final DateTime Function() _now;

  /// Called by the camera for every frame that holds codes.
  Future<void> onDetected(List<DetectedCode> codes) async {
    if (state.current != null || state.busy) return;
    final first = codes.where((c) => c.raw.trim().isNotEmpty).firstOrNull;
    if (first == null) return;
    await _show(first);
  }

  Future<void> _show(DetectedCode code) async {
    final parsed = parseCode(code.raw, format: code.format);
    emit(QrScanState(current: parsed));
    await _history.add(code, _now());
  }

  Future<void> scanImage(String path) async {
    if (state.busy) return;
    emit(const QrScanState(busy: true));
    final found = await _reader.read(path);
    if (isClosed) return;
    final first = found.where((c) => c.raw.trim().isNotEmpty).firstOrNull;
    if (first == null) {
      emit(const QrScanState(notice: 'No QR code or barcode was found in that picture.'));
      return;
    }
    await _show(first);
  }

  void dismiss() {
    if (state.current != null || state.notice != null) emit(const QrScanState());
  }
}

class QrHistoryState extends Equatable {
  const QrHistoryState({this.items = const [], this.loaded = false, this.enabled = true});
  final List<ScanRecord> items;
  final bool loaded;
  final bool enabled;

  @override
  List<Object?> get props => [items.map((r) => '${r.raw}|${r.at.millisecondsSinceEpoch}').toList(), loaded, enabled];
}

class QrHistoryCubit extends Cubit<QrHistoryState> {
  QrHistoryCubit(this._history) : super(const QrHistoryState());
  final ScanHistory _history;

  Future<void> load() async {
    final items = await _history.list();
    final enabled = await _history.isEnabled();
    if (!isClosed) emit(QrHistoryState(items: items, loaded: true, enabled: enabled));
  }

  Future<void> delete(String raw) async {
    await _history.delete(raw);
    await load();
  }

  Future<void> clear() async {
    await _history.clear();
    await load();
  }

  Future<void> setEnabled(bool value) async {
    await _history.setEnabled(value);
    await load();
  }
}
