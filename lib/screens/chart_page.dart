import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';
import '../services/pdf_service.dart';
import 'dart:io';
import '../services/pdf_service.dart';

class ChartPage extends StatefulWidget {
  final Function() onRefresh;
  // Optional callback to request navigation to the camera tab in the parent
  final VoidCallback? onNavigateToCamera;

  const ChartPage({
    super.key,
    required this.onRefresh,
    this.onNavigateToCamera,
  });

  @override
  State<ChartPage> createState() => _ChartPageState();
}

class _ChartPageState extends State<ChartPage> {
  bool _isLoading = true;
  bool _isExporting = false;
  Map<String, int> _cropHarvestDays = {};
  List<String> _availableCrops = [];
  String? _selectedCrop;
  Map<String, List<Map<String, dynamic>>> _cropData = {};
  List<Color> gradientColors = [
    const Color(0xFF2E7D32), // Dark Green
    const Color(0xFF4CAF50), // Medium Green
    const Color(0xFF8BC34A), // Light Green
    const Color(0xFFFFB300), // Amber
    const Color(0xFFFF9800), // Orange
    const Color(0xFFE65100), // Deep Orange
  ];
  final PdfService _pdfService = PdfService();

  @override
  void initState() {
    super.initState();
    _fetchCropHarvestData();
  }

  Future<void> _fetchCropHarvestData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      final userId = currentUser?.uid;

