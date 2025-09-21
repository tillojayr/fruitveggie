import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io';

class AllScansPage extends StatefulWidget {
  final List<Map<String, dynamic>> scans;
  final Future<void> Function() onRefresh;

  const AllScansPage({
    super.key,
    required this.scans,
    required this.onRefresh,
  });

  @override
  State<AllScansPage> createState() => _AllScansPageState();
}

class _AllScansPageState extends State<AllScansPage> {
  bool _isLoading = false;
  String _sortOption = 'Recent'; // Default sort option
  late List<Map<String, dynamic>> _filteredScans;
  late List<Map<String, dynamic>> _originalScans; // Store the original scans
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  bool _isGridView = false;
  String _selectedCategory = 'All';
  late List<String> _categories;

  @override
  void initState() {
    super.initState();

    // Deduplicate scans by scanId before storing
    final Map<String, Map<String, dynamic>> deduplicatedScans = {};

    // Process each scan to ensure no duplicates
    for (final scan in widget.scans) {
      final String scanId = scan['scanId'] ?? '';

      if (scanId.isNotEmpty) {
        // Use scanId as key for deduplication
        deduplicatedScans[scanId] = scan;
      } else {
        // For scans without scanId, use image path as fallback key
        final String imagePath = scan['imagePath'] ?? scan['imageUrl'] ?? '';
        if (imagePath.isNotEmpty) {
          deduplicatedScans[imagePath] = scan;
        }
      }
    }

    // Store deduplicated scans
    _originalScans = deduplicatedScans.values.toList();
    _filteredScans = List.from(_originalScans);

    // Build categories list
    final Set<String> categorySet = {};
    for (final scan in _originalScans) {
      final String category = (scan['category'] ?? 'Uncategorized').toString();
      if (category.trim().isNotEmpty) {
        categorySet.add(category);
      }
    }
    _categories = ['All', ...categorySet.toList()..sort()];

    _applySorting(); // Apply default sorting when page loads
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterScans(String query) {
    setState(() {
      _searchQuery = query;
      _applyFilters();
    });
  }

  void _applyFilters() {
    List<Map<String, dynamic>> result = List.from(_originalScans);

    // Category filter
    if (_selectedCategory != 'All') {
      final String selectedLower = _selectedCategory.toLowerCase();
      result = result.where((scan) {
        final String category =
            (scan['category'] ?? '').toString().toLowerCase();
        return category == selectedLower;
      }).toList();
    }

    // Search filter
    if (_searchQuery.isNotEmpty) {
      final String q = _searchQuery.toLowerCase();
      result = result.where((scan) {
        final name = (scan['name'] ?? '').toString().toLowerCase();
        final category = (scan['category'] ?? '').toString().toLowerCase();
        return name.contains(q) || category.contains(q);
      }).toList();
    }

    _filteredScans = result;
    _applySorting();
  }

  void _applySorting() {
    switch (_sortOption) {
      case 'Name':
        // Sort alphabetically by name
        _filteredScans.sort((a, b) {
          final nameA = (a['name'] ?? 'Unknown').toString();
          final nameB = (b['name'] ?? 'Unknown').toString();
          return nameA.compareTo(nameB);
        });
        break;

      case 'Confidence':
        // Sort by confidence (highest first)
        _filteredScans.sort((a, b) {
          final confidenceA = _getConfidenceValue(a);
          final confidenceB = _getConfidenceValue(b);
          return confidenceB.compareTo(confidenceA); // Descending order
        });
        break;

      case 'Recent':
      default:
        // Most recent scans first based on timestamp
        _filteredScans.sort((a, b) {
          final timestampA = a['timestamp'];
          final timestampB = b['timestamp'];

          if (timestampA == null && timestampB == null) return 0;
          if (timestampA == null) return 1;
          if (timestampB == null) return -1;

          try {
            final dateA =
                timestampA is DateTime ? timestampA : timestampA.toDate();
            final dateB =
                timestampB is DateTime ? timestampB : timestampB.toDate();
            return dateB.compareTo(dateA); // Newest first
          } catch (e) {
            print('Error comparing timestamps: $e');
            return 0;
          }
        });
        break;
    }
  }

  // Helper method to get normalized confidence value for sorting
  double _getConfidenceValue(Map<String, dynamic> scan) {
    final confidence = scan['confidence'];
    if (confidence == null) return 0.0;

    if (confidence is double) {
      return confidence <= 1.0 ? confidence : confidence / 100.0;
    } else if (confidence is int) {
      return confidence / 100.0;
    } else if (confidence is String) {
      try {
        final stringValue = confidence.replaceAll('%', '').trim();
        return double.parse(stringValue) / 100.0;
      } catch (e) {
        return 0.0;
      }
    }
    return 0.0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('All Scans'),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _refreshScans,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
            onPressed: () {
              setState(() {
                _isGridView = !_isGridView;
              });
            },
            tooltip: _isGridView ? 'List view' : 'Grid view',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // Search field (modern style)
                Material(
                  elevation: 1,
                  color: Colors.transparent,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search produce...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              tooltip: 'Clear',
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _searchController.clear();
                                _filterScans('');
                              },
                            )
                          : null,
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
                      _buildSortChip('Recent', Icons.schedule),
                      const SizedBox(width: 8),
                      _buildSortChip('Name', Icons.sort_by_alpha),
                      const SizedBox(width: 8),
                      _buildSortChip('Confidence', Icons.insights),
                      const SizedBox(width: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_filteredScans.length} result${_filteredScans.length == 1 ? '' : 's'}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),

