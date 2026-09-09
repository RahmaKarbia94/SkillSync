import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class ReportExportException implements Exception {
  const ReportExportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ReportGenerator {
  const ReportGenerator({required this.baseUrl, required this.token});

  final String baseUrl;
  final String token;

  Future<Map<String, dynamic>> _fetchExportData(String sessionId) async {
    final uri = Uri.parse('$baseUrl/api/v1/evaluations/$sessionId/export');
    final response = await http.get(uri, headers: {'Authorization': 'Bearer $token'});

    if (response.statusCode != 200) {
      throw ReportExportException('Failed to fetch report data (status ${response.statusCode})');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  String _fmt(dynamic value, {String fallback = 'N/A'}) {
    if (value == null) return fallback;
    if (value is String && value.isEmpty) return fallback;
    return value.toString();
  }

  String _fmtScore(dynamic value) {
    if (value == null) return 'N/A';
    final num? n = value is num ? value : num.tryParse(value.toString());
    if (n == null) return 'N/A';
    return n.toStringAsFixed(0);
  }

  String _fmtDate(String? iso) {
    if (iso == null) return 'N/A';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return 'N/A';
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Fetches the export payload and lays out a branded A4 PDF. The heavy
  /// widget-tree/rasterization work happens inside `pw.Document.save()`,
  /// which the `pdf` package runs off the UI isolate's frame scheduler —
  /// awaited here rather than blocking, so the calling screen stays
  /// responsive while the document compiles.
  Future<Uint8List> generate(String sessionId) async {
    final data = await _fetchExportData(sessionId);

    final fillerWords = data['filler_words'] as Map<String, dynamic>? ?? {};
    final logicPacing = data['logic_pacing'] as Map<String, dynamic>? ?? {};
    final sentiment = data['sentiment'] as Map<String, dynamic>? ?? {};
    final flags = (data['flags'] as List<dynamic>? ?? []).map((f) => f.toString()).toList();

    final overallScore = _fmtScore(data['overall_score']);
    final pacingScore = _fmtScore(logicPacing['score']);

    String clarityScore = 'N/A';
    final density = fillerWords['density_per_100_words'];
    if (density is num) {
      clarityScore = _fmtScore((100 - density).clamp(0, 100));
    }

    String confidenceScore = 'N/A';
    final confidenceRaw = sentiment['confidence'];
    if (confidenceRaw is num) {
      confidenceScore = _fmtScore((confidenceRaw * 100).clamp(0, 100));
    }

    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 48),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'SkillSync — Assessment Report',
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromInt(0xFF6C63FF),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Divider(color: PdfColors.grey300, thickness: 1),
            pw.SizedBox(height: 12),
          ],
        ),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 12),
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ),
        build: (context) => [
          _buildHeaderSection(
            candidateName: _fmt(data['candidate_name']),
            candidateEmail: _fmt(data['candidate_email']),
            assessmentDate: _fmtDate(data['assessment_date'] as String?),
            sessionId: _fmt(data['session_id']),
            overallScore: overallScore,
          ),
          pw.SizedBox(height: 20),
          _buildMetricsSection(
            pacing: pacingScore,
            clarity: clarityScore,
            confidence: confidenceScore,
            sentimentOverall: _fmt(sentiment['overall']),
            emotionalTone: _fmt(sentiment['emotional_tone']),
          ),
          pw.SizedBox(height: 20),
          _buildQualitativeSection(
            summary: _fmt(data['summary'], fallback: 'No summary available for this assessment.'),
            flags: flags,
          ),
          pw.SizedBox(height: 20),
          _buildTranscriptSection(_fmt(data['transcript'], fallback: 'No transcript available.')),
        ],
      ),
    );

    return doc.save();
  }

  pw.Widget _sectionTitle(String text) {
    return pw.Text(
      text,
      style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF141826)),
    );
  }

  pw.Widget _buildHeaderSection({
    required String candidateName,
    required String candidateEmail,
    required String assessmentDate,
    required String sessionId,
    required String overallScore,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(candidateName, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 2),
                pw.Text(candidateEmail, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                pw.SizedBox(height: 8),
                pw.Text('Assessment Date: $assessmentDate', style: const pw.TextStyle(fontSize: 10)),
                pw.Text('Session ID: $sessionId', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
              ],
            ),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromInt(0xFF6C63FF),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              children: [
                pw.Text(
                  '$overallScore / 100',
                  style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                ),
                pw.Text('Overall Score', style: const pw.TextStyle(fontSize: 8, color: PdfColors.white)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildMetricsSection({
    required String pacing,
    required String clarity,
    required String confidence,
    required String sentimentOverall,
    required String emotionalTone,
  }) {
    pw.Widget metricTile(String label, String value) {
      return pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.all(10),
          margin: const pw.EdgeInsets.symmetric(horizontal: 4),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(
            children: [
              pw.Text(value, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 2),
              pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
            ],
          ),
        ),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('Soft Skills Metrics'),
        pw.SizedBox(height: 8),
        pw.Row(
          children: [
            metricTile('Pacing', pacing),
            metricTile('Clarity', clarity),
            metricTile('Confidence', confidence),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Text('Sentiment: $sentimentOverall — $emotionalTone', style: const pw.TextStyle(fontSize: 10)),
      ],
    );
  }

  pw.Widget _buildQualitativeSection({required String summary, required List<String> flags}) {
    final children = <pw.Widget>[
      _sectionTitle('Qualitative Feedback'),
      pw.SizedBox(height: 8),
      pw.Text(summary, style: const pw.TextStyle(fontSize: 10)),
    ];

    if (flags.isNotEmpty) {
      children.add(pw.SizedBox(height: 10));
      children.add(pw.Text('Flagged for Attention:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)));
      children.add(pw.SizedBox(height: 4));
      for (final flag in flags) {
        children.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 2),
            child: pw.Text('•  $flag', style: const pw.TextStyle(fontSize: 10)),
          ),
        );
      }
    }

    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: children);
  }

  pw.Widget _buildTranscriptSection(String transcript) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('Transcript Excerpt'),
        pw.SizedBox(height: 8),
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey50,
            border: pw.Border.all(color: PdfColors.grey300),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Text(transcript, style: const pw.TextStyle(fontSize: 9.5)),
        ),
      ],
    );
  }
}