import 'package:flutter/material.dart';

class AllHarvestsPage extends StatefulWidget {
  final String lastProcessedProduceType;
  final String? lastProcessedImagePath;
  final String? lastProcessedImageBase64;
  final List<Map<String, dynamic>> recentScans;
  final Map<String, dynamic>? Function() findScanDataForLatestProcessed;
  final bool Function(Map<String, dynamic>) isSameScanAsLastProcessed;
  final Widget Function({
    required String plantName,
    required String variety,
    int? daysLeft,
    String? imageUrl,
    String? imageBase64,
    Map<String, dynamic>? scanData,
  }) buildHarvestCard;
  final Future<void> Function() onRefresh;

  const AllHarvestsPage({
    super.key,
    required this.lastProcessedProduceType,
    required this.lastProcessedImagePath,
    required this.lastProcessedImageBase64,
    required this.recentScans,
    required this.findScanDataForLatestProcessed,
    required this.isSameScanAsLastProcessed,
    required this.buildHarvestCard,
    required this.onRefresh,
  });

  @override
  State<AllHarvestsPage> createState() => _AllHarvestsPageState();
}

class _AllHarvestsPageState extends State<AllHarvestsPage> {
  bool _isLoading = false;
  String _sortOption = 'Recent';
  List<Map<String, dynamic>> _processedScans = [];
  List<Map<String, dynamic>> _originalProcessedScans =
      []; // New list to store the original data
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _processScanData();
  }

  void _processScanData() {
    // Start with an empty list
    _processedScans = [];
    _originalProcessedScans = []; // Clear the original list too

    // Create a map to deduplicate scans by scanId or image path
    final Map<String, Map<String, dynamic>> deduplicatedScans = {};

    // Add the last processed item if valid
    if (widget.lastProcessedProduceType != 'Produce' &&
        widget.lastProcessedImagePath != null) {
      // Find or create the scan data for last processed
      Map<String, dynamic>? lastProcessedScanData =
          widget.findScanDataForLatestProcessed();

      if (lastProcessedScanData != null) {
        final newItem = {
          'plantName': widget.lastProcessedProduceType,
          'variety': 'From Recent Scan',
          'imageUrl': widget.lastProcessedImagePath,
          'imageBase64': widget.lastProcessedImageBase64,
          'scanData': lastProcessedScanData,
          'isLatest': true,
        };

        final String scanId = lastProcessedScanData['scanId'] ?? '';
        final String key =
            scanId.isNotEmpty ? scanId : (widget.lastProcessedImagePath ?? '');

        if (key.isNotEmpty) {
          deduplicatedScans[key] = newItem;
        }
      }
    }

    // Add all other scans that aren't the same as the last processed
    for (final scan in widget.recentScans) {
      if (!widget.isSameScanAsLastProcessed(scan)) {
        final newItem = {
          'plantName': scan['name'] ?? 'Unknown',
          'variety': 'Recently Scanned',
          'imageUrl': scan['imagePath'] ?? scan['imageUrl'],
          'imageBase64': scan['imageBase64'],
          'scanData': scan,
          'isLatest': false,
        };

        final String scanId = scan['scanId'] ?? '';
        final String imagePath = scan['imagePath'] ?? scan['imageUrl'] ?? '';
        final String key = scanId.isNotEmpty ? scanId : imagePath;

        if (key.isNotEmpty) {
          deduplicatedScans[key] = newItem;
        }
      }
    }

    // Convert map values to lists
    _processedScans = deduplicatedScans.values.toList();
    _originalProcessedScans = List.from(_processedScans);

    // Apply sort based on current option
    _applySorting();

    // Apply search filter if any
    if (_searchQuery.isNotEmpty) {
      _filterScans(_searchQuery);
    }
  }

  void _applySorting() {
    switch (_sortOption) {
      case 'Ready':
        // Sort by readiness - Ready first, then by days until harvest
        _processedScans.sort((a, b) {
          bool aReady = _isReadyForHarvest(a['scanData']);
          bool bReady = _isReadyForHarvest(b['scanData']);

          if (aReady && !bReady) return -1;
          if (!aReady && bReady) return 1;

          int aDays = _getDaysUntilHarvest(a['scanData']);
          int bDays = _getDaysUntilHarvest(b['scanData']);

          return aDays.compareTo(bDays);
        });
        break;

      case 'Days':
        // Sort by days until harvest (ascending)
        _processedScans.sort((a, b) {
          int aDays = _getDaysUntilHarvest(a['scanData']);
          int bDays = _getDaysUntilHarvest(b['scanData']);
          return aDays.compareTo(bDays);
        });
        break;

      case 'Name':
        // Sort alphabetically by plant name
        _processedScans.sort((a, b) {
          String aName = (a['plantName'] ?? '').toString();
          String bName = (b['plantName'] ?? '').toString();
          return aName.compareTo(bName);
        });
        break;

      case 'Recent':
      default:
        // Most recent first (default) - already in correct order from recentScans
        // But prioritize the last processed item
        _processedScans.sort((a, b) {
          if (a['isLatest'] == true) return -1;
          if (b['isLatest'] == true) return 1;

          // Otherwise use timestamp if available
          dynamic aTimestamp = a['scanData']?['timestamp'];
          dynamic bTimestamp = b['scanData']?['timestamp'];

          if (aTimestamp != null && bTimestamp != null) {
            try {
              DateTime aDate =
                  aTimestamp is DateTime ? aTimestamp : aTimestamp.toDate();
              DateTime bDate =
                  bTimestamp is DateTime ? bTimestamp : bTimestamp.toDate();
              return bDate.compareTo(aDate); // Newest first
            } catch (e) {
              // Fall back to default order
            }
          }

          return 0; // Keep original order
        });
        break;
    }
  }

  void _filterScans(String query) {
    // Store the query
    _searchQuery = query;

    setState(() {
      // If empty query, restore the original data
      if (query.isEmpty) {
        _processedScans = List.from(_originalProcessedScans);
        _applySorting();
        return;
      }

      // Filter based on query using the original list to avoid recursive filtering
      _processedScans = _originalProcessedScans.where((scan) {
        final name = (scan['plantName'] ?? '').toString().toLowerCase();
        final variety = (scan['variety'] ?? '').toString().toLowerCase();

        return name.contains(query.toLowerCase()) ||
            variety.contains(query.toLowerCase());
      }).toList();

      // Apply current sort to filtered results
      _applySorting();
    });
  }

  bool _isReadyForHarvest(Map<String, dynamic>? scanData) {
    if (scanData == null) return false;

    // First check the harvestStatus field (which we updated in result_page.dart)
    if (scanData.containsKey('harvestStatus')) {
      final status = scanData['harvestStatus'].toString().toLowerCase();
      return status == 'ready_for_harvest' ||
          status == 'ready' ||
          (status.contains('ready') && !status.contains('not'));
    }

    // Check Ready for Harvest field
    if (scanData.containsKey('Ready for Harvest')) {
      final status = scanData['Ready for Harvest'].toString().toLowerCase();
      return status == 'ready_for_harvest' ||
          status == 'ready' ||
          (status.contains('ready') && !status.contains('not'));
    }

    // Check final_prediction as fallback
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

    // Then check gemini_prediction as last resort
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

  int _getDaysUntilHarvest(Map<String, dynamic>? scanData) {
    if (scanData == null) return 999; // Large default for sorting purposes

    // If it's ready for harvest, return 0 days
    if (_isReadyForHarvest(scanData)) return 0;

    // Check for overripe status
    if (scanData.containsKey('harvestStatus')) {
      final status = scanData['harvestStatus'].toString().toLowerCase();
      if (status == 'overripe' || status.contains('over')) {
        return -1; // Negative days indicates overripe
      }
    }

    if (scanData.containsKey('Ready for Harvest')) {
      final status = scanData['Ready for Harvest'].toString().toLowerCase();
      if (status == 'overripe' || status.contains('over')) {
        return -1; // Negative days indicates overripe
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
    return 7; // More accurate default based on average ripening time
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (!mounted) return;
        Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('All Harvests'),
          backgroundColor: const Color(0xFF2E7D32),
          foregroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (!mounted) return;
              Navigator.of(context).pop();
            },
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _isLoading
                  ? null
                  : () async {
                      if (!mounted) return;
                      await _refreshData();
                    },
              tooltip: 'Refresh',
            ),
          ],
        ),
        body: Column(
          children: [
            // Search and sort options
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Search field
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Search produce...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade200,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                    onChanged: _filterScans,
                  ),

                  // Sort options
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        const Text(
                          'Sort by:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 12),
                        _buildSortChip('Recent'),
                        const SizedBox(width: 8),
                        _buildSortChip('Ready'),
                        const SizedBox(width: 8),
                        _buildSortChip('Days'),
                        const SizedBox(width: 8),
                        _buildSortChip('Name'),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Main harvest list
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(),
                    )
                  : _processedScans.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _searchQuery.isEmpty
                                    ? Icons.eco_outlined
                                    : Icons.search_off,
                                size: 80,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _searchQuery.isEmpty
                                    ? 'No harvests available'
                                    : 'No matching harvests found',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (_searchQuery.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: TextButton(
                                    onPressed: () => _filterScans(''),
                                    child: const Text('Clear search'),
                                  ),
                                ),
                              if (_searchQuery.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                      Navigator.pop(context);
                                    },
                                    icon: const Icon(Icons.camera_alt),
                                    label: const Text('Scan Something'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFE65100),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 24, vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(30),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _refreshData,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _processedScans.length,
                            itemBuilder: (context, index) {
                              final scan = _processedScans[index];
                              return widget.buildHarvestCard(
                                plantName: scan['plantName'],
                                variety: scan['variety'],
                                imageUrl: scan['imageUrl'],
                                imageBase64: scan['imageBase64'],
                                scanData: scan['scanData'],
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refreshData() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await widget.onRefresh();

      if (mounted) {
        setState(() {
          _processScanData();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error refreshing harvest data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildSortChip(String value) {
    return Chip(
      label: Text(value),
      backgroundColor:
          _sortOption == value ? Colors.white : Colors.grey.shade200,
      labelStyle: TextStyle(
        fontWeight: _sortOption == value ? FontWeight.bold : FontWeight.normal,
        color: _sortOption == value ? Colors.black : Colors.grey.shade700,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color:
              _sortOption == value ? Colors.grey.shade300 : Colors.transparent,
        ),
      ),
      onDeleted: _sortOption == value
          ? () => setState(() => _sortOption = 'Recent')
          : null,
    );
  }
}
