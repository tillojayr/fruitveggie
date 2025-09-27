import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/services.dart';
import 'dart:async';

class ChartPage extends StatefulWidget {
  final Function() onRefresh;

  const ChartPage({
    super.key,
    required this.onRefresh,
  });

  @override
  State<ChartPage> createState() => _ChartPageState();
}

class _ChartPageState extends State<ChartPage> {
  bool _isLoading = true;
  Map<String, int> _cropHarvestDays = {};
  List<Color> gradientColors = [
    const Color(0xFF2E7D32), // Dark Green
    const Color(0xFF4CAF50), // Medium Green
    const Color(0xFF8BC34A), // Light Green
    const Color(0xFFFFB300), // Amber
    const Color(0xFFFF9800), // Orange
    const Color(0xFFE65100), // Deep Orange
  ];

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
          Map<String, int> cropDaysMap = {};
          Map<String, int> cropCountMap = {};

          debugPrint('Data fetched: ${result.docs.length} scans');
          for (var doc in result.docs) {
            final scanData = doc.data() as Map<String, dynamic>;

            String produceName = scanData['produceType'];
            int daysUntilHarvest = _getDaysUntilHarvest(scanData);

            // Start with the original name
            String key = produceName;
            int counter = 2;

            // If the key already exists, keep trying with #2, #3, ...
            while (cropDaysMap.containsKey(key)) {
              key = '$produceName#$counter';
              counter++;
            }

            cropDaysMap[key] = daysUntilHarvest + 1;
          }

          debugPrint('Initial crop days map: $cropDaysMap');
          debugPrint('Processed crop days map: $cropDaysMap');
          setState(() {
            _cropHarvestDays = cropDaysMap;
            _isLoading = false;
          });
        } else {
          setState(() {
            _cropHarvestDays = {};
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
    return RefreshIndicator(
      onRefresh: _refreshData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Container(
          padding:
              const EdgeInsets.only(bottom: 100), // Space for bottom nav bar
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              _isLoading
                  ? _buildLoadingIndicator()
                  : _cropHarvestDays.isEmpty
                      ? _buildEmptyState()
                      : _buildChartContent(),
            ],
          ),
        ),
      ),
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
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  onPressed: _refreshData,
                ),
              ],
            ),
            const SizedBox(height: 15),
            Text(
              'View days until harvest for all your produce',
              style: TextStyle(
                fontSize: 16,
                color: Colors.white.withOpacity(0.9),
              ),
            ),
            const SizedBox(height: 10),
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
                // Navigate to camera
                Navigator.of(context).pop();
                // Using a callback to notify the parent to navigate to camera page
                // This will be handled in dashboard_page.dart
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Estimated Days Until Harvest',
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
            'Based on your scans',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
        ),
        const SizedBox(height: 20),
        _buildBarChart(),
        const SizedBox(height: 30),
        _buildLegend(),
      ],
    );
  }

  Widget _buildBarChart() {
    final entries = _cropHarvestDays.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    debugPrint('Building chart with ${entries.length} entries');
    return Container(
      height: 300,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: _getMaxY(),
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              tooltipBgColor: Colors.blueGrey.withOpacity(0.8),
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                return BarTooltipItem(
                  '${entries[groupIndex].key}\n${rod.toY.round()} days',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  if (value >= 0 && value < entries.length) {
                    // Abbreviate longer crop names
                    String name = entries[value.toInt()].key;
                    if (name.length > 10) {
                      name = '${name.substring(0, 8)}...';
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        name,
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
                reservedSize: 30,
                getTitlesWidget: (value, meta) {
                  if (value % 1 == 0) {
                    return Text(
                      value.toInt().toString(),
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
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
            entries.length,
            (index) {
              final entry = entries[index];
              return BarChartGroupData(
                x: index,
                barRods: [
                  BarChartRodData(
                    toY: entry.value.toDouble(),
                    gradient: LinearGradient(
                      colors: [
                        _getColorForValue(entry.value.toDouble()),
                        _getColorForValue(entry.value.toDouble())
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
            horizontalInterval: 1,
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

  double _getMaxY() {
    if (_cropHarvestDays.isEmpty) return 10.0;

    final maxValue = _cropHarvestDays.values
        .reduce((curr, next) => curr > next ? curr : next);

    // Return max value rounded up to next integer plus some padding
    return (maxValue + 2).toDouble();
  }

  Color _getColorForValue(double value) {
    if (value <= 0) return const Color(0xFFE65100); // Overripe or Ready
    if (value <= 3) return const Color(0xFFFF9800); // Very Soon
    if (value <= 5) return const Color(0xFFFFB300); // Soon
    if (value <= 7) return const Color(0xFF8BC34A); // Medium
    if (value <= 10) return const Color(0xFF4CAF50); // Further
    return const Color(0xFF2E7D32); // Far
  }

  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Color Legend',
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
              _buildLegendItem('Ready', const Color(0xFFE65100)),
              _buildLegendItem('1-3 Days', const Color(0xFFFF9800)),
              _buildLegendItem('4-5 Days', const Color(0xFFFFB300)),
              _buildLegendItem('6-7 Days', const Color(0xFF8BC34A)),
              _buildLegendItem('8-10 Days', const Color(0xFF4CAF50)),
              _buildLegendItem('10+ Days', const Color(0xFF2E7D32)),
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