      if (userId != null) {
        // Get all scans from Firestore
        final QuerySnapshot result = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('reminders')
            .where('isDismissed', isEqualTo: false)
            .get();

        if (result.docs.isNotEmpty) {
          Map<String, List<Map<String, dynamic>>> cropDataMap = {};
          Set<String> cropNames = {};

          debugPrint('Data fetched: ${result.docs.length} reminders');
          for (var doc in result.docs) {
            final scanData = doc.data() as Map<String, dynamic>;

            debugPrint('All data for scan ${doc.id}: $scanData');
            String produceName = scanData['produceType'] ?? 'Unknown';
            int daysUntilHarvest = _getDaysUntilHarvest(scanData);
            double ripenessPercentage = _getRipenessPercentage(scanData);

            // Create unique key for each crop instance
            String key = produceName;
            int counter = 1;
            while (cropDataMap.containsKey(key)) {
              key = '$produceName#$counter';
              counter++;
            }

            debugPrint(
                'Processing scan: $key, Days until harvest: $daysUntilHarvest, Ripeness: $ripenessPercentage%');

            cropDataMap[key] = [
              {
                'produceName': produceName,
                'daysUntilHarvest': daysUntilHarvest,
                'ripenessPercentage': ripenessPercentage,
                'harvestDate': scanData['harvestDate'],
                'scanId': scanData['scanId'],
              }
            ];

            cropNames.add(produceName);
          }

          debugPrint('Crop data map: $cropDataMap');
          setState(() {
            _cropData = cropDataMap;
            _availableCrops = cropNames.toList()..sort();
            _selectedCrop =
                _availableCrops.isNotEmpty ? _availableCrops.first : null;
            _isLoading = false;
          });
        } else {
          setState(() {
            _cropData = {};
            _availableCrops = [];
            _selectedCrop = null;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      print('Error fetching crop harvest data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _getProduceName(Map<String, dynamic> scanData) {
    // Try different fields that might contain the produce name
    if (scanData.containsKey('name')) {
      return _capitalizeFirstLetter(scanData['name'].toString());
    } else if (scanData.containsKey('produceName')) {
      return _capitalizeFirstLetter(scanData['produceName'].toString());
    } else if (scanData.containsKey('produceType')) {
      return _capitalizeFirstLetter(scanData['produceType'].toString());
    } else if (scanData.containsKey('Fruit or Vegetable Type')) {
      return _capitalizeFirstLetter(
          scanData['Fruit or Vegetable Type'].toString());
    }
    return '';
  }

  String _capitalizeFirstLetter(String text) {
    if (text.isEmpty) return '';
    return text[0].toUpperCase() + text.substring(1).toLowerCase();
  }

  int _getDaysUntilHarvest(Map<String, dynamic>? scanData) {
    final now = DateTime.now();
    final harvestData = scanData?['harvestDate'];

    if (harvestData is Timestamp) {
      final harvestDate = harvestData.toDate();
      return harvestDate.difference(now).inDays;
    } else if (harvestData is DateTime) {
      return harvestData.difference(now).inDays;
    } else if (harvestData is String) {
      try {
        final parsedDate = DateTime.parse(harvestData);
        return parsedDate.difference(now).inDays;
      } catch (e) {
        print('Error parsing harvest date string: $e');
        return 0; // Default to 0 days if parsing fails
      }
    }
    return 0; // Default to 0 days if no valid harvest date is found
  }

  double _getRipenessPercentage(Map<String, dynamic>? scanData) {
    if (scanData == null) return 0.0;

    // Try to get ripeness from different possible fields
    var ripeness = scanData['ripeness'] ??
        scanData['ripenessPercentage'] ??
        scanData['ripeness_percentage'];

    if (ripeness is double) {
      return ripeness;
    } else if (ripeness is int) {
      return ripeness.toDouble();
    } else if (ripeness is String) {
      // Parse percentage strings like "75%" or "75% - Nearly ripe"
      final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(ripeness);
      if (match != null) {
        return double.tryParse(match.group(1)!) ?? 0.0;
      }
    }

    // If no ripeness data, estimate based on days until harvest
    final daysUntilHarvest = _getDaysUntilHarvest(scanData);
    if (daysUntilHarvest <= 0) return 100.0;
    if (daysUntilHarvest <= 3) return 90.0;
    if (daysUntilHarvest <= 7) return 70.0;
    if (daysUntilHarvest <= 14) return 50.0;
    return 25.0;
  }

  bool _isReadyForHarvest(Map<String, dynamic> scanData) {
    // Check harvestStatus field (preferred format)
    if (scanData.containsKey('harvestStatus')) {
      final status = scanData['harvestStatus'].toString().toLowerCase();
      return status == 'ready_for_harvest' ||
          status == 'ready' ||
          (status.contains('ready') && !status.contains('not'));
    }

    // Check Ready for Harvest field (alternate format)
    if (scanData.containsKey('Ready for Harvest')) {
      final status = scanData['Ready for Harvest'].toString().toLowerCase();
      return status == 'ready_for_harvest' ||
          status == 'ready' ||
          (status.contains('ready') && !status.contains('not'));
    }

    // Check final_prediction field
    if (scanData.containsKey('final_prediction')) {
      final prediction = scanData['final_prediction'];
      if (prediction is bool) {
        return prediction;
      } else if (prediction is String) {
        return prediction.toLowerCase() == 'true' ||
            prediction.toLowerCase() == 'yes' ||
            prediction.toLowerCase() == 'ready';
      }
    }

    // As a last resort, check gemini_prediction field
    if (scanData.containsKey('gemini_prediction')) {
      final prediction = scanData['gemini_prediction'];
      if (prediction is bool) {
        return prediction;
      } else if (prediction is String) {
        return prediction.toLowerCase() == 'true' ||
            prediction.toLowerCase() == 'yes' ||
            prediction.toLowerCase() == 'ready';
      }
    }

    return false;
  }

  Future<void> _refreshData() async {
    await _fetchCropHarvestData();
    widget.onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _refreshData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Container(
              padding: const EdgeInsets.only(
                  bottom: 100), // Space for bottom nav bar
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  _isLoading
                      ? _buildLoadingIndicator()
                      : _availableCrops.isEmpty
                          ? _buildEmptyState()
                          : _buildChartContent(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF2E7D32),
            Color(0xFF1B5E20),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(30),
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Harvest Chart',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon:
                          const Icon(Icons.picture_as_pdf, color: Colors.white),
                      onPressed: _availableCrops.isEmpty ? null : _exportToPdf,
                      tooltip: 'Export to PDF',
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      onPressed: _refreshData,
                      tooltip: 'Refresh Data',
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 15),
            Text(
              'View ripeness status for your selected crop',
              style: TextStyle(
                fontSize: 16,
                color: Colors.white.withOpacity(0.9),
              ),
            ),
            const SizedBox(height: 10),
            if (_availableCrops.isNotEmpty) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButton<String>(
                  value: _selectedCrop,
                  isExpanded: true,
                  underline: const SizedBox(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  dropdownColor: const Color(0xFF2E7D32),
                  items: _availableCrops.map((String crop) {
                    return DropdownMenuItem<String>(
                      value: crop,
                      child: Text(
                        crop,
                        style: const TextStyle(color: Colors.white),
                      ),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    setState(() {
                      _selectedCrop = newValue;
                    });
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return Container(
      height: 400,
      padding: const EdgeInsets.all(20),
      child: const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4CAF50)),
        ),
      ),
    );
  }

  Future<void> _exportToPdf() async {
    if (_availableCrops.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No data available to export')),
      );
      return;
    }

    setState(() {
      _isExporting = true;
    });

    try {
      // Get data for the selected crop only
      final selectedCropData = _cropData.entries
          .where((entry) => entry.value.first['produceName'] == _selectedCrop)
          .toList();

      final File? pdfFile = await _pdfService.generateRipenessChartPdf(
        cropData: selectedCropData,
        selectedCrop: _selectedCrop ?? 'All Crops',
        title: 'Ripeness Status Chart Report',
        description: 'Ripeness status and harvest timeline for $_selectedCrop.',
      );

      if (pdfFile != null) {
        // Show options dialog after PDF is generated
        if (mounted) {
          _showPdfOptionsDialog(pdfFile);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to generate PDF')),
          );
        }
      }
    } catch (e) {
      debugPrint('Error exporting to PDF: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  void _showPdfOptionsDialog(File pdfFile) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('PDF Generated'),
          content: const Text('What would you like to do with the PDF?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _pdfService.openPdf(pdfFile);
              },
              child: const Text('View'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _pdfService.printPdf(pdfFile);
              },
              child: const Text('Print'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _pdfService.sharePdf(pdfFile);
              },
              child: const Text('Share'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return SizedBox(
      height: 400,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bar_chart_outlined,
              size: 80,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 20),
            Text(
              'No produce data yet',
              style: TextStyle(
                fontSize: 20,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Scan some fruits or vegetables\nto see harvest time data',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: () {
                // If a callback is provided by the parent, use it to request
                // navigation to the camera tab. Otherwise, just pop.
                if (widget.onNavigateToCamera != null) {
                  widget.onNavigateToCamera!();
                } else {
                  Navigator.of(context).pop();
                }
              },
              icon: const Icon(Icons.camera_alt),
              label: const Text('Start Scanning'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65100),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartContent() {
    if (_selectedCrop == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Ripeness Status for $_selectedCrop',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
        ),
        const SizedBox(height: 5),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Daily ripeness progression until harvest',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
        ),
        const SizedBox(height: 20),
        _buildRipenessChart(),
        const SizedBox(height: 30),
        _buildRipenessLegend(),
      ],
    );
  }

  Widget _buildRipenessChart() {
    if (_selectedCrop == null) return const SizedBox.shrink();

    // Get all data for the selected crop
    final cropInstances = _cropData.entries
        .where((entry) => entry.value.first['produceName'] == _selectedCrop)
        .toList();

    if (cropInstances.isEmpty) return const SizedBox.shrink();

    // Calculate daily ripeness progression for each instance
    List<Map<String, dynamic>> chartData = [];
    for (var instance in cropInstances) {
      final data = instance.value.first;
      final daysUntilHarvest = data['daysUntilHarvest'] as int;
      final currentRipenessPercentage = data['ripenessPercentage'] as double;

      // Create data points for each day from 1 to daysUntilHarvest
      for (int day = 1; day <= daysUntilHarvest; day++) {
        // Calculate ripeness percentage for this specific day
        // Ripeness increases over time, starting from current percentage
        final ripenessForDay = _calculateRipenessForDay(currentRipenessPercentage, day, daysUntilHarvest);
        
        // Determine ripeness status based on percentage
        String ripenessStatus = _getRipenessStatus(ripenessForDay, daysUntilHarvest - day);
        
        chartData.add({
          'day': day,
          'ripenessStatus': ripenessStatus,
          'ripenessPercentage': ripenessForDay,
          'daysUntilHarvest': daysUntilHarvest,
          'instanceName': instance.key,
        });
      }
    }

    debugPrint('Building ripeness chart with ${chartData.length} entries');
    return Container(
      height: 300,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: 100, // Ripeness percentage scale 0-100
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              tooltipBgColor: Colors.blueGrey.withOpacity(0.8),
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                if (groupIndex < chartData.length) {
                  final data = chartData[groupIndex];
                  return BarTooltipItem(
                    'Day ${data['day']}\n${data['ripenessStatus']}\n${data['ripenessPercentage'].toStringAsFixed(1)}%',
                    const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                }
                return null;
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  if (value >= 0 && value < chartData.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Day ${chartData[value.toInt()]['day']}',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
                reservedSize: 42,
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  if (value % 10 == 0) {
                    return Text(
                      '${value.toInt()}%',
                      style: const TextStyle(fontSize: 10),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(
            chartData.length,
            (index) {
              final data = chartData[index];
              final ripenessPercentage = data['ripenessPercentage'] as double;

              // ADD DEBUG PRINT HERE:
              debugPrint(
                  'Bar Chart - Index: $index, Y-axis Value: $ripenessPercentage%');

              return BarChartGroupData(
                x: index,
                barRods: [
                  BarChartRodData(
                    toY: ripenessPercentage,
                    gradient: LinearGradient(
                      colors: [
                        _getColorForRipenessStatus(data['ripenessStatus']),
                        _getColorForRipenessStatus(data['ripenessStatus'])
                            .withOpacity(0.6),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    width: 20,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              );
            },
          ),
          gridData: FlGridData(
            show: true,
            horizontalInterval: 10,
            getDrawingHorizontalLine: (value) => FlLine(
              color: Colors.grey.shade300,
              strokeWidth: 1,
              dashArray: [5, 5],
            ),
          ),
        ),
      ),
    );
  }

  double _calculateRipenessForDay(double currentRipeness, int day, int totalDays) {
    // Calculate how much ripeness should increase per day
    // Start from current ripeness and reach 100% by harvest day
    final remainingRipeness = 100.0 - currentRipeness;
    final ripenessIncreasePerDay = remainingRipeness / totalDays;
    
    // Calculate ripeness for this specific day
    final ripenessForDay = currentRipeness + (ripenessIncreasePerDay * day);
    
    // Ensure it doesn't exceed 100%
    return ripenessForDay.clamp(0.0, 100.0);
  }

  String _getRipenessStatus(double ripenessPercentage, int daysUntilHarvest) {
    if (ripenessPercentage >= 100 || daysUntilHarvest <= 0) {
      return 'Ready to Harvest';
    } else if (ripenessPercentage >= 70 || daysUntilHarvest <= 3) {
      return 'Almost Ready';
    } else {
      return 'Not Yet Ready';
    }
  }

  int _getRipenessLevel(String ripenessStatus) {
    switch (ripenessStatus) {
      case 'Not Yet Ready':
        return 0;
      case 'Almost Ready':
        return 1;
      case 'Ready to Harvest':
        return 2;
      default:
        return 0;
    }
  }

  Color _getColorForRipenessStatus(String ripenessStatus) {
    switch (ripenessStatus) {
      case 'Not Yet Ready':
        return const Color(0xFF2E7D32); // Dark Green
      case 'Almost Ready':
        return const Color(0xFFFFB300); // Amber
      case 'Ready to Harvest':
        return const Color(0xFFE65100); // Deep Orange
      default:
        return const Color(0xFF2E7D32);
    }
  }

  Color _getColorForValue(double value) {
    if (value <= 0) return const Color(0xFFE65100); // Overripe or Ready
    if (value <= 3) return const Color(0xFFFF9800); // Very Soon
    if (value <= 5) return const Color(0xFFFFB300); // Soon
    if (value <= 7) return const Color(0xFF8BC34A); // Medium
    if (value <= 10) return const Color(0xFF4CAF50); // Further
    return const Color(0xFF2E7D32); // Far
  }

  Widget _buildRipenessLegend() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ripeness Status Legend',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildLegendItem(
                  'Not Yet Ready (0-69%)', const Color(0xFF2E7D32)),
              _buildLegendItem(
                  'Almost Ready (70-99%)', const Color(0xFFFFB300)),
              _buildLegendItem(
                  'Ready to Harvest (100%)', const Color(0xFFE65100)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade700,
          ),
        ),
      ],
    );
  }
}
