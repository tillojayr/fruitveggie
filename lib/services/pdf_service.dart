import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:open_file/open_file.dart';
import 'package:intl/intl.dart';

class PdfService {
  /// Generate a PDF with the harvest chart data
  Future<File?> generateHarvestChartPdf({
    required Map<String, int> cropHarvestDays,
    required String title,
    required String description,
  }) async {
    try {
      // Create a PDF document
      final pdf = pw.Document();
      
      // Load font
      final font = await PdfGoogleFonts.nunitoRegular();
      final fontBold = await PdfGoogleFonts.nunitoBold();
      
      // Create a sorted list of entries
      final entries = cropHarvestDays.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      
      // Create header
      final header = pw.Header(
        level: 0,
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(title, style: pw.TextStyle(font: fontBold, fontSize: 24)),
            pw.Text(
              DateFormat('MMM dd, yyyy').format(DateTime.now()),
              style: pw.TextStyle(font: font, fontSize: 16, color: PdfColors.grey700),
            ),
          ],
        ),
      );
      
      // Add content to PDF
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return [
              header,
              pw.SizedBox(height: 8),
              pw.Text(description, style: pw.TextStyle(font: font, fontSize: 16)),
              pw.SizedBox(height: 20),
              
              // Chart title
              pw.Text('Estimated Days Until Harvest',
                  style: pw.TextStyle(font: fontBold, fontSize: 18)),
              pw.SizedBox(height: 5),
              pw.Text('Based on your scans',
                  style: pw.TextStyle(font: font, fontSize: 14, color: PdfColors.grey700)),
              pw.SizedBox(height: 20),
              
              // Create chart
              _buildHarvestBarChart(entries, font, fontBold),
              pw.SizedBox(height: 20),
              
              // Legend
              _buildColorLegend(font, fontBold),
              pw.SizedBox(height: 30),
              
              // Tabular data
              _buildDataTable(entries, font, fontBold),
            ];
          },
          footer: (context) {
            return pw.Container(
              alignment: pw.Alignment.centerRight,
              margin: const pw.EdgeInsets.only(top: 20),
              child: pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: pw.TextStyle(font: font, fontSize: 12, color: PdfColors.grey700),
              ),
            );
          },
        ),
      );
      
      // Save the PDF to a file
      final output = await getTemporaryDirectory();
      final file = File('${output.path}/harvest_chart_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf');
      await file.writeAsBytes(await pdf.save());
      
      return file;
    } catch (e) {
      debugPrint('Error generating PDF: $e');
      return null;
    }
  }
  
  /// Open a PDF file
  Future<void> openPdf(File file) async {
    try {
      final result = await OpenFile.open(file.path);
      if (result.type != ResultType.done) {
        debugPrint('Could not open the file: ${result.message}');
      }
    } catch (e) {
      debugPrint('Error opening PDF: $e');
    }
  }
  
  /// Print a PDF file
  Future<void> printPdf(File file) async {
    try {
      await Printing.layoutPdf(
        onLayout: (_) => file.readAsBytes(),
      );
    } catch (e) {
      debugPrint('Error printing PDF: $e');
    }
  }
  
  /// Share the PDF file
  Future<void> sharePdf(File file) async {
    try {
      await Printing.sharePdf(bytes: await file.readAsBytes(), filename: file.path.split('/').last);
    } catch (e) {
      debugPrint('Error sharing PDF: $e');
    }
  }

  // Helper method to build the harvest bar chart in the PDF
  pw.Widget _buildHarvestBarChart(List<MapEntry<String, int>> entries, pw.Font font, pw.Font fontBold) {
    final maxValue = entries.isEmpty ? 10.0 : entries.map((e) => e.value).reduce((a, b) => a > b ? a : b) + 2.0;
    final barWidth = 40.0;
    final chartHeight = 300.0;
    final chartWidth = entries.length * (barWidth + 20.0);
    
    return pw.Container(
      height: chartHeight,
      width: chartWidth,
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: List.generate(entries.length, (index) {
          final entry = entries[index];
          final barHeight = (entry.value / maxValue) * chartHeight;
          
          return pw.Column(
            children: [
              pw.Container(
                height: barHeight,
                width: barWidth,
                decoration: pw.BoxDecoration(
                  color: _getPdfColorForValue(entry.value),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
              ),
              pw.SizedBox(height: 5),
              pw.Container(
                width: barWidth + 20,
                child: pw.Text(
                  entry.key,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: font, fontSize: 10),
                ),
              ),
              pw.Text(
                '${entry.value} days',
                style: pw.TextStyle(font: fontBold, fontSize: 10),
              ),
            ],
          );
        }),
      ),
    );
  }
  
  // Helper method to build the color legend in the PDF
  pw.Widget _buildColorLegend(pw.Font font, pw.Font fontBold) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Color Legend', style: pw.TextStyle(font: fontBold, fontSize: 16)),
        pw.SizedBox(height: 10),
        pw.Wrap(
          spacing: 20,
          runSpacing: 10,
          children: [
            _buildLegendItem('Ready', PdfColors.deepOrange800, font),
            _buildLegendItem('1-3 Days', PdfColors.orange, font),
            _buildLegendItem('4-5 Days', PdfColors.amber, font),
            _buildLegendItem('6-7 Days', PdfColors.lightGreen, font),
            _buildLegendItem('8-10 Days', PdfColors.green, font),
            _buildLegendItem('10+ Days', PdfColors.green900, font),
          ],
        ),
      ],
    );
  }
  
  // Helper method to build a legend item in the PDF
  pw.Widget _buildLegendItem(String label, PdfColor color, pw.Font font) {
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Container(
          width: 16,
          height: 16,
          decoration: pw.BoxDecoration(
            color: color,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
        ),
        pw.SizedBox(width: 5),
        pw.Text(label, style: pw.TextStyle(font: font, fontSize: 12)),
      ],
    );
  }
  
  // Helper method to build a data table in the PDF
  pw.Widget _buildDataTable(List<MapEntry<String, int>> entries, pw.Font font, pw.Font fontBold) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.all(8),
              child: pw.Text('Produce Name', style: pw.TextStyle(font: fontBold)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(8),
              child: pw.Text('Days Until Harvest', style: pw.TextStyle(font: fontBold)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(8),
              child: pw.Text('Status', style: pw.TextStyle(font: fontBold)),
            ),
          ],
        ),
        ...entries.map((entry) {
          return pw.TableRow(
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.all(8),
                child: pw.Text(entry.key, style: pw.TextStyle(font: font)),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(8),
                child: pw.Text('${entry.value}', style: pw.TextStyle(font: font)),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(8),
                child: pw.Text(_getStatusText(entry.value), style: pw.TextStyle(font: font)),
              ),
            ],
          );
        }).toList(),
      ],
    );
  }
  
  // Helper method to get color for value
  PdfColor _getPdfColorForValue(int value) {
    if (value <= 0) return PdfColors.deepOrange800; // Overripe or Ready
    if (value <= 3) return PdfColors.orange; // Very Soon
    if (value <= 5) return PdfColors.amber; // Soon
    if (value <= 7) return PdfColors.lightGreen; // Medium
    if (value <= 10) return PdfColors.green; // Further
    return PdfColors.green900; // Far
  }
  
  // Helper method to get status text
  String _getStatusText(int value) {
    if (value <= 0) return 'Ready for harvest';
    if (value <= 3) return 'Very soon';
    if (value <= 5) return 'Soon';
    if (value <= 7) return 'Medium term';
    if (value <= 10) return 'Longer term';
    return 'Far future';
  }
}