                // Category chips
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      const Text(
                        'Filter:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 12),
                      ..._categories.map((c) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(c),
                              selected: _selectedCategory == c,
                              selectedColor: const Color(0xFF2E7D32),
                              labelStyle: TextStyle(
                                color: _selectedCategory == c
                                    ? Colors.white
                                    : Colors.black,
                                fontWeight: _selectedCategory == c
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                              backgroundColor: Colors.grey.shade200,
                              onSelected: (_) {
                                setState(() {
                                  _selectedCategory = c;
                                  _applyFilters();
                                });
                              },
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                          )),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(),
                  )
                : _filteredScans.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color:
                                      const Color(0xFF2E7D32).withOpacity(0.08),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _searchQuery.isEmpty
                                      ? Icons.history
                                      : Icons.search_off,
                                  size: 40,
                                  color: const Color(0xFF2E7D32),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _searchQuery.isEmpty
                                    ? 'No scans yet'
                                    : 'No results found',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _searchQuery.isEmpty
                                    ? 'Start scanning fruits and vegetables to see them here.'
                                    : 'Try a different search or clear the filter.',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade700,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              if (_searchQuery.isNotEmpty)
                                OutlinedButton.icon(
                                  onPressed: () => _filterScans(''),
                                  icon: const Icon(Icons.clear),
                                  label: const Text('Clear search'),
                                  style: OutlinedButton.styleFrom(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _refreshScans,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          child: _isGridView
                              ? GridView.builder(
                                  key: const ValueKey('grid'),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 4),
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    mainAxisSpacing: 16,
                                    crossAxisSpacing: 16,
                                    childAspectRatio: 0.9,
                                  ),
                                  itemCount: _filteredScans.length,
                                  itemBuilder: (context, index) {
                                    return _buildScanGridItem(
                                        _filteredScans[index]);
                                  },
                                )
                              : ListView.builder(
                                  key: const ValueKey('list'),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                  itemCount: _filteredScans.length,
                                  itemBuilder: (context, index) {
                                    return _buildScanCard(
                                        _filteredScans[index]);
                                  },
                                ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSortChip(String option, IconData icon) {
    final isSelected = _sortOption == option;

    return FilterChip(
      avatar: Icon(
        icon,
        size: 18,
        color: isSelected ? Colors.white : const Color(0xFF2E7D32),
      ),
      label: Text(option),
      selected: isSelected,
      checkmarkColor: Colors.white,
      selectedColor: const Color(0xFF2E7D32),
      backgroundColor: Colors.grey.shade200,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _sortOption = option;
            _applySorting();
          });
        }
      },
    );
  }

  Future<void> _refreshScans() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await widget.onRefresh();

      if (mounted) {
        setState(() {
          _originalScans = List.from(widget.scans); // Update original data
          _filteredScans = List.from(widget.scans);
          // Rebuild categories
          final Set<String> categorySet = {};
          for (final scan in _originalScans) {
            final String category =
                (scan['category'] ?? 'Uncategorized').toString();
            if (category.trim().isNotEmpty) {
              categorySet.add(category);
            }
          }
          _categories = ['All', ...categorySet.toList()..sort()];
          if (_searchQuery.isNotEmpty) {
            _applyFilters(); // Reapply filters
          } else {
            _applyFilters(); // Apply filters + sorting
          }
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
            content: Text('Error refreshing scans: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildScanGridItem(Map<String, dynamic> scan) {
    final String fruitName = scan['name'] ?? 'Unknown Item';
    final String? imagePath = scan['imagePath'] ?? scan['imageUrl'];
    final String? base64Image = scan['imageBase64'];

    // Calculate date text
    final dynamic timestamp = scan['timestamp'];
    String dateText = 'Unknown date';
    if (timestamp != null) {
      try {
        final DateTime date =
            timestamp is DateTime ? timestamp : timestamp.toDate();
        dateText = '${date.day}/${date.month}/${date.year}';
      } catch (_) {}
    }

    // Confidence text
    String confidenceText = 'N/A';
    if (scan.containsKey('confidence')) {
      final dynamic confidence = scan['confidence'];
      if (confidence is double) {
        confidenceText = '${(confidence * 100).toStringAsFixed(0)}%';
      } else if (confidence is int) {
        confidenceText = '$confidence%';
      } else if (confidence is String) {
        confidenceText = confidence;
      }
    }

    return GestureDetector(
      onTap: () => _showScanDetails(scan),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        elevation: 2,
        child: Stack(
          children: [
            Positioned.fill(
              child: Hero(
                tag: _heroTagForScan(scan),
                child: _buildImageWidget(imagePath, base64Image),
              ),
            ),
            // Gradient overlay
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.45),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            // Info
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fruitName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _buildMiniPill(icon: Icons.event, text: dateText),
                      _buildMiniPill(
                          icon: Icons.verified, text: 'Conf: $confidenceText'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniPill({required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: const Color(0xFF2E7D32)),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildScanCard(Map<String, dynamic> scan) {
    final String fruitName = scan['name'] ?? 'Unknown Item';
    final String? imagePath = scan['imagePath'] ?? scan['imageUrl'];
    final String? base64Image = scan['imageBase64'];

    // Calculate date
    final dynamic timestamp = scan['timestamp'];
    String dateText = 'Unknown date';

    if (timestamp != null) {
      try {
        final DateTime date = timestamp is DateTime
            ? timestamp
            : timestamp.toDate(); // For Firestore Timestamp
        dateText = '${date.day}/${date.month}/${date.year}';
      } catch (e) {
        dateText = 'Unknown date';
      }
    }

    // Get confidence
    String confidenceText = 'N/A';
    if (scan.containsKey('confidence')) {
      dynamic confidence = scan['confidence'];
      if (confidence is double) {
        confidenceText = '${(confidence * 100).toStringAsFixed(1)}%';
      } else if (confidence is int) {
        confidenceText = '$confidence%';
      } else if (confidence is String) {
        confidenceText = confidence;
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      elevation: 2,
      child: InkWell(
        onTap: () => _showScanDetails(scan),
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 100,
                  height: 100,
                  child: Hero(
                    tag: _heroTagForScan(scan),
                    child: _buildImageWidget(imagePath, base64Image),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fruitName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildInfoChip(
                          icon: Icons.event,
                          text: dateText,
                          background: Colors.grey.shade200,
                          foreground: Colors.black87,
                        ),
                        _buildInfoChip(
                          icon: Icons.verified,
                          text: 'Conf: $confidenceText',
                          background: const Color(0xFF2E7D32).withOpacity(0.1),
                          foreground: const Color(0xFF2E7D32),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: () => _showScanDetails(scan),
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('View Details'),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF2E7D32),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                        )
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showScanDetails(Map<String, dynamic> scan) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2E7D32).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.eco,
                          color: Color(0xFF2E7D32),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Scan Details',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: SizedBox(
                        width: 200,
                        height: 200,
                        child: Hero(
                          tag: _heroTagForScan(scan),
                          child: _buildImageWidget(
                              scan['imagePath'] ?? scan['imageUrl'],
                              scan['imageBase64']),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildDetailRow('Name', scan['name'] ?? 'Unknown'),
                  _buildDetailRow(
                      'Category', scan['category'] ?? 'Uncategorized'),
                  _buildDetailRow('Date', _formatTimestamp(scan['timestamp'])),
                  _buildDetailRow('Status', scan['harvestStatus'] ?? 'N/A'),
                  _buildDetailRow(
                      'Harvest date', _formatTimestamp(scan['harvestDate'])),
                  if (scan.containsKey('ripeness'))
                    _buildDetailRow('Ripeness',
                        _formatRipeness(scan['ripeness'].toString())),
                  if (scan.containsKey('confidence'))
                    _buildDetailRow(
                        'Confidence', _formatConfidence(scan['confidence'])),
                  if (scan.containsKey('final_prediction') ||
                      scan.containsKey('gemini_prediction'))
                    _buildDetailRow(
                        'Ready for Harvest', _formatReadiness(scan)),
                  if (scan.containsKey('days_until_harvest'))
                    _buildDetailRow(
                        'Days Until Harvest', '${scan['days_until_harvest']}'),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.center,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        elevation: 0,
                      ),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _heroTagForScan(Map<String, dynamic> scan) {
    final String? scanId = scan['scanId'];
    final String? imagePath = scan['imagePath'] ?? scan['imageUrl'];
    final String name = scan['name'] ?? 'Unknown';
    final String date = _formatTimestamp(scan['timestamp']);
    return (scanId?.isNotEmpty == true)
        ? 'scan-hero-$scanId'
        : 'scan-hero-${imagePath ?? name}-$date';
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String text,
    required Color background,
    required Color foreground,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: foreground,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'Unknown';

    try {
      final DateTime date = timestamp is DateTime
          ? timestamp
          : timestamp.toDate(); // For Firestore Timestamp
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return 'Unknown';
    }
  }

  String _formatRipeness(dynamic ripeness) {
    if (ripeness == null) return 'N/A';

    if (ripeness is double) {
      return '${ripeness.toStringAsFixed(1)}%';
    } else if (ripeness is int) {
      return '$ripeness%';
    } else if (ripeness is String) {
      return '$ripeness%';
    }

    return 'N/A';
  }

  String _formatConfidence(dynamic confidence) {
    if (confidence == null) return 'N/A';

    if (confidence is double) {
      return '${(confidence * 100).toStringAsFixed(1)}%';
    } else if (confidence is int) {
      return '$confidence%';
    } else if (confidence is String) {
      return confidence;
    }

    return 'N/A';
  }

  String _formatReadiness(Map<String, dynamic> scan) {
    // Check final_prediction first
    if (scan.containsKey('final_prediction')) {
      final prediction = scan['final_prediction'];
      if (prediction is bool) {
        return prediction ? 'Yes' : 'No';
      } else if (prediction is String) {
        if (prediction.toLowerCase() == 'true' ||
            prediction.toLowerCase() == 'yes' ||
            prediction.toLowerCase() == 'ready') {
          return 'Yes';
        } else {
          return 'No';
        }
      }
    }

    // Then check gemini_prediction
    if (scan.containsKey('gemini_prediction')) {
      final prediction = scan['gemini_prediction'];
      if (prediction is bool) {
        return prediction ? 'Yes' : 'No';
      } else if (prediction is String) {
        if (prediction.toLowerCase() == 'true' ||
            prediction.toLowerCase() == 'yes' ||
            prediction.toLowerCase() == 'ready') {
          return 'Yes';
        } else {
          return 'No';
        }
      }
    }

    return 'Unknown';
  }

  Widget _buildImageWidget(String? path, String? base64String) {
    // First try base64
    if (base64String != null && base64String.isNotEmpty) {
      try {
        final Uint8List bytes = base64.decode(base64String);
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _buildPlaceholderImage();
          },
        );
      } catch (e) {
        return _buildPlaceholderImage();
      }
    }

    // Then try network or file image
    if (path != null && path.isNotEmpty) {
      if (path.startsWith('http')) {
        // Network image
        return CachedNetworkImage(
          imageUrl: path,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            color: Colors.grey[200],
            child: const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF2E7D32),
              ),
            ),
          ),
          errorWidget: (context, url, error) {
            return _buildPlaceholderImage();
          },
        );
      } else {
        // Local file image
        try {
          // Try to load the file
          final file = File(path);
          if (file.existsSync()) {
            return Image.file(
              file,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return _buildPlaceholderImage();
              },
            );
          } else {
            return _buildPlaceholderImage();
          }
        } catch (e) {
          return _buildPlaceholderImage();
        }
      }
    }

    // Fallback
    return _buildPlaceholderImage();
  }

  // Helper to build placeholder image
  Widget _buildPlaceholderImage() {
    return Container(
      color: Colors.grey[200],
      child: const Icon(
        Icons.eco,
        color: Color(0xFF2E7D32),
        size: 30,
      ),
    );
  }
}
