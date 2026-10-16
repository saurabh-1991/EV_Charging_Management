import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class SlotBookingPage extends StatefulWidget {
  const SlotBookingPage({super.key});

  static const String routeName = '/booking';

  @override
  State<SlotBookingPage> createState() => _SlotBookingPageState();
}

class _SlotBookingPageState extends State<SlotBookingPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _flatController = TextEditingController();
  final TextEditingController _vehicleController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  bool _prefilledFromProfile = false;
  String _role = 'resident';
  String _profileWing = 'B1';

  static const List<String> _pointKeys = <String>[
    'B1-P1',
    'B1-P2',
    'B2-P1',
    'B2-P2',
  ];

  static const List<int> _slotStartHours = <int>[
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
    19,
    20,
    21,
    22,
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _flatController.dispose();
    _vehicleController.dispose();
    super.dispose();
  }

  String get _dateKey => DateFormat('yyyy-MM-dd').format(_selectedDate);
  String get _flatFilter => _flatController.text.trim().toUpperCase();
  String get _vehicleFilter => _vehicleController.text.trim().toUpperCase();
  String get _currentUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  List<String> _allowedPoints() {
    if (_role == 'admin') {
      return _pointKeys;
    }
    return _pointKeys.where((String k) => k.startsWith(_profileWing)).toList();
  }

  void _hydrateProfile(Map<String, dynamic> profile) {
    if (_prefilledFromProfile) {
      return;
    }
    _prefilledFromProfile = true;
    final String name = (profile['name'] ?? '').toString().trim();
    final String flat =
        (profile['flatNumber'] ?? '').toString().trim().toUpperCase();
    final String vehicle =
        (profile['vehicleNumber'] ?? '').toString().trim().toUpperCase();
    _role = (profile['role'] ?? 'resident').toString();
    final String wing = (profile['wing'] ?? 'B1').toString().toUpperCase();
    _profileWing = wing == 'B2' ? 'B2' : 'B1';
    if (name.isNotEmpty) {
      _nameController.text = name;
    }
    if (flat.isNotEmpty) {
      _flatController.text = flat;
    }
    if (vehicle.isNotEmpty) {
      _vehicleController.text = vehicle;
    }
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _selectedDate = DateTime(picked.year, picked.month, picked.day);
    });
  }

  Future<void> _bookSlot({
    required String pointKey,
    required int startHour,
  }) async {
    final String name = _nameController.text.trim();
    final String ownerUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final String flat = _flatController.text.trim().toUpperCase();
    final String vehicle = _vehicleController.text.trim().toUpperCase();
    if (name.isEmpty || flat.isEmpty || vehicle.isEmpty || ownerUid.isEmpty) {
      _toast('Enter name, flat number, and vehicle number first.');
      return;
    }

    final int endHour = startHour + 1;
    final String slotId = '${_dateKey}_${pointKey}_$startHour';
    final DateTime startAt = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      startHour,
    );
    final DateTime endAt = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      endHour,
    );

    try {
      final DocumentReference<Map<String, dynamic>> ref =
          _firestore.collection('slotBookings').doc(slotId);
      await _firestore.runTransaction((Transaction txn) async {
        final DocumentSnapshot<Map<String, dynamic>> existing =
            await txn.get(ref);
        if (existing.exists && existing.data()?['status'] == 'booked') {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'slot-booked',
            message: 'Selected slot is already booked.',
          );
        }
        txn.set(ref, <String, dynamic>{
          'slotId': slotId,
          'dateKey': _dateKey,
          'pointKey': pointKey,
          'wing': pointKey.split('-').first,
          'chargingPoint': pointKey.endsWith('P1') ? 1 : 2,
          'startHour': startHour,
          'endHour': endHour,
          'timeLabel': _timeLabel(startHour),
          'residentName': name,
          'ownerUid': ownerUid,
          'flatNumber': flat,
          'vehicleNumber': vehicle,
          'status': 'booked',
          'startAt': Timestamp.fromDate(startAt),
          'endAt': Timestamp.fromDate(endAt),
          'createdAt': Timestamp.now(),
        });
      });
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('Slot Booked'),
          content: Text('Booked $pointKey for ${_timeLabel(startHour)}'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } on FirebaseException catch (e) {
      _toast(e.message ?? e.code);
    }
  }

  Future<void> _cancelBooking(String bookingId) async {
    await _firestore.collection('slotBookings').doc(bookingId).update(
      <String, dynamic>{
        'status': 'cancelled',
        'updatedAt': Timestamp.now(),
      },
    );
    _toast('Booking cancelled.');
  }

  Future<void> _showRescheduleDialog(
    QueryDocumentSnapshot<Map<String, dynamic>> bookingDoc,
    Map<String, bool> occupiedNow,
  ) async {
    DateTime pickedDate = (bookingDoc.data()['startAt'] as Timestamp).toDate();
    String pickedPoint = (bookingDoc.data()['pointKey'] ?? '').toString();
    int pickedStartHour =
        (bookingDoc.data()['startHour'] as num?)?.toInt() ?? 6;

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder:
              (BuildContext statefulDialogContext, StateSetter setDialogState) {
            return AlertDialog(
              title: const Text('Reschedule Booking'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: () async {
                      final DateTime? d = await showDatePicker(
                        context: statefulDialogContext,
                        initialDate: pickedDate,
                        firstDate:
                            DateTime.now().subtract(const Duration(days: 1)),
                        lastDate: DateTime.now().add(const Duration(days: 60)),
                      );
                      if (d != null) {
                        setDialogState(() {
                          pickedDate = DateTime(d.year, d.month, d.day);
                        });
                      }
                    },
                    icon: const Icon(Icons.calendar_today),
                    label: Text(DateFormat('dd MMM yyyy').format(pickedDate)),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: pickedPoint,
                    decoration: const InputDecoration(labelText: 'Point'),
                    items: _allowedPoints()
                        .map((String key) => DropdownMenuItem<String>(
                              value: key,
                              child: Text(key),
                            ))
                        .toList(),
                    onChanged: (String? value) {
                      if (value == null) {
                        return;
                      }
                      setDialogState(() {
                        pickedPoint = value;
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    initialValue: pickedStartHour,
                    decoration: const InputDecoration(labelText: 'Time'),
                    items: _slotStartHours
                        .map((int h) => DropdownMenuItem<int>(
                              value: h,
                              child: Text(_timeLabel(h)),
                            ))
                        .toList(),
                    onChanged: (int? value) {
                      if (value == null) {
                        return;
                      }
                      setDialogState(() {
                        pickedStartHour = value;
                      });
                    },
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final String newDateKey =
                        DateFormat('yyyy-MM-dd').format(pickedDate);
                    final String newSlotId =
                        '${newDateKey}_${pickedPoint}_$pickedStartHour';
                    final bool blockedByActiveCharging =
                        _isBlockedByCurrentChargingForDate(
                      selectedDate: pickedDate,
                      occupiedNow: occupiedNow[pickedPoint] == true,
                      startHour: pickedStartHour,
                    );
                    final DocumentSnapshot<Map<String, dynamic>> existing =
                        await _firestore
                            .collection('slotBookings')
                            .doc(newSlotId)
                            .get();
                    final bool alreadyBooked = existing.exists &&
                        existing.data()?['status'] == 'booked' &&
                        newSlotId != bookingDoc.id;
                    if (alreadyBooked || blockedByActiveCharging) {
                      _toast(
                        alreadyBooked
                            ? 'Selected slot is already booked.'
                            : 'Selected slot is blocked by current charging.',
                      );
                      return;
                    }

                    final int endHour = pickedStartHour + 1;
                    final DateTime startAt = DateTime(
                      pickedDate.year,
                      pickedDate.month,
                      pickedDate.day,
                      pickedStartHour,
                    );
                    final DateTime endAt = DateTime(
                      pickedDate.year,
                      pickedDate.month,
                      pickedDate.day,
                      endHour,
                    );
                    final Map<String, dynamic> old = bookingDoc.data();
                    final WriteBatch batch = _firestore.batch();
                    batch.update(bookingDoc.reference, <String, dynamic>{
                      'status': 'rescheduled',
                      'rescheduledTo': newSlotId,
                      'updatedAt': Timestamp.now(),
                    });
                    batch.set(
                      _firestore.collection('slotBookings').doc(newSlotId),
                      <String, dynamic>{
                        'slotId': newSlotId,
                        'dateKey': newDateKey,
                        'pointKey': pickedPoint,
                        'wing': pickedPoint.split('-').first,
                        'chargingPoint': pickedPoint.endsWith('P1') ? 1 : 2,
                        'startHour': pickedStartHour,
                        'endHour': endHour,
                        'timeLabel': _timeLabel(pickedStartHour),
                        'residentName': old['residentName'],
                        'flatNumber': old['flatNumber'],
                        'vehicleNumber': old['vehicleNumber'],
                        'status': 'booked',
                        'startAt': Timestamp.fromDate(startAt),
                        'endAt': Timestamp.fromDate(endAt),
                        'createdAt': Timestamp.now(),
                        'rescheduledFrom': bookingDoc.id,
                      },
                    );
                    await batch.commit();
                    if (!dialogContext.mounted) {
                      return;
                    }
                    Navigator.of(dialogContext).pop();
                    _toast('Booking rescheduled successfully.');
                  },
                  child: const Text('Reschedule'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _timeLabel(int startHour) {
    final DateTime start = DateTime(2000, 1, 1, startHour);
    final DateTime end = DateTime(2000, 1, 1, startHour + 1);
    return '${DateFormat('hh:mm a').format(start)} - ${DateFormat('hh:mm a').format(end)}';
  }

  bool _isPastSlot(int startHour) {
    final DateTime now = DateTime.now();
    final DateTime slotStart = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      startHour,
    );
    return slotStart.isBefore(DateTime(now.year, now.month, now.day, now.hour));
  }

  bool _isBlockedByCurrentCharging({
    required bool occupiedNow,
    required int startHour,
  }) {
    if (!occupiedNow) {
      return false;
    }
    final DateTime now = DateTime.now();
    final bool sameDay = _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
    if (!sameDay) {
      return false;
    }
    return startHour <= now.hour;
  }

  bool _isBlockedByCurrentChargingForDate({
    required DateTime selectedDate,
    required bool occupiedNow,
    required int startHour,
  }) {
    if (!occupiedNow) {
      return false;
    }
    final DateTime now = DateTime.now();
    final bool sameDay = selectedDate.year == now.year &&
        selectedDate.month == now.month &&
        selectedDate.day == now.day;
    if (!sameDay) {
      return false;
    }
    return startHour <= now.hour;
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final String uid = _currentUid;
    if (uid.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Please login to book charging slots.')),
      );
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _firestore.collection('users').doc(uid).snapshots(),
      builder: (BuildContext context,
          AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> profileSnap) {
        if (profileSnap.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Charging Slot Booking')),
            body: Center(
                child: Text('Profile load failed: ${profileSnap.error}')),
          );
        }
        if (!profileSnap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        _hydrateProfile(profileSnap.data!.data() ?? <String, dynamic>{});
        final List<String> allowedPoints = _allowedPoints();
        return Scaffold(
          appBar: AppBar(
            title: Text(
              _role == 'admin'
                  ? 'Charging Slot Booking (B1+B2)'
                  : 'Charging Slot Booking ($_profileWing)',
            ),
          ),
          body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _firestore.collection('chargingSlots').snapshots(),
            builder: (BuildContext context,
                AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> slotsSnap) {
              final Map<String, bool> occupiedNow = <String, bool>{};
              for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
                  in slotsSnap.data?.docs ??
                      <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
                occupiedNow[doc.id] = doc.data()['occupied'] == true;
              }

              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _firestore
                    .collection('slotBookings')
                    .where('dateKey', isEqualTo: _dateKey)
                    .where('status', isEqualTo: 'booked')
                    .snapshots(),
                builder: (BuildContext context,
                    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>>
                        bookingSnap) {
                  final Set<String> bookedSlotIds = <String>{};
                  final Map<String, Map<String, dynamic>> bookingBySlot =
                      <String, Map<String, dynamic>>{};
                  for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
                      in bookingSnap.data?.docs ??
                          <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
                    bookedSlotIds.add(doc.id);
                    bookingBySlot[doc.id] = doc.data();
                  }

                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: <Widget>[
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(labelText: 'Name'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _flatController,
                        decoration:
                            const InputDecoration(labelText: 'Flat Number'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _vehicleController,
                        decoration:
                            const InputDecoration(labelText: 'Vehicle Number'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.calendar_today),
                        label: Text(
                            'Date: ${DateFormat('dd MMM yyyy').format(_selectedDate)}'),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Available Booking Tiles',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          _LegendChip(
                              label: 'Available', color: Colors.green.shade200),
                          _LegendChip(
                              label: 'Booked by You',
                              color: Colors.blue.shade200),
                          _LegendChip(
                              label: 'Booked by Others',
                              color: Colors.orange.shade200),
                          _LegendChip(
                              label: 'Unavailable (Active Charging)',
                              color: Colors.red.shade200),
                          _LegendChip(
                              label: 'Past Slot', color: Colors.grey.shade300),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: allowedPoints.expand((String pointKey) {
                          return _slotStartHours
                              .where((int startHour) => !_isPastSlot(startHour))
                              .map((int startHour) {
                            final String slotId =
                                '${_dateKey}_${pointKey}_$startHour';
                            final bool isBooked =
                                bookedSlotIds.contains(slotId);
                            final bool isPast = _isPastSlot(startHour);
                            final bool blockedByActiveCharging =
                                _isBlockedByCurrentCharging(
                              occupiedNow: occupiedNow[pointKey] == true,
                              startHour: startHour,
                            );
                            final Map<String, dynamic>? bookingData =
                                bookingBySlot[slotId];
                            final bool bookedByYou = isBooked &&
                                _flatFilter.isNotEmpty &&
                                _vehicleFilter.isNotEmpty &&
                                (bookingData?['flatNumber'] ?? '')
                                        .toString()
                                        .toUpperCase() ==
                                    _flatFilter &&
                                (bookingData?['vehicleNumber'] ?? '')
                                        .toString()
                                        .toUpperCase() ==
                                    _vehicleFilter;
                            final bool available = !isBooked &&
                                !isPast &&
                                !blockedByActiveCharging;

                            final Color bgColor;
                            if (available) {
                              bgColor = Colors.green.shade100;
                            } else if (bookedByYou) {
                              bgColor = Colors.blue.shade100;
                            } else if (isBooked) {
                              bgColor = Colors.orange.shade100;
                            } else if (blockedByActiveCharging) {
                              bgColor = Colors.red.shade100;
                            } else {
                              bgColor = Colors.grey.shade300;
                            }
                            final String subtitle = available
                                ? 'Available'
                                : bookedByYou
                                    ? 'Booked by You'
                                    : isBooked
                                        ? 'Booked by Others'
                                        : blockedByActiveCharging
                                            ? 'Unavailable due to active charging'
                                            : 'Past Slot';
                            final String byLine = (isBooked &&
                                    bookingData != null &&
                                    !bookedByYou)
                                ? 'By ${bookingData['residentName'] ?? '-'} (${bookingData['flatNumber'] ?? '-'})'
                                : '';
                            final IconData statusIcon = available
                                ? Icons.check_circle
                                : bookedByYou
                                    ? Icons.person
                                    : isBooked
                                        ? Icons.event_busy
                                        : blockedByActiveCharging
                                            ? Icons.ev_station
                                            : Icons.history;

                            return SizedBox(
                              width: 182,
                              child: InkWell(
                                onTap: available
                                    ? () => _bookSlot(
                                          pointKey: pointKey,
                                          startHour: startHour,
                                        )
                                    : null,
                                child: Card(
                                  color: bgColor,
                                  child: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Row(
                                          children: <Widget>[
                                            Icon(statusIcon, size: 16),
                                            const SizedBox(width: 6),
                                            Text(
                                              pointKey,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Text(_timeLabel(startHour)),
                                        Text(
                                          subtitle,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        if (byLine.isNotEmpty)
                                          Text(
                                            byLine,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          });
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'My Bookings',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: _firestore
                            .collection('slotBookings')
                            .where('ownerUid', isEqualTo: uid)
                            .snapshots(),
                        builder: (BuildContext context,
                            AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>>
                                mySnap) {
                          if (mySnap.hasError) {
                            return Text(
                                'Unable to load your bookings: ${mySnap.error}');
                          }
                          if (!mySnap.hasData) {
                            return const Padding(
                              padding: EdgeInsets.all(8),
                              child: CircularProgressIndicator(),
                            );
                          }
                          final List<
                                  QueryDocumentSnapshot<Map<String, dynamic>>>
                              docs = mySnap.data!.docs;
                          if (docs.isEmpty) {
                            return const Text('No bookings found.');
                          }
                          docs.sort((a, b) {
                            final Timestamp at =
                                a.data()['startAt'] as Timestamp;
                            final Timestamp bt =
                                b.data()['startAt'] as Timestamp;
                            return at.compareTo(bt);
                          });

                          return Column(
                            children: docs.map(
                                (QueryDocumentSnapshot<Map<String, dynamic>>
                                    doc) {
                              final Map<String, dynamic> data = doc.data();
                              final DateTime startAt =
                                  (data['startAt'] as Timestamp).toDate();
                              return Card(
                                child: ListTile(
                                  title: Text(
                                    '${data['pointKey']} | ${DateFormat('dd MMM yyyy').format(startAt)}',
                                  ),
                                  subtitle: Text(
                                    '${data['timeLabel']?.toString() ?? ''}\nStatus: ${(data['status'] ?? '-').toString().toUpperCase()}',
                                  ),
                                  isThreeLine: true,
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      if ((data['status'] ?? '') == 'booked')
                                        TextButton(
                                          onPressed: () =>
                                              _showRescheduleDialog(
                                                  doc, occupiedNow),
                                          child: const Text('Reschedule'),
                                        ),
                                      if ((data['status'] ?? '') == 'booked')
                                        TextButton(
                                          onPressed: () =>
                                              _cancelBooking(doc.id),
                                          child: const Text('Cancel'),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ],
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
