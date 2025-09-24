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
            .collection('scans')
            .orderBy('timestamp', descending: true)
            .get();
        
        if (result.docs.isNotEmpty) {
          Map<String, int> cropDaysMap = {};
          Map<String, int> cropCountMap = {};
          
          for (var doc in result.docs) {
            final scanData = doc.data() as Map<String, dynamic>;
            
            // Extract produce name and days until harvest
            String produceName = _getProduceName(scanData);
            int daysUntilHarvest = _getDaysUntilHarvest(scanData);
            
            if (produceName.isNotEmpty) {
              // Calculate running average for each crop type
              if (cropDaysMap.containsKey(produceName)) {
                int currentTotal = cropDaysMap[produceName]! * cropCountMap[produceName]!;
                cropCountMap[produceName] = cropCountMap[produceName]! + 1;
                cropDaysMap[produceName] = ((currentTotal + daysUntilHarvest) / cropCountMap[produceName]!).round();
              } else {
                cropDaysMap[produceName] = daysUntilHarvest;
                cropCountMap[produceName] = 1;
              }
            }
          }
          
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
      return _capitalizeFirstLetter(scanData['Fruit or Vegetable Type'].toString());
    }
    return '';
  }
  
  String _capitalizeFirstLetter(String text) {
    if (text.isEmpty) return '';
    return text[0].toUpperCase() + text.substring(1).toLowerCase();
  }
  
  int _getDaysUntilHarvest(Map<String, dynamic>? scanData) {
    if (scanData == null) return 7; // Default for sorting purposes

    // If it's ready for harvest, return 0 days
    if (_isReadyForHarvest(scanData)) return 0;

    // Check for overripe status
    if (scanData.containsKey('harvestStatus')) {
      final status = scanData['harvestStatus'].toString().toLowerCase();
      if (status == 'overripe' || status.contains('over')) {
        return 0; // For chart purposes, show 0 days for overripe
      }
    }
    
    if (scanData.containsKey('Ready for Harvest')) {
      final status = scanData['Ready for Harvest'].toString().toLowerCase();
      if (status == 'overripe' || status.contains('over')) {
        return 0;
      }
    }

    // Check if there's an explicit days_until_harvest field
    if (scanData.containsKey('days_until_harvest')) {
      final daysValue = scanData['days_until_harvest'];

      // Handle different types
      if (daysValue is int) {
        return daysValue;
      } else if (daysValue is double) {
        return daysValue.round();
      } else if (daysValue is String && daysValue.isNotEmpty) {
        try {
          return int.parse(daysValue);
        } catch (e) {
          // Fall through to default
        }
      }
    }
    
    // Also check the daysUntilHarvest field (camel case version)
    if (scanData.containsKey('daysUntilHarvest')) {
      final daysValue = scanData['daysUntilHarvest'];

      // Handle different types
      if (daysValue is int) {
        return daysValue;
      } else if (daysValue is double) {
        return daysValue.round();
      } else if (daysValue is String && daysValue.isNotEmpty) {
        try {
          return int.parse(daysValue);
        } catch (e) {
          // Fall through to default
        }
      }
    }

    // Use produce type and characteristics to make a better estimate
    if (scanData.containsKey('name') && scanData.containsKey('Color')) {
      final type = (scanData['name'] ?? '').toString().toLowerCase();
      final color = (scanData['Color'] ?? '').toString().toLowerCase();

      // Use improved produce-specific estimates
      if (type.contains('banana')) {
        if (color.contains('green')) return 7;
        if (color.contains('yellow') && color.contains('green')) return 3;
        return 4;
      } else if (type.contains('tomato')) {
        if (color.contains('green')) return 10;
        if (color.contains('orange') || color.contains('light red')) return 3;
        return 5;
      } else if (type.contains('apple')) {
        if (color.contains('green') && !type.contains('granny')) return 10;
        return 7;
      } else if (type.contains('avocado')) {
        if (color.contains('green')) return 8;
        return 3;
      } else if (type.contains('mango')) {
        if (color.contains('green')) return 10;
        if (color.contains('yellow') && color.contains('green')) return 5;
        return 4;
      }
    }

    // Default value if no specific days information
    return 7;
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
          padding: const EdgeInsets.only(bottom: 100), // Space for bottom nav bar
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
                        _getColorForValue(entry.value.toDouble()).withOpacity(0.6),
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
