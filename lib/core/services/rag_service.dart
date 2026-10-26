import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import '../config/api_keys.dart';
import '../models/user_profile.dart';
import 'schedule_service.dart';

/// Pre-computed text chunk with 768-dimensional Matryoshka embeddings (gemini-embedding-001).
class RagChunk {
  final String id;
  final String source;
  final String category;
  final String? specialization;
  final int? year;
  final int? group;
  final String text;
  final List<double> embedding;

  RagChunk({
    required this.id,
    required this.source,
    required this.category,
    required this.text,
    required this.embedding,
    this.specialization,
    this.year,
    this.group,
  });

  factory RagChunk.fromJson(Map<String, dynamic> j) => RagChunk(
        id: j['id'] as String,
        source: j['source'] as String,
        category: j['category'] as String,
        specialization: j['specialization'] as String?,
        year: (j['year'] as num?)?.toInt(),
        group: (j['group'] as num?)?.toInt(),
        text: j['text'] as String,
        embedding: (j['embedding'] as List).cast<num>().map((e) => e.toDouble()).toList(),
      );
}

class RagService {
  static final RagService _instance = RagService._();
  factory RagService() => _instance;
  RagService._();

  static const _embedUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-001:embedContent';
  static const _embedDims = 768;

  List<RagChunk>? _chunks;
  Future<void>? _loadFuture;

  /// Lazily loads assets/rag/chunks.json once per session.
  Future<void> ensureLoaded() {
    return _loadFuture ??= _load();
  }

  Future<void> _load() async {
    try {
      final raw = await rootBundle.loadString('assets/rag/chunks.json');
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      final loaded = list.map(RagChunk.fromJson).toList(growable: false);
      // Pre-normalize embeddings at load time to avoid O(768) per-chunk re-normalization during queries.
      for (final c in loaded) {
        final norm = _l2Normalize(c.embedding);
        for (int i = 0; i < c.embedding.length; i++) {
          c.embedding[i] = norm[i];
        }
      }
      _chunks = loaded;
      debugPrint('[RAG] loaded & normalized ${_chunks!.length} chunks');
    } catch (e) {
      debugPrint('[RAG] load failed: $e');
      _chunks = const [];
    }
  }

  /// Builds relevant RAG context for a user query to inject into Gemini's prompt.
  Future<String> buildContextForQuery(String query, {int topK = 5}) async {
    await ensureLoaded();
    final all = _chunks;
    if (all == null || all.isEmpty || query.trim().isEmpty) return '';

    final filtered = _filterForUserProfile(all);
    if (filtered.isEmpty) return '';

    final List<double>? qEmb = await _embedQuery(query);
    if (qEmb == null) return '';

    // Chunk embeddings are pre-normalized at load time; only normalize the query embedding at runtime.
    final qNorm = _l2Normalize(qEmb);

    final scored = <(RagChunk, double)>[];
    for (final c in filtered) {
      // With unit vectors, dot product equals cosine similarity.
      double dot = 0;
      for (int i = 0; i < qNorm.length && i < c.embedding.length; i++) {
        dot += qNorm[i] * c.embedding[i];
      }
      scored.add((c, dot));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    final top = scored.take(topK).where((e) => e.$2 > 0.3).toList();
    if (top.isEmpty) return '';

    final buf = StringBuffer();
    buf.writeln('Context relevant din documentele FMI Ovidius (folosește-l pentru a răspunde):');
    for (final entry in top) {
      final chunk = entry.$1;
      buf.writeln('---');
      buf.writeln('[Sursă: ${chunk.source} · ${chunk.category}'
          '${chunk.year != null ? " · an ${chunk.year} grupa ${chunk.group}" : ""}]');
      buf.writeln(chunk.text);
    }
    buf.writeln('---');
    return buf.toString();
  }

  // For schedules, match the user profile. Non-schedule categories are universal (regulations, fees, exams).
  List<RagChunk> _filterForUserProfile(List<RagChunk> all) {
    final spec = _normalizeSpec(UserProfile.specializare);
    final year = UserProfile.anul;
    final group = ScheduleService.parseGroup(UserProfile.grupa);
    return all.where((c) {
      if (c.category != 'orar') return true;
      if (spec == null || group == null) return false;
      return c.specialization == spec && c.year == year && c.group == group;
    }).toList(growable: false);
  }

  /// Normalizes free-text specialization to canonical keys ('informatica' | 'computer-science' | 'matematica-informatica').
  static String? normalizeSpec(String raw) => _normalizeSpec(raw);

  static String? _normalizeSpec(String raw) {
    if (raw.isEmpty) return null;
    final t = raw
        .toLowerCase()
        .replaceAll('ă', 'a').replaceAll('â', 'a').replaceAll('î', 'i')
        .replaceAll('ș', 's').replaceAll('ț', 't')
        .trim();
    if (t.contains('matematic') && t.contains('informatic')) return 'matematica-informatica';
    if (t.contains('computer') || t == 'cs' || t.contains('science') || t.contains('sience')) {
      return 'computer-science';
    }
    if (t.contains('informatic')) return 'informatica';
    return null;
  }

  Future<List<double>?> _embedQuery(String text) async {
    try {
      final resp = await http.post(
        Uri.parse('$_embedUrl?key=${ApiKeys.gemini}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'content': {'parts': [{'text': text}]},
          'outputDimensionality': _embedDims,
          'taskType': 'RETRIEVAL_QUERY',
        }),
      ).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) {
        debugPrint('[RAG] embed query HTTP ${resp.statusCode}: ${resp.body}');
        return null;
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final values = (data['embedding']?['values'] as List?)?.cast<num>();
      return values?.map((e) => e.toDouble()).toList();
    } catch (e) {
      debugPrint('[RAG] embed query failed: $e');
      return null;
    }
  }

  static List<double> _l2Normalize(List<double> v) {
    double sum = 0;
    for (final x in v) {
      sum += x * x;
    }
    final norm = math.sqrt(sum);
    if (norm == 0) return v;
    return v.map((x) => x / norm).toList(growable: false);
  }
}
