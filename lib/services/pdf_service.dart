import 'package:universal_io/io.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:open_file/open_file.dart';
import 'package:intl/intl.dart';

class PdfService {
  /// Generate a PDF with the ripeness chart data
  Future<File?> generateRipenessChartPdf({
    required List<MapEntry<String, List<Map<String, dynamic>>>> cropData,
    required String selectedCrop,
    required String title,
    required String description,
  }) async {
    try {
      // Create a PDF document
      final pdf = pw.Document();

      // Load fonts
      final font = await PdfGoogleFonts.nunitoRegular();
      final fontBold = await PdfGoogleFonts.nunitoBold();

      // Load images
      final logoData = await rootBundle.load('assets/images/logo.png');
      final ustpData = await rootBundle.load('assets/images/USTP.jpg');

      // Create header with logos
      final header = pw.Header(
        level: 0,
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Image(
              pw.MemoryImage(logoData.buffer.asUint8List()),
              height: 60,
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(
                  title,
                  style: pw.TextStyle(font: fontBold, fontSize: 24),
                ),
                pw.SizedBox(height: 5),
                pw.Text(
                  'Crop: $selectedCrop',
                  style: pw.TextStyle(
                      font: font, fontSize: 16, color: PdfColors.grey700),
                ),
                pw.Text(
                  DateFormat('MMM dd, yyyy').format(DateTime.now()),
                  style: pw.TextStyle(
                      font: font, fontSize: 14, color: PdfColors.grey700),
                ),
              ],
            ),
            pw.Image(
              pw.MemoryImage(ustpData.buffer.asUint8List()),
              height: 60,
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
              pw.SizedBox(height: 20),
              pw.Text(description,
                  style: pw.TextStyle(font: font, fontSize: 16)),
              pw.SizedBox(height: 20),

              // Chart title
              pw.Text('Daily Ripeness Progression Chart',
                  style: pw.TextStyle(font: fontBold, fontSize: 18)),
              pw.SizedBox(height: 5),
              pw.Text('Daily ripeness progression until harvest',
                  style: pw.TextStyle(
                      font: font, fontSize: 14, color: PdfColors.grey700)),
              pw.SizedBox(height: 20),

              // Create ripeness chart
              _buildRipenessBarChart(cropData, font, fontBold),
              pw.SizedBox(height: 20),

              // Legend
              _buildRipenessLegend(font, fontBold),
              pw.SizedBox(height: 30),

              // Tabular data
              _buildRipenessDataTable(cropData, font, fontBold),
            ];
          },
          footer: (context) {
            return pw.Container(
              alignment: pw.Alignment.centerRight,
              margin: const pw.EdgeInsets.only(top: 20),
              child: pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: pw.TextStyle(
                    font: font, fontSize: 12, color: PdfColors.grey700),
              ),
            );
          },
        ),
      );

      // Save the PDF to a file
      final output = await getTemporaryDirectory();
      final file = File(
          '${output.path}/ripeness_chart_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf');
      await file.writeAsBytes(await pdf.save());

      return file;
    } catch (e) {
      debugPrint('Error generating PDFdd: $e');
      return null;
    }
  }

  /// Generate a PDF with the harvest chart data (legacy method)
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
              style: pw.TextStyle(
                  font: font, fontSize: 16, color: PdfColors.grey700),
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
              pw.Text(description,
                  style: pw.TextStyle(font: font, fontSize: 16)),
              pw.SizedBox(height: 20),

              // Chart title
              pw.Text('Estimated Days Until Harvest',
                  style: pw.TextStyle(font: fontBold, fontSize: 18)),
              pw.SizedBox(height: 5),
              pw.Text('Based on your scans',
                  style: pw.TextStyle(
                      font: font, fontSize: 14, color: PdfColors.grey700)),
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
                style: pw.TextStyle(
                    font: font, fontSize: 12, color: PdfColors.grey700),
              ),
            );
          },
        ),
      );

      // Save the PDF to a file
      final output = await getTemporaryDirectory();
      final file = File(
          '${output.path}/harvest_chart_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf');
      await file.writeAsBytes(await pdf.save());

      return file;
    } catch (e) {
      debugPrint('Error generating PDFss: $e');
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
      await Printing.sharePdf(
          bytes: await file.readAsBytes(), filename: file.path.split('/').last);
    } catch (e) {
      debugPrint('Error sharing PDF: $e');
    }
  }

  // Helper method to build the harvest bar chart in the PDF
  pw.Widget _buildHarvestBarChart(
      List<MapEntry<String, int>> entries, pw.Font font, pw.Font fontBold) {
    final maxValue = entries.isEmpty
        ? 10.0
        : entries.map((e) => e.value).reduce((a, b) => a > b ? a : b) + 2.0;
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
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(4)),
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
        pw.Text('Color Legend',
            style: pw.TextStyle(font: fontBold, fontSize: 16)),
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
  pw.Widget _buildDataTable(
      List<MapEntry<String, int>> entries, pw.Font font, pw.Font fontBold) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.all(8),
              child:
                  pw.Text('Produce Name', style: pw.TextStyle(font: fontBold)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(8),
              child: pw.Text('Days Until Harvest',
                  style: pw.TextStyle(font: fontBold)),
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
                child:
                    pw.Text('${entry.value}', style: pw.TextStyle(font: font)),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(8),
                child: pw.Text(_getStatusText(entry.value),
                    style: pw.TextStyle(font: font)),
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

  // Helper method to build the ripeness bar chart in the PDF
  pw.Widget _buildRipenessBarChart(
      List<MapEntry<String, List<Map<String, dynamic>>>> cropData,
      pw.Font font,
      pw.Font fontBold) {
    if (cropData.isEmpty) return pw.SizedBox();

    // Calculate daily ripeness progression for each instance (same logic as chart page)
    List<Map<String, dynamic>> chartData = [];
    for (var instance in cropData) {
      final data = instance.value.first;
      final daysUntilHarvest = data['daysUntilHarvest'] as int;
      final currentRipenessPercentage = data['ripenessPercentage'] as double;

      // Create data points for each day from 1 to daysUntilHarvest
      for (int day = 1; day <= daysUntilHarvest; day++) {
        // Calculate ripeness percentage for this specific day
        final ripenessForDay = _calculateRipenessForDay(
            currentRipenessPercentage, day, daysUntilHarvest);

        // Determine ripeness status based on percentage
        String ripenessStatus =
            _getRipenessStatus(ripenessForDay, daysUntilHarvest - day);

        chartData.add({
          'day': day,
          'ripenessStatus': ripenessStatus,
          'ripenessPercentage': ripenessForDay,
          'daysUntilHarvest': daysUntilHarvest,
          'instanceName': instance.key,
        });
      }
    }

    final barWidth = 8.0; // Smaller bars for daily data
    final chartHeight = 300.0;
    final chartWidth = 500.0;
    final padding = 40.0;
    final maxBarsToShow = 30; // Limit bars to prevent overcrowding

    // If we have too many bars, sample them
    List<Map<String, dynamic>> displayData = chartData;
    if (chartData.length > maxBarsToShow) {
      final step = (chartData.length / maxBarsToShow).ceil();
      displayData = List.generate(maxBarsToShow, (index) {
        final originalIndex = index * step;
        return chartData[originalIndex.clamp(0, chartData.length - 1)];
      });
    }

    return pw.Container(
      height: chartHeight + padding * 2,
      width: chartWidth,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
      ),
      child: pw.Stack(
        children: [
          // Y-axis labels (0, 20, 40, 60, 80, 100)
          pw.Positioned(
            left: 0,
            top: padding,
            child: pw.Container(
              width: 30,
              height: chartHeight,
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('100', style: pw.TextStyle(font: font, fontSize: 10)),
                  pw.Text('80', style: pw.TextStyle(font: font, fontSize: 10)),
                  pw.Text('60', style: pw.TextStyle(font: font, fontSize: 10)),
                  pw.Text('40', style: pw.TextStyle(font: font, fontSize: 10)),
                  pw.Text('20', style: pw.TextStyle(font: font, fontSize: 10)),
                  pw.Text('0', style: pw.TextStyle(font: font, fontSize: 10)),
                ],
              ),
            ),
          ),

          // Grid lines
          pw.Positioned(
            left: 30,
            top: padding,
            child: pw.Container(
              width: chartWidth - 60,
              height: chartHeight,
              child: pw.Column(
                children: List.generate(6, (index) {
                  return pw.Expanded(
                    child: pw.Container(
                      decoration: pw.BoxDecoration(
                        border: pw.Border(
                          bottom: pw.BorderSide(
                            color: PdfColors.grey300,
                            width: 0.5,
                            style: pw.BorderStyle.dashed,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),

          // Bars
          pw.Positioned(
            left: 30,
            top: padding,
            child: pw.Container(
              width: chartWidth - 60,
              height: chartHeight,
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: List.generate(displayData.length, (index) {
                  final data = displayData[index];
                  final ripenessPercentage =
                      data['ripenessPercentage'] as double;
                  final ripenessStatus = data['ripenessStatus'] as String;

                  final barHeight = (ripenessPercentage / 100) * chartHeight;

                  return pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.end,
                    children: [
                      pw.Container(
                        height: barHeight,
                        width: barWidth,
                        decoration: pw.BoxDecoration(
                          color: _getPdfColorForRipenessStatus(ripenessStatus),
                          borderRadius:
                              const pw.BorderRadius.all(pw.Radius.circular(4)),
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),

          // X-axis labels (Day numbers)
          pw.Positioned(
            left: 30,
            top: padding + chartHeight + 5,
            child: pw.Container(
              width: chartWidth - 60,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: List.generate(displayData.length, (index) {
                  final data = displayData[index];
                  final day = data['day'] as int;

                  // Only show every 5th day label to avoid overcrowding
                  if (day % 5 == 0 || day == 1) {
                    return pw.Container(
                      width: barWidth + 10,
                      child: pw.Text(
                        '$day',
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(font: font, fontSize: 8),
                      ),
                    );
                  } else {
                    return pw.Container(width: barWidth + 10);
                  }
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper method to build the ripeness legend in the PDF
  pw.Widget _buildRipenessLegend(pw.Font font, pw.Font fontBold) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Ripeness Status Legend',
            style: pw.TextStyle(font: fontBold, fontSize: 16)),
        pw.SizedBox(height: 10),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
          children: [
            _buildLegendItem('Not Yet Ready (0-69%)', PdfColors.red800, font),
            _buildLegendItem('Almost Ready (70-99%)', PdfColors.amber, font),
            _buildLegendItem('Ready to Harvest (100%)', PdfColors.green, font),
          ],
        ),
      ],
    );
  }

  // Helper method to build a ripeness data table in the PDF
  pw.Widget _buildRipenessDataTable(
      List<MapEntry<String, List<Map<String, dynamic>>>> cropData,
      pw.Font font,
      pw.Font fontBold) {
    if (cropData.isEmpty) return pw.SizedBox();

    // Get the first instance for summary data
    final firstInstance = cropData.first.value.first;
    debugPrint('First instance data: $firstInstance');
    final ripenessPercentage = firstInstance['ripenessPercentage'] as double;
    final daysUntilHarvest = firstInstance['daysUntilHarvest'] as int;

    // Safely handle createdAt and harvestDate which may be null, DateTime,
    // Firestore Timestamp (has toDate()), int (ms since epoch), or String.
    // Try multiple common keys including values inside a provided 'raw' map.
    final dynamic raw = firstInstance['raw'];
    dynamic scanRaw = firstInstance['timestamp'];
    dynamic harvestRaw = firstInstance['harvestDate'];

    if (scanRaw == null && raw is Map) {
      scanRaw = raw['timestamp'] ??
          raw['createdAt'] ??
          raw['created_at'] ??
          raw['scanDate'] ??
          raw['scannedAt'] ??
          raw['uploadedAt'];
    }

    if (harvestRaw == null && raw is Map) {
      harvestRaw = raw['harvestDate'] ?? raw['harvest_date'] ?? raw['expectedHarvest'];
    }

    DateTime? scanDateTime;
    DateTime? harvestDateTime;
    debugPrint('scanRaw: $scanRaw, harvestRaw: $harvestRaw');
    // Try to normalize scanRaw to DateTime
    if (scanRaw is DateTime) {
      scanDateTime = scanRaw;
    } else if (scanRaw is int) {
      // treat as milliseconds since epoch
      scanDateTime = DateTime.fromMillisecondsSinceEpoch(scanRaw);
    } else if (scanRaw is String) {
      scanDateTime = DateTime.tryParse(scanRaw);
    } else if (scanRaw != null) {
      // Try to handle Firestore Timestamp by calling toDate() if available
      try {
        final maybeDate = (scanRaw as dynamic).toDate();
        if (maybeDate is DateTime) scanDateTime = maybeDate;
      } catch (_) {
        // ignore
      }
    }

    // Try to normalize harvestRaw to DateTime
    if (harvestRaw is DateTime) {
      harvestDateTime = harvestRaw;
    } else if (harvestRaw is int) {
      harvestDateTime = DateTime.fromMillisecondsSinceEpoch(harvestRaw);
    } else if (harvestRaw is String) {
      harvestDateTime = DateTime.tryParse(harvestRaw);
    } else if (harvestRaw != null) {
      try {
        final maybeDate = (harvestRaw as dynamic).toDate();
        if (maybeDate is DateTime) harvestDateTime = maybeDate;
      } catch (_) {
        // ignore
      }
    }

    String scanDateStr = 'N/A';
    String harvestDateStr = 'N/A';

    if (scanDateTime != null) {
      scanDateStr = DateFormat('MM/dd/yyyy').format(scanDateTime);
    }

    if (harvestDateTime != null) {
      harvestDateStr = DateFormat('MM/dd/yyyy').format(harvestDateTime);
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Summary Information',
            style: pw.TextStyle(font: fontBold, fontSize: 16)),
        pw.SizedBox(height: 10),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300),
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.all(8),
                  child:
                      pw.Text('Property', style: pw.TextStyle(font: fontBold)),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Text('Value', style: pw.TextStyle(font: fontBold)),
                ),
              ],
            ),
            pw.TableRow(
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Text('Current Ripeness',
                      style: pw.TextStyle(font: font)),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Text('${ripenessPercentage.toStringAsFixed(1)}%',
                      style: pw.TextStyle(font: font)),
                ),
              ],
            ),
            pw.TableRow(
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Text('Days Until Harvest',
                      style: pw.TextStyle(font: font)),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Text('$daysUntilHarvest days',
                      style: pw.TextStyle(font: font)),
                ),
              ],
            ),
            pw.TableRow(
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Text('Scan Date', style: pw.TextStyle(font: font)),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Text(scanDateStr, style: pw.TextStyle(font: font)),
                ),
              ],
            ),
            pw.TableRow(
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.all(8),
                  child:
                      pw.Text('Harvest Date', style: pw.TextStyle(font: font)),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(8),
                  child:
                      pw.Text(harvestDateStr, style: pw.TextStyle(font: font)),
                ),
              ],
            ),
            pw.TableRow(
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Text('Status', style: pw.TextStyle(font: font)),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Text(
                      _getRipenessStatusText(
                          ripenessPercentage, daysUntilHarvest),
                      style: pw.TextStyle(font: font)),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // Helper method to get color for ripeness percentage
  PdfColor _getPdfColorForRipeness(double ripenessPercentage) {
    if (ripenessPercentage >= 100) return PdfColors.orange; // Ready to Harvest
    if (ripenessPercentage >= 70) return PdfColors.amber; // Almost Ready
    return PdfColors.green900; // Not Yet Ready
  }

  // Helper method to get ripeness status text
  String _getRipenessStatusText(
      double ripenessPercentage, int daysUntilHarvest) {
    if (ripenessPercentage >= 100 || daysUntilHarvest <= 0) {
      return 'Ready to Harvest';
    } else if (ripenessPercentage >= 70 || daysUntilHarvest <= 3) {
      return 'Almost Ready';
    } else {
      return 'Not Yet Ready';
    }
  }

  // Helper method to calculate ripeness for a specific day (same logic as chart page)
  double _calculateRipenessForDay(
      double currentRipeness, int day, int totalDays) {
    // Calculate how much ripeness should increase per day
    // Start from current ripeness and reach 100% by harvest day
    final remainingRipeness = 100.0 - currentRipeness;
    final ripenessIncreasePerDay = remainingRipeness / totalDays;

    // Calculate ripeness for this specific day
    final ripenessForDay = currentRipeness + (ripenessIncreasePerDay * day);

    // Ensure it doesn't exceed 100%
    return ripenessForDay.clamp(0.0, 100.0);
  }

  // Helper method to get ripeness status (same logic as chart page)
  String _getRipenessStatus(double ripenessPercentage, int daysUntilHarvest) {
    if (ripenessPercentage >= 100 || daysUntilHarvest <= 0) {
      return 'Ready to Harvest';
    } else if (ripenessPercentage >= 70 || daysUntilHarvest <= 3) {
      return 'Almost Ready';
    } else {
      return 'Not Yet Ready';
    }
  }

  // Helper method to get color for ripeness status (matching chart page colors)
  PdfColor _getPdfColorForRipenessStatus(String ripenessStatus) {
    switch (ripenessStatus) {
      case 'Not Yet Ready':
        return PdfColors.red800; // Red - matches Color(0xFFD32F2F)
      case 'Almost Ready':
        return PdfColors.amber; // Amber - matches Color(0xFFFFB300)
      case 'Ready to Harvest':
        return PdfColors.green; // Green - matches Color(0xFF4CAF50)
      default:
        return PdfColors.green900;
    }
  }
}
