import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    throw ArgumentError(
        'Usage: dart run tool/generate_chat_demo_pdf.dart <output>');
  }
  final document = pw.Document();
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(42),
      build: (_) => [
        pw.Text(
          'Kaizen School Fee Schedule',
          style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.Text('Academic year 2026 · Term 2'),
        pw.SizedBox(height: 28),
        pw.TableHelper.fromTextArray(
          headers: const ['Item', 'Amount (KES)'],
          data: const [
            ['Tuition', '48,000'],
            ['Activity fee', '4,500'],
            ['Technology levy', '2,000'],
            ['Transport (optional)', '12,000'],
          ],
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          cellPadding: const pw.EdgeInsets.all(10),
        ),
        pw.SizedBox(height: 24),
        pw.Text(
          'For support, reference ticket DGKSL-103 when contacting the school office.',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
      ],
    ),
  );
  await File(arguments.single).writeAsBytes(await document.save());
}
