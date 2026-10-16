import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../config/app_config.dart';
import 'session_repository.dart';

class SessionEntryPage extends StatefulWidget {
  const SessionEntryPage({required this.firebaseReady, super.key});

  static const String routeName = '/sessions';
  final bool firebaseReady;

  @override
  State<SessionEntryPage> createState() => _SessionEntryPageState();
}

class _SessionEntryPageState extends State<SessionEntryPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _flatNumberController = TextEditingController();
  final TextEditingController _vehicleController = TextEditingController();
  final TextEditingController _startMeterController = TextEditingController();
  final TextEditingController _endMeterController = TextEditingController();
  final TextEditingController _historyFilterController =
      TextEditingController();

  bool _isExporting = false;
  bool _isProcessingSession = false;
  bool _didAutoSelectOnLoad = false;
  bool _prefilledFromProfile = false;
  String _historyFilter = '';
  String _displayName = '';
  String _displayEmail = '';
  bool _isAdmin = false;
  String _selectedWing = 'B1';
  int _selectedPoint = 1;
  Timer? _clockTimer;
  late final SessionRepository _sessionRepository =
      SessionRepository(FirebaseFirestore.instance);

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _nameController.dispose();
    _flatNumberController.dispose();
    _vehicleController.dispose();
    _startMeterController.dispose();
    _endMeterController.dispose();
    _historyFilterController.dispose();
    super.dispose();
  }

  String get _selectedPointKey =>
      '${_selectedWing.toUpperCase()}-P$_selectedPoint';
  String get _flatFilter => _flatNumberController.text.trim().toUpperCase();

  double _meter(TextEditingController controller) =>
      double.tryParse(controller.text.trim()) ?? 0;

  int _deriveFloorFromFlat(String flat) {
    final RegExp floorPattern = RegExp(r'^(\d{1,2})');
    final Match? match = floorPattern.firstMatch(flat.trim());
    final int parsed = int.tryParse(match?.group(1) ?? '') ?? 0;
    return parsed;
  }

  Future<void> _startCharging(double ratePerUnit) async {
    if (!widget.firebaseReady) {
      _toast('Firebase not configured yet.');
      return;
    }

    final String name = _nameController.text.trim();
    final String ownerUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final String flat = _flatFilter;
    final String vehicle = _vehicleController.text.trim().toUpperCase();
    final double startMeter = _meter(_startMeterController);
    if (name.isEmpty || flat.isEmpty || vehicle.isEmpty) {
      _toast('Enter Name, Flat Number and Vehicle Number.');
      return;
    }
    if (ownerUid.isEmpty) {
      _toast('Please login first.');
      return;
    }

    setState(() {
      _isProcessingSession = true;
    });
    try {
      await _sessionRepository.startChargingSession(
        ownerUid: ownerUid,
        residentName: name,
        wing: _selectedWing,
        floor: _deriveFloorFromFlat(flat),
        flatNumber: flat,
        chargingPoint: _selectedPoint,
        vehicleNumber: vehicle,
        startMeter: startMeter,
        ratePerUnit: ratePerUnit,
      );
      if (!mounted) {
        return;
      }
      _endMeterController.clear();
      await _successDialog('Charging started for $_selectedPointKey.');
    } on FirebaseException catch (e) {
      _toast(e.message ?? e.code);
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingSession = false;
        });
      }
    }
  }

  Future<void> _stopCharging(ChargingSession activeSession) async {
    final String ownerUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (ownerUid.isEmpty) {
      _toast('Please login first.');
      return;
    }
    final double endMeter = _meter(_endMeterController);
    if (endMeter <= activeSession.startMeter) {
      _toast('End meter must be greater than start meter.');
      return;
    }

    setState(() {
      _isProcessingSession = true;
    });
    try {
      await _sessionRepository.stopChargingSession(
        ownerUid: ownerUid,
        pointKey: _selectedPointKey,
        endMeter: endMeter,
      );
      if (!mounted) {
        return;
      }
      _endMeterController.clear();
      await _successDialog('Charging stopped. Slot is now available.');
    } on FirebaseException catch (e) {
      _toast(e.message ?? e.code);
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingSession = false;
        });
      }
    }
  }

  Future<void> _exportMyHistoryCsv() async {
    if (!widget.firebaseReady) {
      _toast('Firebase not configured yet.');
      return;
    }

    setState(() {
      _isExporting = true;
    });
    try {
      final List<ChargingSession> sessions =
          await _sessionRepository.fetchAllSessionsForExport(
        ownerUid: _isAdmin ? null : FirebaseAuth.instance.currentUser?.uid,
        wingFilter: _isAdmin ? _selectedWing : null,
        flatNumberFilter: _isAdmin ? _flatFilter : null,
      );
      if (sessions.isEmpty) {
        _toast('No sessions available for this flat.');
        return;
      }

      final StringBuffer csv = StringBuffer();
      csv.writeln(
        'Name,Wing,Floor,Flat Number,Charging Point,Point Key,Vehicle Number,Status,Start Date,Start Time,End Date,End Time,Start Meter (kWh),End Meter (kWh),Units (kWh),Rate (INR),Amount (INR)',
      );
      for (final ChargingSession s in sessions) {
        final String startDate = s.startTime == null
            ? ''
            : DateFormat('yyyy-MM-dd').format(s.startTime!);
        final String startTime = s.startTime == null
            ? ''
            : DateFormat('HH:mm:ss').format(s.startTime!);
        final String endDate = s.endTime == null
            ? ''
            : DateFormat('yyyy-MM-dd').format(s.endTime!);
        final String endTime =
            s.endTime == null ? '' : DateFormat('HH:mm:ss').format(s.endTime!);
        csv.writeln(
          '${_csv(s.residentName)},${s.wing},${s.floor},${s.flatNumber},P${s.chargingPoint},${s.pointKey},${_csv(s.vehicleNumber)},${s.status},$startDate,$startTime,$endDate,$endTime,${s.startMeter.toStringAsFixed(2)},${s.endMeter.toStringAsFixed(2)},${s.units.toStringAsFixed(2)},${s.ratePerUnit.toStringAsFixed(2)},${s.amount.toStringAsFixed(2)}',
        );
      }

      final Directory directory = await getApplicationDocumentsDirectory();
      final String filename =
          'my_history_${_selectedWing}_${_flatFilter}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv';
      final File file = File('${directory.path}/$filename');
      await file.writeAsString(csv.toString());
      await Share.shareXFiles(<XFile>[XFile(file.path)],
          subject: 'My Charging History');
    } catch (_) {
      _toast('Export failed. Please retry.');
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  Future<void> _exportAdminB1B2Excel() async {
    if (!widget.firebaseReady) {
      _toast('Firebase not configured yet.');
      return;
    }
    setState(() {
      _isExporting = true;
    });
    try {
      final List<ChargingSession> b1 =
          await _sessionRepository.fetchAllSessionsForExport(
        ownerUid: _isAdmin ? null : FirebaseAuth.instance.currentUser?.uid,
        wingFilter: 'B1',
      );
      final List<ChargingSession> b2 =
          await _sessionRepository.fetchAllSessionsForExport(
        ownerUid: _isAdmin ? null : FirebaseAuth.instance.currentUser?.uid,
        wingFilter: 'B2',
      );
      if (b1.isEmpty && b2.isEmpty) {
        _toast('No data available for B1/B2 export.');
        return;
      }

      final Excel excel = Excel.createExcel();
      _writeWingSheet(excel, 'B1', b1);
      _writeWingSheet(excel, 'B2', b2);
      _writeSummarySheet(excel, b1, b2);
      excel.delete('Sheet1');
      final List<int>? bytes = excel.encode();
      if (bytes == null) {
        throw Exception('Excel generation failed');
      }

      final Directory directory = await getApplicationDocumentsDirectory();
      final String filename =
          'final_report_B1_B2_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
      final File file = File('${directory.path}/$filename');
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles(<XFile>[XFile(file.path)],
          subject: 'Final EV Charging Report');
      _toast('Final Excel report generated.');
    } catch (_) {
      _toast('Admin export failed. Please retry.');
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  void _writeWingSheet(
      Excel excel, String sheetName, List<ChargingSession> rows) {
    final Sheet sheet = excel[sheetName];
    sheet.appendRow(<CellValue>[
      TextCellValue('Name'),
      TextCellValue('Wing'),
      TextCellValue('Floor'),
      TextCellValue('Flat Number'),
      TextCellValue('Charging Point'),
      TextCellValue('Point Key'),
      TextCellValue('Vehicle Number'),
      TextCellValue('Status'),
      TextCellValue('Start Date'),
      TextCellValue('Start Time'),
      TextCellValue('End Date'),
      TextCellValue('End Time'),
      TextCellValue('Start Meter'),
      TextCellValue('End Meter'),
      TextCellValue('Units'),
      TextCellValue('Rate'),
      TextCellValue('Amount'),
    ]);

    for (final ChargingSession s in rows) {
      sheet.appendRow(<CellValue>[
        TextCellValue(s.residentName),
        TextCellValue(s.wing),
        IntCellValue(s.floor),
        TextCellValue(s.flatNumber),
        TextCellValue('P${s.chargingPoint}'),
        TextCellValue(s.pointKey),
        TextCellValue(s.vehicleNumber),
        TextCellValue(s.status),
        TextCellValue(
          s.startTime == null
              ? ''
              : DateFormat('yyyy-MM-dd').format(s.startTime!),
        ),
        TextCellValue(
          s.startTime == null
              ? ''
              : DateFormat('HH:mm:ss').format(s.startTime!),
        ),
        TextCellValue(
          s.endTime == null ? '' : DateFormat('yyyy-MM-dd').format(s.endTime!),
        ),
        TextCellValue(
          s.endTime == null ? '' : DateFormat('HH:mm:ss').format(s.endTime!),
        ),
        DoubleCellValue(s.startMeter),
        DoubleCellValue(s.endMeter),
        DoubleCellValue(s.units),
        DoubleCellValue(s.ratePerUnit),
        DoubleCellValue(s.amount),
      ]);
    }
  }

  void _writeSummarySheet(
      Excel excel, List<ChargingSession> b1, List<ChargingSession> b2) {
    final Sheet sheet = excel['Summary'];
    sheet.appendRow(<CellValue>[
      TextCellValue('Wing'),
      TextCellValue('Sessions'),
      TextCellValue('Units (kWh)'),
      TextCellValue('Amount (INR)'),
    ]);
    _appendSummaryRow(sheet, 'B1', b1);
    _appendSummaryRow(sheet, 'B2', b2);
    _appendSummaryRow(sheet, 'TOTAL', <ChargingSession>[...b1, ...b2]);
  }

  void _appendSummaryRow(
      Sheet sheet, String label, List<ChargingSession> sessions) {
    final List<ChargingSession> completed =
        sessions.where((ChargingSession s) => s.status == 'completed').toList();
    final double totalUnits =
        completed.fold<double>(0, (double p, ChargingSession e) => p + e.units);
    final double totalAmount = completed.fold<double>(
        0, (double p, ChargingSession e) => p + e.amount);
    sheet.appendRow(<CellValue>[
      TextCellValue(label),
      IntCellValue(completed.length),
      DoubleCellValue(totalUnits),
      DoubleCellValue(totalAmount),
    ]);
  }

  String _csv(String value) => '"${value.replaceAll('"', '""')}"';

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _successDialog(String message) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Success'),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _chargingDurationText(DateTime? startedAt) {
    if (startedAt == null) {
      return '-';
    }
    final Duration d = DateTime.now().difference(startedAt);
    final int hours = d.inHours;
    final int mins = d.inMinutes.remainder(60);
    return '${hours}h ${mins}m';
  }

  void _hydrateProfile(Map<String, dynamic> profile, String email) {
    if (_prefilledFromProfile) {
      return;
    }
    _prefilledFromProfile = true;
    _displayName = (profile['name'] ?? '').toString();
    _displayEmail = email;
    _isAdmin = (profile['role'] ?? '') == 'admin';
    if (_displayName.isNotEmpty) {
      _nameController.text = _displayName;
    }
    final String wing = (profile['wing'] ?? '').toString().toUpperCase();
    final String flat = (profile['flatNumber'] ?? '').toString().toUpperCase();
    final String vehicle =
        (profile['vehicleNumber'] ?? '').toString().toUpperCase();
    if (wing == 'B1' || wing == 'B2') {
      _selectedWing = wing;
    }
    if (flat.isNotEmpty) {
      _flatNumberController.text = flat;
    }
    if (vehicle.isNotEmpty) {
      _vehicleController.text = vehicle;
    }
  }

  void _showProfileSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _displayName.isEmpty ? 'Profile' : _displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 6),
                Text(_displayEmail),
                const SizedBox(height: 6),
                Text(
                    'Wing: $_selectedWing  Flat: ${_flatNumberController.text}'),
                Text('Role: ${_isAdmin ? 'Admin' : 'Resident'}'),
              ],
            ),
          ),
        );
      },
    );
  }

  void _autoSelectOccupiedPointOnLoad(Map<String, PointSlotStatus> slotMap) {
    if (_didAutoSelectOnLoad) {
      return;
    }
    _didAutoSelectOnLoad = true;

    PointSlotStatus? latest;
    for (final PointSlotStatus status in slotMap.values) {
      if (!status.occupied) {
        continue;
      }
      if (latest == null) {
        latest = status;
        continue;
      }
      final DateTime latestTime =
          latest.startedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final DateTime currentTime =
          status.startedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      if (currentTime.isAfter(latestTime)) {
        latest = status;
      }
    }

    final String key = latest?.pointKey ?? '';
    if (key.isEmpty || key == _selectedPointKey) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final List<String> parts = key.split('-P');
      setState(() {
        _selectedWing = parts.first;
        _selectedPoint = int.tryParse(parts.last) ?? 1;
      });
    });
  }

  Widget _pointBoard(Map<String, PointSlotStatus> slotMap) {
    final List<String> keys = <String>['B1-P1', 'B1-P2', 'B2-P1', 'B2-P2'];
    final int occupiedCount =
        keys.where((String key) => slotMap[key]?.occupied == true).length;
    final int availableCount = keys.length - occupiedCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Charging Station Availability',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Wrap(
          spacing: 8,
          runSpacing: 6,
          children: <Widget>[
            _LegendChip(label: 'Available', color: Colors.green),
            _LegendChip(label: 'Occupied', color: Colors.red),
            _LegendChip(label: 'Selected', color: Colors.teal),
          ],
        ),
        const SizedBox(height: 6),
        Card(
          child: ListTile(
            dense: true,
            title:
                Text('Available: $availableCount   Occupied: $occupiedCount'),
            subtitle: const Text('Tap an available point card to select it'),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: keys.map((String key) {
            final PointSlotStatus? status = slotMap[key];
            final bool occupied = status?.occupied == true;
            final bool selected = key == _selectedPointKey;
            final Color bg = selected
                ? Colors.teal.shade100
                : occupied
                    ? Colors.red.shade100
                    : Colors.green.shade100;
            return SizedBox(
              width: 160,
              child: InkWell(
                onTap: () {
                  final List<String> parts = key.split('-P');
                  setState(() {
                    _selectedWing = parts.first;
                    _selectedPoint = int.tryParse(parts.last) ?? 1;
                  });
                  if (occupied) {
                    _toast(
                      '$key is currently occupied. You can use Stop Charging for this point.',
                    );
                  }
                },
                child: Card(
                  color: bg,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          key,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(occupied ? 'Unavailable' : 'Available'),
                        if (occupied && status != null) ...<Widget>[
                          Text(
                            status.vehicleNumber.isEmpty
                                ? 'Vehicle: -'
                                : 'Vehicle: ${status.vehicleNumber}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'By: ${status.residentName} (${status.flatNumber})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Time: ${_chargingDurationText(status.startedAt)}',
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;
    final String uid = user?.uid ?? '';
    if (uid.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Please login to access charging sessions.')),
      );
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream:
          FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (BuildContext context,
          AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>>
              profileSnapshot) {
        if (profileSnapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Charging Session Entry')),
            body: Center(
              child: Text('Profile load failed: ${profileSnapshot.error}'),
            ),
          );
        }
        if (!profileSnapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final Map<String, dynamic> profile =
            profileSnapshot.data!.data() ?? <String, dynamic>{};
        _hydrateProfile(profile, user?.email ?? '');
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('appConfig')
              .doc('rates')
              .snapshots(),
          builder: (BuildContext context,
              AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>>
                  rateSnapshot) {
            final double effectiveRate = ((rateSnapshot.data?.data() ??
                        <String, dynamic>{})['ratePerUnit'] as num?)
                    ?.toDouble() ??
                AppConfig.ratePerUnitInr;
            return StreamBuilder<Map<String, PointSlotStatus>>(
              stream: _sessionRepository.watchPointStatuses(),
              builder: (BuildContext context,
                  AsyncSnapshot<Map<String, PointSlotStatus>> slotsSnapshot) {
                final Map<String, PointSlotStatus> slotMap =
                    slotsSnapshot.data ?? <String, PointSlotStatus>{};
                _autoSelectOccupiedPointOnLoad(slotMap);
                final PointSlotStatus? selectedSlot =
                    slotMap[_selectedPointKey];
                final bool selectedPointOccupied =
                    selectedSlot?.occupied == true;
                return StreamBuilder<ChargingSession?>(
                  stream: _sessionRepository
                      .watchActiveSessionForPoint(_selectedPointKey),
                  builder: (BuildContext context,
                      AsyncSnapshot<ChargingSession?> activeSnapshot) {
                    final ChargingSession? activeSession = activeSnapshot.data;
                    final bool hasActiveSession = activeSession != null;
                    return Scaffold(
                      appBar: AppBar(
                        title: Text(
                          _displayName.isEmpty
                              ? 'Charging Session Entry'
                              : 'Charging Session - $_displayName',
                        ),
                        actions: <Widget>[
                          IconButton(
                            onPressed: _showProfileSheet,
                            icon: const Icon(Icons.account_circle),
                          ),
                        ],
                      ),
                      body: ListView(
                        padding: const EdgeInsets.all(16),
                        children: <Widget>[
                          _pointBoard(slotMap),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                                labelText: 'Resident Name'),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: _selectedWing,
                            decoration:
                                const InputDecoration(labelText: 'Wing'),
                            items: const <DropdownMenuItem<String>>[
                              DropdownMenuItem<String>(
                                  value: 'B1', child: Text('B1')),
                              DropdownMenuItem<String>(
                                  value: 'B2', child: Text('B2')),
                            ],
                            onChanged: (String? value) {
                              if (value == null) {
                                return;
                              }
                              setState(() {
                                _selectedWing = value;
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _flatNumberController,
                            decoration: const InputDecoration(
                              labelText: 'Flat Number',
                              hintText: 'e.g. 1203 or 05-03',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _vehicleController,
                            decoration: const InputDecoration(
                                labelText: 'Vehicle Number'),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _startMeterController,
                            keyboardType: TextInputType.number,
                            enabled: !hasActiveSession,
                            decoration: InputDecoration(
                              labelText: 'Start Meter Reading (kWh)',
                              helperText: hasActiveSession
                                  ? 'Start meter locked while session is active.'
                                  : 'Enter this only while starting charging.',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _endMeterController,
                            keyboardType: TextInputType.number,
                            enabled: hasActiveSession,
                            decoration: InputDecoration(
                              labelText: 'End Meter Reading (kWh)',
                              helperText: hasActiveSession
                                  ? 'Enter end meter, then tap Stop Charging.'
                                  : 'Enabled only after charging has started.',
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blueGrey.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.blueGrey.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              'Rate per Unit (admin config): INR ${effectiveRate.toStringAsFixed(2)}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Selected: $_selectedPointKey | '
                            '${selectedPointOccupied ? 'Unavailable' : 'Available'}',
                          ),
                          if (selectedPointOccupied && selectedSlot != null)
                            Text(
                              'Occupied by ${selectedSlot.residentName} (${selectedSlot.flatNumber})',
                            ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: (_isProcessingSession ||
                                    selectedPointOccupied ||
                                    hasActiveSession)
                                ? null
                                : () => _startCharging(effectiveRate),
                            child: const Text('Start Charging'),
                          ),
                          const SizedBox(height: 8),
                          FilledButton(
                            onPressed:
                                (_isProcessingSession || !hasActiveSession)
                                    ? null
                                    : () => _stopCharging(activeSession),
                            child: const Text('Stop Charging'),
                          ),
                          if (hasActiveSession) ...<Widget>[
                            const SizedBox(height: 8),
                            Text(
                              'Active session for ${activeSession.pointKey}: '
                              '${activeSession.vehicleNumber} | '
                              'Start Meter ${activeSession.startMeter.toStringAsFixed(2)}',
                            ),
                          ],
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed:
                                _isExporting ? null : _exportMyHistoryCsv,
                            icon: const Icon(Icons.download),
                            label: Text(_isExporting
                                ? 'Exporting...'
                                : 'Download My History'),
                          ),
                          if (_isAdmin) ...<Widget>[
                            const SizedBox(height: 8),
                            FilledButton.icon(
                              onPressed:
                                  _isExporting ? null : _exportAdminB1B2Excel,
                              icon: const Icon(Icons.admin_panel_settings),
                              label: Text(
                                _isExporting
                                    ? 'Exporting...'
                                    : 'Download Final Excel Report',
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          TextField(
                            controller: _historyFilterController,
                            decoration: const InputDecoration(
                              labelText: 'Vehicle History Filter',
                              hintText: 'Enter vehicle number (optional)',
                            ),
                            onChanged: (String value) {
                              setState(() {
                                _historyFilter = value.trim().toUpperCase();
                              });
                            },
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Flat-wise History',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          StreamBuilder<List<ChargingSession>>(
                            stream: _sessionRepository.watchRecentSessions(
                              ownerUid: _isAdmin ? null : uid,
                              vehicleFilter: _historyFilter,
                              wingFilter: _isAdmin ? _selectedWing : null,
                              flatNumberFilter: _isAdmin ? _flatFilter : null,
                            ),
                            builder: (BuildContext context,
                                AsyncSnapshot<List<ChargingSession>> snapshot) {
                              if (snapshot.hasError) {
                                return Text(
                                    'History load failed: ${snapshot.error}');
                              }
                              if (!snapshot.hasData) {
                                return const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: CircularProgressIndicator(),
                                );
                              }
                              final List<ChargingSession> sessions =
                                  snapshot.data!;
                              if (sessions.isEmpty) {
                                return const Text('No session history yet.');
                              }
                              final List<ChargingSession> completed = sessions
                                  .where((ChargingSession s) =>
                                      s.status == 'completed')
                                  .toList();
                              final Map<String, _MonthlySummary> monthSummary =
                                  <String, _MonthlySummary>{};
                              for (final ChargingSession s in completed) {
                                final DateTime at = s.endTime ?? s.createdAt;
                                final String key =
                                    DateFormat('yyyy-MM').format(at);
                                final _MonthlySummary summary =
                                    monthSummary.putIfAbsent(
                                  key,
                                  () => _MonthlySummary(month: key),
                                );
                                summary.units += s.units;
                                summary.amount += s.amount;
                                summary.sessions += 1;
                              }
                              final List<_MonthlySummary> summaryRows =
                                  monthSummary.values.toList()
                                    ..sort((_MonthlySummary a,
                                            _MonthlySummary b) =>
                                        b.month.compareTo(a.month));
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  if (_flatFilter.isNotEmpty) ...<Widget>[
                                    const Text(
                                      'Monthly Consumption Summary',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 6),
                                    if (summaryRows.isEmpty)
                                      const Text(
                                          'No completed sessions for summary.')
                                    else
                                      ...summaryRows.map((_MonthlySummary m) {
                                        final DateTime monthDate =
                                            DateTime.parse('${m.month}-01');
                                        return Card(
                                          color: Colors.teal
                                              .withValues(alpha: 0.08),
                                          child: ListTile(
                                            title: Text(
                                              DateFormat('MMMM yyyy')
                                                  .format(monthDate),
                                            ),
                                            subtitle: Text(
                                              'Sessions: ${m.sessions} | Units: ${m.units.toStringAsFixed(2)} kWh',
                                            ),
                                            trailing: Text(
                                              'INR ${m.amount.toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        );
                                      }),
                                    const SizedBox(height: 10),
                                  ],
                                  const Text(
                                    'Detailed Sessions',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 6),
                                  ...sessions.map((ChargingSession s) {
                                    final DateTime shownAt =
                                        s.endTime ?? s.createdAt;
                                    return Card(
                                      child: ListTile(
                                        title: Text(
                                          '${s.vehicleNumber} | ${s.pointKey} | ${s.status.toUpperCase()}',
                                        ),
                                        subtitle: Text(
                                          '${s.wing} ${s.flatNumber} | ${DateFormat('dd MMM yyyy, hh:mm a').format(shownAt)}\n'
                                          'Start: ${s.startMeter.toStringAsFixed(2)}  End: ${s.endMeter.toStringAsFixed(2)}  Units: ${s.units.toStringAsFixed(2)} kWh',
                                        ),
                                        trailing: Text(
                                          'INR ${s.amount.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    );
                                  }),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }
}

class _MonthlySummary {
  _MonthlySummary({required this.month});

  final String month;
  int sessions = 0;
  double units = 0;
  double amount = 0;
}
