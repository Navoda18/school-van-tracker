import 'dart:convert';
import 'dart:typed_data';
import 'package:cross_file/cross_file.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'absence_rules.dart';

class LogExport {
  static const _headers = [
    'Date', 'Session', 'Child', 'School', 'Status', 'Boarded', 'Dropped'
  ];

  static String _status(String s) {
    switch (s) {
      case 'coming':
        return 'Coming';
      case 'absent_parent':
        return 'Absent (parent)';
      case 'absent_driver':
        return 'Not coming';
      default:
        return 'Not marked';
    }
  }

  static String _time(dynamic v) {
    if (v == null) return '';
    final d = DateTime.parse(v as String).toLocal();
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  static List<List<String>> _table(List<Map<String, dynamic>> rows) => [
        for (final r in rows)
          [
            r['day'] as String,
            sessionLabel(r['session'] as String),
            r['student_name'] as String,
            (r['school'] as String?) ?? '',
            _status(r['status'] as String),
            _time(r['boarded_at']),
            _time(r['dropped_at']),
          ]
      ];

  // Quotes cells, and stops typed names like "=1+1" running as spreadsheet formulas
  static String _csvCell(String v) {
    var t = v;
    if (t.isNotEmpty && '=+-@'.contains(t[0])) t = "'$t";
    if (t.contains(',') || t.contains('"') || t.contains('\n')) {
      t = '"${t.replaceAll('"', '""')}"';
    }
    return t;
  }

  static Future<void> shareCsv(
      List<Map<String, dynamic>> rows, String from, String to) async {
    final buf = StringBuffer('\uFEFF'); // lets Excel read Sinhala and Tamil names
    buf.writeln(_headers.join(','));
    for (final r in _table(rows)) {
      buf.writeln(r.map(_csvCell).join(','));
    }
    final bytes = Uint8List.fromList(utf8.encode(buf.toString()));
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(bytes, mimeType: 'text/csv')],
      fileNameOverrides: ['attendance_${from}_to_$to.csv'],
      subject: 'Attendance log $from to $to',
    ));
  }

  static pw.Widget _cell(String t, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.all(3),
        child: pw.Text(t,
            style: pw.TextStyle(
                fontSize: 8,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      );

  static Future<void> sharePdf(
      List<Map<String, dynamic>> rows, String from, String to) async {
    final doc = pw.Document();
    final table = _table(rows);
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      maxPages: 300,
      header: (ctx) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Text('Attendance log: $from to $to',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      ),
      build: (ctx) => [
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.amber200),
              children: [for (final h in _headers) _cell(h, bold: true)],
            ),
            for (final r in table)
              pw.TableRow(children: [for (final v in r) _cell(v)]),
          ],
        ),
      ],
    ));
    final bytes = await doc.save();
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(bytes, mimeType: 'application/pdf')],
      fileNameOverrides: ['attendance_${from}_to_$to.pdf'],
      subject: 'Attendance log $from to $to',
    ));
  }
}