import 'dart:io';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../../core/i18n/tr.dart';
import '../../../core/utils/format.dart';
import '../../documents/domain/entities/scanned_document.dart';
import '../../export/data/document_builders.dart' show PageSource;
import '../data/packet_builder.dart';
import '../domain/packet.dart';

enum PacketStatus { idle, building, done, failed }

class PacketState extends Equatable {
  const PacketState({
    this.entries = const [],
    this.settings = const PacketSettings(),
    this.status = PacketStatus.idle,
    this.result,
    this.problem,
    this.tried = false,
  });
  final List<PacketEntry> entries;
  final PacketSettings settings;
  final PacketStatus status;
  final PacketResult? result;

  /// Why the packet could not be made, as a line for the person.
  final String? problem;

  /// The person pressed the button at least once, so what is missing is shown in the fields.
  final bool tried;

  PacketState copyWith({
    List<PacketEntry>? entries,
    PacketSettings? settings,
    PacketStatus? status,
    Object? result = _keep,
    Object? problem = _keep,
    bool? tried,
  }) => PacketState(
    entries: entries ?? this.entries,
    settings: settings ?? this.settings,
    status: status ?? this.status,
    result: identical(result, _keep) ? this.result : result as PacketResult?,
    problem: identical(problem, _keep) ? this.problem : problem as String?,
    tried: tried ?? this.tried,
  );

  static const _keep = Object();

  @override
  List<Object?> get props => [
    entries.map((e) => '${e.docId}:${e.pageCount}').toList(),
    settings.title,
    settings.name,
    settings.purpose,
    settings.cover,
    settings.numbers,
    settings.limit,
    status,
    result?.path,
    result?.bytes,
    problem,
    tried,
  ];
}

typedef CoverRenderer = Future<Uint8List> Function(CoverText text, List<ContentsLine> lines, {bool letter, bool rtl});

class PacketCubit extends Cubit<PacketState> {
  PacketCubit({
    required PacketBuilder builder,
    required Future<Directory> Function() outputDir,
    required List<ScannedDocument> library,
    List<String> initial = const [],
    DateTime Function()? now,
    bool letter = false,
    bool rtl = false,
    CoverRenderer coverRenderer = renderCover,
  }) : _builder = builder,
       _outputDir = outputDir,
       _library = {for (final d in library) d.id: d},
       _now = now ?? DateTime.now,
       _letter = letter,
       _rtl = rtl,
       _cover = coverRenderer,
       super(const PacketState()) {
    addDocuments(initial);
  }

  final PacketBuilder _builder;
  final Future<Directory> Function() _outputDir;
  final Map<String, ScannedDocument> _library;
  final DateTime Function() _now;
  final bool _letter;
  final bool _rtl;
  final CoverRenderer _cover;

  void addDocuments(Iterable<String> ids) {
    final have = state.entries.map((e) => e.docId).toSet();
    final added = <PacketEntry>[];
    for (final id in ids) {
      final d = _library[id];
      if (d == null || d.pages.isEmpty || have.contains(id)) continue;
      have.add(id);
      added.add(PacketEntry(docId: id, title: d.title, pageCount: d.pages.length));
    }
    if (added.isEmpty) return;
    emit(state.copyWith(entries: [...state.entries, ...added], status: PacketStatus.idle, result: null, problem: null));
  }

  void remove(String docId) =>
      emit(state.copyWith(entries: state.entries.where((e) => e.docId != docId).toList(), status: PacketStatus.idle, result: null, problem: null));

  void move(String docId, int delta) {
    final list = [...state.entries];
    final i = list.indexWhere((e) => e.docId == docId);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= list.length) return;
    list.insert(j, list.removeAt(i));
    emit(state.copyWith(entries: list, status: PacketStatus.idle, result: null, problem: null));
  }

  void setSettings(PacketSettings settings) =>
      emit(state.copyWith(settings: settings, status: state.status == PacketStatus.building ? null : PacketStatus.idle, result: null));

  Future<void> make() async {
    if (state.status == PacketStatus.building) return;
    emit(state.copyWith(tried: true, problem: null));
    if (packetProblem(state.settings, state.entries) != null) return;
    emit(state.copyWith(status: PacketStatus.building, result: null));
    try {
      final s = state.settings;
      final entries = state.entries;
      final sources = <PageSource>[];
      for (final e in entries) {
        final pages = [..._library[e.docId]!.pages]..sort((a, b) => a.position.compareTo(b.position));
        for (final page in pages) {
          if (!File(page.imagePath).existsSync()) throw const FileSystemException('A page is missing');
          sources.add(PageSource(path: page.imagePath, width: page.width, height: page.height));
        }
      }
      final now = _now();
      Uint8List? cover;
      if (s.cover) {
        final lines = contentsLines(entries, cover: true);
        cover = await _cover(
          CoverText(
            title: s.title.trim(),
            purpose: s.purpose.trim(),
            applicant: s.name.trim().isEmpty ? '' : trf('Prepared for {name}', {'name': s.name.trim()}),
            contents: tr('Contents'),
            summary: '${trf('Documents: {docs}', {'docs': entries.length})}   ${trf('Pages: {pages}', {'pages': packetPageCount(entries, cover: true)})}',
            date: trf('Prepared on {date}', {'date': formatDate(now)}),
          ),
          lines,
          letter: _letter,
          rtl: _rtl,
        );
      }
      final dir = Directory(p.join((await _outputDir()).path, 'packets'));
      await dir.create(recursive: true);
      final result = await _builder.build(
        PacketRequest(
          pages: sources,
          outputPath: p.join(dir.path, packetFileName(s.title, now)),
          cover: cover,
          numbers: s.numbers,
          limitBytes: s.limit.bytes,
          letter: _letter,
        ),
      );
      if (!isClosed) emit(state.copyWith(status: PacketStatus.done, result: result));
    } on Object {
      if (!isClosed) {
        emit(
          state.copyWith(
            status: PacketStatus.failed,
            problem: 'The packet could not be made. Check that the documents are still on this phone, then try again.',
          ),
        );
      }
    }
  }
}
