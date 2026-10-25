import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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
  static final RegExp _vehiclePattern =
      RegExp(r'^[A-Z]{2}[0-9]{1,2}[A-Z]{0,3}[0-9]{1,4}$');

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _wingController = TextEditingController();
  final TextEditingController _flatNumberController = TextEditingController();
  final TextEditingController _guestNameController = TextEditingController();
  final TextEditingController _guestVehicleController = TextEditingController();
  final TextEditingController _manualVehicleController =
      TextEditingController();
  final TextEditingController _startMeterController = TextEditingController();
  final TextEditingController _endMeterController = TextEditingController();

  bool _isProcessingSession = false;
  bool _didAutoSelectOnLoad = false;
  bool _prefilledFromProfile = false;
  bool _profileVehicleEnsured = false;
  bool _useGuestVehicle = false;
  String _displayName = '';
  String _displayEmail = '';
  bool _isAdmin = false;
  List<String> _savedVehicles = <String>[];
  String? _selectedVehicle;
  String _selectedWing = 'B1';
  String _profileWing = 'B1';
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
    _wingController.dispose();
    _flatNumberController.dispose();
    _guestNameController.dispose();
    _guestVehicleController.dispose();
    _manualVehicleController.dispose();
    _startMeterController.dispose();
    _endMeterController.dispose();
    super.dispose();
  }

  String get _selectedPointKey =>
      '${_selectedWing.toUpperCase()}-P$_selectedPoint';
  String get _flatFilter => _flatNumberController.text.trim().toUpperCase();
  String get _effectiveWing => _isAdmin ? _selectedWing : _profileWing;

  double _meter(TextEditingController controller) =>
      double.tryParse(controller.text.trim()) ?? 0;

  int _deriveFloorFromFlat(String flat) {
    final RegExp floorPattern = RegExp(r'^(\d{1,2})');
    final Match? match = floorPattern.firstMatch(flat.trim());
    final int parsed = int.tryParse(match?.group(1) ?? '') ?? 0;
    return parsed;
  }

  String _normalizeVehicle(String vehicle) {
    return vehicle.trim().toUpperCase().replaceAll(RegExp(r'[\s\-]'), '');
  }

  bool _isValidVehicle(String vehicle) {
    return _vehiclePattern.hasMatch(_normalizeVehicle(vehicle));
  }

  String _effectiveVehicleNumber() {
    if (_useGuestVehicle) {
      return _normalizeVehicle(_guestVehicleController.text);
    }
    final String manualVehicle =
        _normalizeVehicle(_manualVehicleController.text);
    if (manualVehicle.isNotEmpty) {
      return manualVehicle;
    }
    return _normalizeVehicle(_selectedVehicle ?? '');
  }

  Future<void> _startCharging(double ratePerUnit) async {
    if (!widget.firebaseReady) {
      _toast('Firebase not configured yet.');
      return;
    }

    final String name = _nameController.text.trim();
    final String guestName = _guestNameController.text.trim();
    final String ownerUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final String sessionWing = _effectiveWing;
    final String flat = _flatFilter;
    final String vehicle = _effectiveVehicleNumber();
    final double startMeter = _meter(_startMeterController);
    final String residentName =
        _useGuestVehicle ? (guestName.isEmpty ? name : guestName) : name;
    if (residentName.isEmpty || flat.isEmpty || vehicle.isEmpty) {
      _toast('Profile details and vehicle number are required.');
      return;
    }
    if (sessionWing.isEmpty) {
      _toast('Wing is missing in profile. Contact admin.');
      return;
    }
    if (!_isValidVehicle(vehicle)) {
      _toast('Enter a valid vehicle number (example: MH12AB1234).');
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
        residentName: residentName,
        wing: sessionWing,
        floor: _deriveFloorFromFlat(flat),
        flatNumber: flat,
        chargingPoint: _selectedPoint,
        vehicleNumber: vehicle,
        isGuestVehicle: _useGuestVehicle,
        startMeter: startMeter,
        ratePerUnit: ratePerUnit,
      );
      if (!mounted) {
        return;
      }
      _endMeterController.clear();
      if (_useGuestVehicle) {
        _guestNameController.clear();
        _guestVehicleController.clear();
      }
      _manualVehicleController.clear();
      await _successDialog('Charging started for $_selectedPointKey.');
    } on FirebaseException catch (e) {
      _toast(_friendlySessionError(e));
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
      _toast(_friendlySessionError(e));
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingSession = false;
        });
      }
    }
  }

  String _friendlySessionError(FirebaseException error) {
    if (error.code == 'permission-denied') {
      return 'Permission denied for charging update. Please login again and retry.';
    }
    if (error.code == 'slot-occupied') {
      return error.message ?? 'Selected slot is currently unavailable.';
    }
    if (error.code == 'invalid-meter') {
      return error.message ?? 'Meter reading is invalid.';
    }
    if (error.code == 'failed-precondition') {
      return 'Database index/config is still updating. Please retry in a minute.';
    }
    return error.message ?? error.code;
  }

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

  Future<void> _ensureVehicleSchema(
      String uid, Map<String, dynamic> profile) async {
    if (_profileVehicleEnsured) {
      return;
    }
    _profileVehicleEnsured = true;
    final List<String> vehicles =
        ((profile['vehicles'] as List<dynamic>?) ?? <dynamic>[])
            .map((dynamic e) => _normalizeVehicle(e.toString()))
            .where((String v) => v.isNotEmpty)
            .toSet()
            .toList();
    final String legacyVehicle = _normalizeVehicle(
      (profile['vehicleNumber'] ?? '').toString(),
    );
    final String defaultVehicle = _normalizeVehicle(
      (profile['defaultVehicle'] ?? '').toString(),
    );
    if (legacyVehicle.isNotEmpty && !vehicles.contains(legacyVehicle)) {
      vehicles.add(legacyVehicle);
    }
    if (vehicles.isEmpty) {
      return;
    }
    final String resolvedDefault =
        vehicles.contains(defaultVehicle) ? defaultVehicle : vehicles.first;
    if ((profile['vehicles'] as List<dynamic>?) == null ||
        profile['defaultVehicle'] != resolvedDefault) {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        <String, dynamic>{
          'vehicles': vehicles,
          'defaultVehicle': resolvedDefault,
          'vehicleNumber': resolvedDefault,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
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
    final String legacyVehicle = _normalizeVehicle(
      (profile['vehicleNumber'] ?? '').toString(),
    );
    final String defaultVehicle = _normalizeVehicle(
      (profile['defaultVehicle'] ?? '').toString(),
    );
    final List<String> vehicles =
        ((profile['vehicles'] as List<dynamic>?) ?? <dynamic>[])
            .map((dynamic e) => _normalizeVehicle(e.toString()))
            .where((String value) => value.isNotEmpty)
            .toSet()
            .toList();
    if (legacyVehicle.isNotEmpty && !vehicles.contains(legacyVehicle)) {
      vehicles.add(legacyVehicle);
    }
    if (wing == 'B1' || wing == 'B2') {
      _profileWing = wing;
      _selectedWing = wing;
      _wingController.text = wing;
    } else if (_wingController.text.isEmpty) {
      _wingController.text = _selectedWing;
    }
    if (flat.isNotEmpty) {
      _flatNumberController.text = flat;
    }
    if (vehicles.isNotEmpty) {
      _savedVehicles = vehicles;
      _selectedVehicle =
          vehicles.contains(defaultVehicle) ? defaultVehicle : vehicles.first;
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

    final Iterable<PointSlotStatus> allowedStatuses = _isAdmin
        ? slotMap.values
        : slotMap.values
            .where((PointSlotStatus s) => s.pointKey.startsWith(_profileWing));
    PointSlotStatus? latest;
    for (final PointSlotStatus status in allowedStatuses) {
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
        _selectedWing = _isAdmin ? parts.first : _profileWing;
        _wingController.text = _selectedWing;
        _selectedPoint = int.tryParse(parts.last) ?? 1;
      });
    });
  }

  void _autoSelectMyActivePoint(ChargingSession? session) {
    if (session == null || session.pointKey == _selectedPointKey) {
      return;
    }
    final List<String> parts = session.pointKey.split('-P');
    if (parts.length != 2) {
      return;
    }
    final String wing = parts.first;
    final int point = int.tryParse(parts.last) ?? 1;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedWing = _isAdmin ? wing : _profileWing;
        _wingController.text = _selectedWing;
        _selectedPoint = point;
      });
    });
  }

  Widget _pointBoard(Map<String, PointSlotStatus> slotMap) {
    final List<String> allKeys = <String>['B1-P1', 'B1-P2', 'B2-P1', 'B2-P2'];
    final List<String> keys = _isAdmin
        ? allKeys
        : allKeys
            .where((String key) => key.startsWith(_profileWing))
            .toList(growable: false);
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
                    _selectedWing = _isAdmin ? parts.first : _profileWing;
                    _wingController.text = _selectedWing;
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
        _ensureVehicleSchema(uid, profile);
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
                  stream: _sessionRepository.watchActiveSessionForOwner(uid),
                  builder: (BuildContext context,
                      AsyncSnapshot<ChargingSession?> myActiveSnapshot) {
                    final ChargingSession? myActiveSession =
                        myActiveSnapshot.data;
                    _autoSelectMyActivePoint(myActiveSession);
                    return StreamBuilder<ChargingSession?>(
                      stream: _sessionRepository
                          .watchActiveSessionForPoint(_selectedPointKey),
                      builder: (BuildContext context,
                          AsyncSnapshot<ChargingSession?> activeSnapshot) {
                        final ChargingSession? activeSession =
                            activeSnapshot.data;
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
                                readOnly: true,
                                decoration: const InputDecoration(
                                  labelText: 'Flat Owner Name',
                                  helperText: 'Auto-filled from your profile',
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _wingController,
                                readOnly: true,
                                decoration: const InputDecoration(
                                  labelText: 'Wing',
                                  helperText: 'Auto-filled from your profile',
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _flatNumberController,
                                readOnly: true,
                                decoration: const InputDecoration(
                                  labelText: 'Flat Number',
                                  helperText: 'Auto-filled from your profile',
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (_savedVehicles.isNotEmpty) ...<Widget>[
                                DropdownButtonFormField<String>(
                                  initialValue: _selectedVehicle,
                                  decoration: const InputDecoration(
                                    labelText: 'Saved Vehicle',
                                  ),
                                  items: _savedVehicles
                                      .map((String vehicle) =>
                                          DropdownMenuItem<String>(
                                            value: vehicle,
                                            child: Text(vehicle),
                                          ))
                                      .toList(),
                                  onChanged: _useGuestVehicle
                                      ? null
                                      : (String? value) {
                                          if (value == null) {
                                            return;
                                          }
                                          setState(() {
                                            _selectedVehicle = value;
                                          });
                                        },
                                ),
                                const SizedBox(height: 8),
                              ],
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Charging a Guest Vehicle'),
                                subtitle: const Text(
                                    'Bill will still be linked to your flat/account'),
                                value: _useGuestVehicle,
                                onChanged: (bool value) {
                                  setState(() {
                                    _useGuestVehicle = value;
                                  });
                                },
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _guestNameController,
                                enabled: _useGuestVehicle,
                                decoration: const InputDecoration(
                                  labelText: 'Guest Name (Optional)',
                                  helperText:
                                      'If empty, flat owner name will be used.',
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _guestVehicleController,
                                textCapitalization:
                                    TextCapitalization.characters,
                                enabled: _useGuestVehicle,
                                decoration: InputDecoration(
                                  labelText: _useGuestVehicle
                                      ? 'Guest Vehicle Number'
                                      : 'Vehicle Number',
                                  helperText: _useGuestVehicle
                                      ? 'Guest vehicle is one-time and not saved.'
                                      : (_selectedVehicle == null
                                          ? 'No saved vehicle found. Enable guest vehicle to continue.'
                                          : 'Using saved vehicle ${_selectedVehicle!}'),
                                ),
                              ),
                              if (!_useGuestVehicle) ...<Widget>[
                                const SizedBox(height: 8),
                                TextField(
                                  controller: _manualVehicleController,
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  decoration: const InputDecoration(
                                    labelText: 'Vehicle Number (Manual Entry)',
                                    helperText:
                                        'Use this if your vehicle is not in saved list.',
                                  ),
                                ),
                              ],
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
                                  color:
                                      Colors.blueGrey.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color:
                                        Colors.blueGrey.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Text(
                                  'Rate per Unit (admin config): INR ${effectiveRate.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Note: Rates may change subject to changes in MSEB rates and Society Management decision.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.black54,
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
                              if (myActiveSession != null &&
                                  myActiveSession.pointKey != _selectedPointKey)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    'You have an active session at ${myActiveSession.pointKey}. Point auto-selected for quick stop.',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              if (hasActiveSession) ...<Widget>[
                                const SizedBox(height: 8),
                                Text(
                                  'Active session for ${activeSession.pointKey}: '
                                  '${activeSession.vehicleNumber}${activeSession.isGuestVehicle ? ' (Guest)' : ''} | '
                                  'Start Meter ${activeSession.startMeter.toStringAsFixed(2)}',
                                ),
                              ],
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
