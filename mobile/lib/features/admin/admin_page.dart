import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/flat_billing.dart';
import '../../core/flat_payment_linker.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  static const String routeName = '/admin';

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final TextEditingController _newNameController = TextEditingController();
  final TextEditingController _newEmailController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _newWingController =
      TextEditingController(text: 'B1');
  final TextEditingController _newFlatController = TextEditingController();
  final TextEditingController _newVehicleController = TextEditingController();
  final TextEditingController _rateController = TextEditingController();
  final TextEditingController _versionController = TextEditingController();
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: <String>[drive.DriveApi.driveFileScope],
  );
  DateTime _selectedMonth = DateTime.now();
  bool _isCreating = false;
  bool _isReportBusy = false;
  int _refreshSeed = 0;
  String _reportStage = '';

  @override
  void initState() {
    super.initState();
    FlatPaymentLinker.ensureAll();
  }

  @override
  void dispose() {
    _newNameController.dispose();
    _newEmailController.dispose();
    _newPasswordController.dispose();
    _newWingController.dispose();
    _newFlatController.dispose();
    _newVehicleController.dispose();
    _rateController.dispose();
    _versionController.dispose();
    super.dispose();
  }

  Future<void> _setStatus(String uid, String status) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).update(
      <String, dynamic>{
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
    _toast('User updated.');
    setState(() {
      _refreshSeed += 1;
    });
  }

  Future<void> _setRole(String uid, String role) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).update(
      <String, dynamic>{
        'role': role,
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
    _toast('Role updated.');
    setState(() {
      _refreshSeed += 1;
    });
  }

  Future<void> _saveRateConfig() async {
    final double rate = double.tryParse(_rateController.text.trim()) ?? 0;
    if (rate <= 0) {
      _toast('Enter a valid positive rate.');
      return;
    }
    await FirebaseFirestore.instance.collection('appConfig').doc('rates').set(
      <String, dynamic>{
        'ratePerUnit': rate,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': FirebaseAuth.instance.currentUser?.uid,
      },
      SetOptions(merge: true),
    );
    _toast('Rate updated.');
    setState(() {
      _refreshSeed += 1;
    });
  }

  Future<void> _saveAppVersion() async {
    final String version = _versionController.text.trim();
    if (version.isEmpty) {
      _toast('Enter the current app version.');
      return;
    }
    await FirebaseFirestore.instance
        .collection('appConfig')
        .doc('appVersion')
        .set(
      <String, dynamic>{
        'currentVersion': version,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': FirebaseAuth.instance.currentUser?.uid,
      },
      SetOptions(merge: true),
    );
    _toast('App version published.');
  }

  Future<void> _updatePaymentStatus(
    String paymentId,
    String status,
  ) async {
    await FirebaseFirestore.instance
        .collection('payments')
        .doc(paymentId)
        .update(<String, dynamic>{
      'status': status,
      'verifiedBy': FirebaseAuth.instance.currentUser?.uid,
      'verifiedAt': FieldValue.serverTimestamp(),
      'paidAt': status == 'paid' ? FieldValue.serverTimestamp() : null,
    });
    _toast('Payment marked as ${_paymentStatusLabel(status)}.');
    setState(() {
      _refreshSeed += 1;
    });
  }

  String get _monthKey => DateFormat('yyyy-MM').format(_selectedMonth);

  Future<void> _pickMonth() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(now.year - 2, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _selectedMonth = DateTime(picked.year, picked.month);
      _refreshSeed += 1;
    });
  }

  Future<List<_DueRow>> _loadDueRows() async {
    final QuerySnapshot<Map<String, dynamic>> usersSnap =
        await FirebaseFirestore.instance.collection('users').get();
    final QuerySnapshot<Map<String, dynamic>> sessionsSnap =
        await FirebaseFirestore.instance
            .collection('chargingSessions')
            .where('monthKey', isEqualTo: _monthKey)
            .where('status', isEqualTo: 'completed')
            .get();
    final QuerySnapshot<Map<String, dynamic>> paymentsSnap =
        await FirebaseFirestore.instance
            .collection('payments')
            .where('monthKey', isEqualTo: _monthKey)
            .orderBy('createdAt', descending: true)
            .get();

    final Map<String, FlatProfileScope> scopes = <String, FlatProfileScope>{};
    final Map<String, List<Map<String, dynamic>>> usersByFlat =
        <String, List<Map<String, dynamic>>>{};
    for (final QueryDocumentSnapshot<Map<String, dynamic>> u
        in usersSnap.docs) {
      final FlatProfileScope? scope = FlatProfileScope.fromUser(u.data());
      if (scope == null) {
        continue;
      }
      scopes[u.id] = scope;
      usersByFlat
          .putIfAbsent(scope.key, () => <Map<String, dynamic>>[])
          .add(u.data());
    }

    final Map<String, _DueRow> rows = <String, _DueRow>{};
    String resolveKey(Map<String, dynamic> data) {
      final String tagged = (data['billingFlatKey'] ?? '').toString();
      if (tagged.isNotEmpty) {
        return tagged;
      }
      final String? direct =
          FlatBillMath.flatKey(data['wing'], data['flatNumber']);
      if (direct != null) {
        return direct;
      }
      final String uid = (data['ownerUid'] ?? '').toString();
      return scopes[uid]?.key ?? 'uid:$uid';
    }

    _DueRow rowFor(String key, Map<String, dynamic> data) {
      return rows.putIfAbsent(key, () {
        final List<String> parts =
            key.startsWith('uid:') ? <String>[] : key.split('|');
        final String wing =
            parts.length == 2 ? parts[0] : (data['wing'] ?? '-').toString();
        final String flat = parts.length == 2
            ? parts[1]
            : (data['flatNumber'] ?? '-').toString();
        final _DueRow row = _DueRow(
          ownerUid: (data['ownerUid'] ?? '').toString(),
          wing: wing,
          flat: flat,
        );
        for (final Map<String, dynamic> user
            in usersByFlat[key] ?? <Map<String, dynamic>>[]) {
          row.addPerson(
            (user['name'] ?? '').toString(),
            (user['email'] ?? '').toString(),
          );
        }
        if (row.names.isEmpty) {
          row.addPerson((data['residentName'] ?? '').toString(), '');
        }
        return row;
      });
    }

    for (final QueryDocumentSnapshot<Map<String, dynamic>> s
        in sessionsSnap.docs) {
      final Map<String, dynamic> d = s.data();
      final String key = resolveKey(d);
      if (key == 'uid:') {
        continue;
      }
      final _DueRow row = rowFor(key, d);
      row.units += (d['units'] as num?)?.toDouble() ?? 0;
      row.billAmount += (d['amount'] as num?)?.toDouble() ?? 0;
      row.sessionCount += 1;
    }

    for (final QueryDocumentSnapshot<Map<String, dynamic>> p
        in paymentsSnap.docs) {
      final Map<String, dynamic> d = p.data();
      final String key = resolveKey(d);
      if (key == 'uid:') {
        continue;
      }
      final _DueRow row = rowFor(key, d);
      final String status = (d['status'] ?? 'submitted').toString();
      final double amount = (d['amount'] as num?)?.toDouble() ?? 0;
      if (FlatBillMath.isSettledStatus(status)) {
        row.paidAmount += amount;
      }
      if (status == 'submitted') {
        row.pendingRefs += 1;
      }
      row.lastTxnRef = (d['txnRef'] ?? row.lastTxnRef).toString();
      row.lastPaymentStatus = _paymentStatusLabel(status);
    }

    final List<_DueRow> dueRows = rows.values.toList()
      ..sort((_DueRow a, _DueRow b) => b.dueAmount.compareTo(a.dueAmount));
    return dueRows
        .where((_DueRow e) => e.billAmount > 0 || e.paidAmount > 0)
        .toList();
  }

  Future<File> _generateAdminReportFile({required bool uploadToDrive}) async {
    setState(() {
      _reportStage = 'Collecting billing and payment data...';
    });
    final List<_DueRow> dueRows = await _loadDueRows();
    final QuerySnapshot<Map<String, dynamic>> sessionsSnap =
        await FirebaseFirestore.instance
            .collection('chargingSessions')
            .where('monthKey', isEqualTo: _monthKey)
            .where('status', isEqualTo: 'completed')
            .orderBy('createdAt', descending: false)
            .get();
    final QuerySnapshot<Map<String, dynamic>> paymentsSnap =
        await FirebaseFirestore.instance
            .collection('payments')
            .where('monthKey', isEqualTo: _monthKey)
            .orderBy('createdAt', descending: false)
            .get();

    setState(() {
      _reportStage = 'Building Excel workbook...';
    });
    final Excel excel = Excel.createExcel();
    final Sheet summary = excel['Summary'];
    summary.appendRow(<CellValue>[
      TextCellValue('Name'),
      TextCellValue('Email'),
      TextCellValue('Wing'),
      TextCellValue('Flat'),
      TextCellValue('Sessions'),
      TextCellValue('Units'),
      TextCellValue('Bill Amount'),
      TextCellValue('Paid Amount'),
      TextCellValue('Due Amount'),
      TextCellValue('Pending Refs'),
      TextCellValue('Last Txn Ref'),
      TextCellValue('Last Payment Status'),
    ]);
    for (final _DueRow row in dueRows) {
      summary.appendRow(<CellValue>[
        TextCellValue(row.nameLabel),
        TextCellValue(row.emailLabel),
        TextCellValue(row.wing),
        TextCellValue(row.flat),
        IntCellValue(row.sessionCount),
        DoubleCellValue(row.units),
        DoubleCellValue(row.billAmount),
        DoubleCellValue(row.paidAmount),
        DoubleCellValue(row.dueAmount),
        IntCellValue(row.pendingRefs),
        TextCellValue(row.lastTxnRef),
        TextCellValue(row.lastPaymentStatus),
      ]);
    }

    final Sheet sessions = excel['Sessions'];
    sessions.appendRow(<CellValue>[
      TextCellValue('Owner UID'),
      TextCellValue('Name'),
      TextCellValue('Wing'),
      TextCellValue('Flat'),
      TextCellValue('Point'),
      TextCellValue('Vehicle'),
      TextCellValue('Units'),
      TextCellValue('Amount'),
      TextCellValue('Start Time'),
      TextCellValue('End Time'),
    ]);
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
        in sessionsSnap.docs) {
      final Map<String, dynamic> d = doc.data();
      final DateTime? start = (d['startTime'] as Timestamp?)?.toDate();
      final DateTime? end = (d['endTime'] as Timestamp?)?.toDate();
      sessions.appendRow(<CellValue>[
        TextCellValue((d['ownerUid'] ?? '').toString()),
        TextCellValue((d['residentName'] ?? '').toString()),
        TextCellValue((d['wing'] ?? '').toString()),
        TextCellValue((d['flatNumber'] ?? '').toString()),
        TextCellValue((d['pointKey'] ?? '').toString()),
        TextCellValue((d['vehicleNumber'] ?? '').toString()),
        DoubleCellValue((d['units'] as num?)?.toDouble() ?? 0),
        DoubleCellValue((d['amount'] as num?)?.toDouble() ?? 0),
        TextCellValue(
            start == null ? '' : DateFormat('yyyy-MM-dd HH:mm').format(start)),
        TextCellValue(
            end == null ? '' : DateFormat('yyyy-MM-dd HH:mm').format(end)),
      ]);
    }

    final Sheet payments = excel['Payments'];
    payments.appendRow(<CellValue>[
      TextCellValue('Owner UID'),
      TextCellValue('Month'),
      TextCellValue('Txn Ref'),
      TextCellValue('Amount'),
      TextCellValue('Status'),
      TextCellValue('Requested At'),
      TextCellValue('Status Updated At'),
      TextCellValue('Verified By'),
    ]);
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
        in paymentsSnap.docs) {
      final Map<String, dynamic> d = doc.data();
      final DateTime? requestedAt =
          (d['requestedAt'] as Timestamp?)?.toDate() ??
              (d['createdAt'] as Timestamp?)?.toDate();
      final DateTime? paidAt = (d['paidAt'] as Timestamp?)?.toDate() ??
          (d['verifiedAt'] as Timestamp?)?.toDate();
      payments.appendRow(<CellValue>[
        TextCellValue((d['ownerUid'] ?? '').toString()),
        TextCellValue((d['monthKey'] ?? '').toString()),
        TextCellValue((d['txnRef'] ?? '').toString()),
        DoubleCellValue((d['amount'] as num?)?.toDouble() ?? 0),
        TextCellValue(_paymentStatusLabel((d['status'] ?? '').toString())),
        TextCellValue(
          requestedAt == null
              ? ''
              : DateFormat('yyyy-MM-dd HH:mm').format(requestedAt),
        ),
        TextCellValue(
          paidAt == null ? '' : DateFormat('yyyy-MM-dd HH:mm').format(paidAt),
        ),
        TextCellValue((d['verifiedBy'] ?? '').toString()),
      ]);
    }

    excel.delete('Sheet1');
    final List<int>? bytes = excel.encode();
    if (bytes == null) {
      throw Exception('Failed to generate report.');
    }
    final Directory dir = await getApplicationDocumentsDirectory();
    final File file = File(
      '${dir.path}/admin_billing_${_monthKey}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx',
    );
    await file.writeAsBytes(bytes, flush: true);
    if (uploadToDrive) {
      setState(() {
        _reportStage = 'Uploading to Google Drive...';
      });
      await _uploadFileToDrive(file);
    }
    return file;
  }

  Future<void> _downloadAdminReport() async {
    setState(() => _isReportBusy = true);
    try {
      final File file = await _generateAdminReportFile(uploadToDrive: false);
      await Share.shareXFiles(<XFile>[XFile(file.path)],
          subject: 'Admin Billing Report ($_monthKey)');
      _toast('Admin report generated.');
    } catch (e) {
      _toast(_friendlyReportError(e));
    } finally {
      if (mounted) {
        setState(() {
          _isReportBusy = false;
          _reportStage = '';
        });
      }
    }
  }

  Future<void> _uploadAdminReportToDrive() async {
    setState(() => _isReportBusy = true);
    try {
      final File file = await _generateAdminReportFile(uploadToDrive: false);
      try {
        setState(() {
          _reportStage = 'Uploading to Google Drive...';
        });
        await _uploadFileToDrive(file);
        _toast('Report uploaded to Google Drive.');
      } catch (e) {
        await Share.shareXFiles(<XFile>[XFile(file.path)],
            subject: 'Admin Billing Report ($_monthKey)');
        _toast(
          'Drive upload failed, but local report was generated and opened for sharing. ${_friendlyReportError(e)}',
        );
      }
    } catch (e) {
      _toast(_friendlyReportError(e));
    } finally {
      if (mounted) {
        setState(() {
          _isReportBusy = false;
          _reportStage = '';
        });
      }
    }
  }

  String _friendlyReportError(Object error) {
    final String text = error.toString();
    if (text.contains('failed-precondition') || text.contains('index')) {
      return 'Report failed due to missing database index. Please retry after index deployment.';
    }
    if (text.contains('permission-denied')) {
      return 'Permission denied. Ensure admin account is active and has admin role.';
    }
    if (text.contains('Google sign-in cancelled')) {
      return 'Google sign-in was cancelled.';
    }
    if (text.contains('Google Drive auth failed')) {
      return 'Google Drive authorization failed. Please sign in again.';
    }
    return 'Operation failed: $error';
  }

  String _paymentStatusLabel(String status) {
    if (status == 'paid' || status == 'verified') {
      return 'Paid';
    }
    if (status == 'submitted') {
      return 'Pending Verification';
    }
    if (status == 'rejected') {
      return 'Rejected';
    }
    return status;
  }

  Future<void> _uploadFileToDrive(File file) async {
    final GoogleSignInAccount? account =
        _googleSignIn.currentUser ?? await _googleSignIn.signIn();
    if (account == null) {
      throw Exception('Google sign-in cancelled.');
    }
    final client = await _googleSignIn.authenticatedClient();
    if (client == null) {
      throw Exception('Google Drive auth failed.');
    }
    final drive.DriveApi api = drive.DriveApi(client);

    final String parentFolderId =
        await _getOrCreateFolder(api, 'EV Charging Reports', null);
    final String monthFolderId =
        await _getOrCreateFolder(api, _monthKey, parentFolderId);

    final drive.File metadata = drive.File()
      ..name = file.uri.pathSegments.last
      ..parents = <String>[monthFolderId];
    final drive.Media media = drive.Media(file.openRead(), file.lengthSync());
    await api.files.create(metadata, uploadMedia: media);
  }

  Future<String> _getOrCreateFolder(
    drive.DriveApi api,
    String folderName,
    String? parentId,
  ) async {
    final String parentQuery =
        parentId == null ? '' : " and '$parentId' in parents";
    final drive.FileList existing = await api.files.list(
      q: "mimeType='application/vnd.google-apps.folder' and trashed=false and name='$folderName'$parentQuery",
      $fields: 'files(id,name)',
      spaces: 'drive',
    );
    if (existing.files != null && existing.files!.isNotEmpty) {
      return existing.files!.first.id!;
    }
    final drive.File folder = drive.File()
      ..name = folderName
      ..mimeType = 'application/vnd.google-apps.folder'
      ..parents = parentId == null ? null : <String>[parentId];
    final drive.File created = await api.files.create(folder);
    return created.id!;
  }

  Future<void> _addUser() async {
    final String name = _newNameController.text.trim();
    final String email = _newEmailController.text.trim();
    final String password = _newPasswordController.text.trim();
    final String wing = _newWingController.text.trim().toUpperCase();
    final String flat = _newFlatController.text.trim().toUpperCase();
    final String vehicle = _newVehicleController.text.trim().toUpperCase();
    if (name.isEmpty ||
        email.isEmpty ||
        password.isEmpty ||
        wing.isEmpty ||
        flat.isEmpty ||
        vehicle.isEmpty) {
      _toast('Fill all fields for new user.');
      return;
    }

    setState(() => _isCreating = true);
    try {
      final FirebaseApp app = Firebase.app();
      final FirebaseApp secondary = await Firebase.initializeApp(
        name: 'adminCreateUserApp',
        options: app.options,
      );
      try {
        final UserCredential cred =
            await FirebaseAuth.instanceFor(app: secondary)
                .createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        final String uid = cred.user!.uid;
        await FirebaseFirestore.instance.collection('users').doc(uid).set(
          <String, dynamic>{
            'email': email,
            'name': name,
            'wing': wing,
            'flatNumber': flat,
            'vehicleNumber': vehicle,
            'role': 'resident',
            'status': 'active',
            'createdAt': FieldValue.serverTimestamp(),
            'createdByAdminUid': FirebaseAuth.instance.currentUser?.uid,
          },
        );
        await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
        _newNameController.clear();
        _newEmailController.clear();
        _newPasswordController.clear();
        _newFlatController.clear();
        _newVehicleController.clear();
        _toast('User created and activated.');
      } finally {
        await secondary.delete();
      }
    } on FirebaseAuthException catch (e) {
      _toast(e.message ?? e.code);
    } on FirebaseException catch (e) {
      _toast(e.message ?? e.code);
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Panel'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Text(
            'Billing & Dues Console',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickMonth,
                  icon: const Icon(Icons.calendar_month),
                  label: Text(DateFormat('MMMM yyyy').format(_selectedMonth)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isReportBusy ? null : _downloadAdminReport,
                  icon: const Icon(Icons.download),
                  label: Text(_isReportBusy
                      ? 'Processing...'
                      : 'Download All Users Report'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isReportBusy ? null : _uploadAdminReportToDrive,
                  icon: const Icon(Icons.cloud_upload),
                  label: const Text('Upload Report to Google Drive'),
                ),
              ),
            ],
          ),
          if (_isReportBusy && _reportStage.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              _reportStage,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
          const SizedBox(height: 10),
          FutureBuilder<List<_DueRow>>(
            key: ValueKey<String>('$_monthKey-$_refreshSeed'),
            future: _loadDueRows(),
            builder:
                (BuildContext context, AsyncSnapshot<List<_DueRow>> snapshot) {
              if (snapshot.hasError) {
                return Text('Unable to load dues: ${snapshot.error}');
              }
              if (!snapshot.hasData) {
                return const CircularProgressIndicator();
              }
              if (snapshot.data!.isEmpty) {
                return const Text('No billing data for this month.');
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Flat Dues & Consumption',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...snapshot.data!.map((_DueRow row) => Card(
                        child: ListTile(
                          title: Text(
                              '${row.nameLabel} (${row.wing} ${row.flat})'),
                          subtitle: Text(
                            '${row.emailLabel}\n'
                            'Units: ${row.units.toStringAsFixed(2)} | '
                            'Bill: INR ${row.billAmount.toStringAsFixed(2)} | '
                            'Paid: INR ${row.paidAmount.toStringAsFixed(2)}\n'
                            'Due: INR ${row.dueAmount.toStringAsFixed(2)} | '
                            'Pending refs: ${row.pendingRefs} | '
                            'Last txn: ${row.lastTxnRef} (${row.lastPaymentStatus})',
                          ),
                          isThreeLine: true,
                        ),
                      )),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          const Text(
            'Rate Configuration',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('appConfig')
                .doc('rates')
                .snapshots(),
            builder: (BuildContext context,
                AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>>
                    snapshot) {
              final double rate = ((snapshot.data?.data() ??
                          <String, dynamic>{})['ratePerUnit'] as num?)
                      ?.toDouble() ??
                  15.0;
              if (_rateController.text.isEmpty) {
                _rateController.text = rate.toStringAsFixed(2);
              }
              return Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _rateController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Rate per Unit (INR)'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _saveRateConfig,
                    child: const Text('Save'),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          const Text(
            'Published App Version',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('appConfig')
                .doc('appVersion')
                .snapshots(),
            builder: (BuildContext context,
                AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>>
                    snapshot) {
              final String version = ((snapshot.data?.data() ??
                          <String, dynamic>{})['currentVersion'] ??
                      '')
                  .toString();
              if (_versionController.text.isEmpty && version.isNotEmpty) {
                _versionController.text = version;
              }
              return Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _versionController,
                      decoration: const InputDecoration(
                        labelText: 'Current app version',
                        helperText: 'Shown on the home dashboard',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _saveAppVersion,
                    child: const Text('Publish'),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          const Text(
            'Add User',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _newNameController,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _newEmailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _newPasswordController,
            decoration: const InputDecoration(labelText: 'Temporary Password'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _newWingController,
            decoration: const InputDecoration(labelText: 'Wing (B1/B2)'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _newFlatController,
            decoration: const InputDecoration(labelText: 'Flat Number'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _newVehicleController,
            decoration: const InputDecoration(labelText: 'Vehicle Number'),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _isCreating ? null : _addUser,
            child:
                Text(_isCreating ? 'Creating...' : 'Create and Activate User'),
          ),
          const SizedBox(height: 20),
          const Text(
            'Pending Payments',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('payments')
                .where('status', isEqualTo: 'submitted')
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (BuildContext context,
                AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot) {
              if (snapshot.hasError) {
                return Text('Pending payments load failed: ${snapshot.error}');
              }
              if (!snapshot.hasData) {
                return const CircularProgressIndicator();
              }
              if (snapshot.data!.docs.isEmpty) {
                return const Text('No pending payments.');
              }
              return Column(
                children: snapshot.data!.docs
                    .map((QueryDocumentSnapshot<Map<String, dynamic>> doc) {
                  final Map<String, dynamic> data = doc.data();
                  return Card(
                    child: ListTile(
                      title: Text(
                        'Txn ${data['txnRef'] ?? '-'} | INR ${((data['amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                      ),
                      subtitle: Text(
                        'Month: ${data['monthKey'] ?? '-'} | Flat: ${data['billingFlatKey'] ?? data['flatNumber'] ?? '-'} | UID: ${data['ownerUid'] ?? '-'}',
                      ),
                      trailing: Wrap(
                        spacing: 8,
                        children: <Widget>[
                          TextButton(
                            onPressed: () =>
                                _updatePaymentStatus(doc.id, 'paid'),
                            child: const Text('Approve Paid'),
                          ),
                          TextButton(
                            onPressed: () =>
                                _updatePaymentStatus(doc.id, 'rejected'),
                            child: const Text('Reject'),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 20),
          const Text(
            'Users',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (BuildContext context,
                AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot) {
              if (snapshot.hasError) {
                return Text('Users load failed: ${snapshot.error}');
              }
              if (!snapshot.hasData) {
                return const CircularProgressIndicator();
              }
              final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs =
                  snapshot.data!.docs;
              if (docs.isEmpty) {
                return const Text('No users found.');
              }
              return Column(
                children:
                    docs.map((QueryDocumentSnapshot<Map<String, dynamic>> doc) {
                  final Map<String, dynamic> data = doc.data();
                  final String status =
                      (data['status'] ?? 'pending').toString();
                  final String role = (data['role'] ?? 'resident').toString();
                  return Card(
                    child: ListTile(
                      title: Text(
                          '${data['name'] ?? '-'} (${data['email'] ?? '-'})'),
                      subtitle: Text(
                        '${data['wing'] ?? '-'} ${data['flatNumber'] ?? '-'} | '
                        '${data['vehicleNumber'] ?? '-'}\nRole: $role | Status: $status',
                      ),
                      isThreeLine: true,
                      trailing: PopupMenuButton<String>(
                        onSelected: (String value) async {
                          if (value == 'approve') {
                            await _setStatus(doc.id, 'active');
                          } else if (value == 'disable') {
                            await _setStatus(doc.id, 'disabled');
                          } else if (value == 'pending') {
                            await _setStatus(doc.id, 'pending');
                          } else if (value == 'admin') {
                            await _setRole(doc.id, 'admin');
                          } else if (value == 'resident') {
                            await _setRole(doc.id, 'resident');
                          }
                        },
                        itemBuilder: (BuildContext context) =>
                            <PopupMenuEntry<String>>[
                          const PopupMenuItem<String>(
                            value: 'approve',
                            child: Text('Approve/Activate'),
                          ),
                          const PopupMenuItem<String>(
                            value: 'disable',
                            child: Text('Disable'),
                          ),
                          const PopupMenuItem<String>(
                            value: 'pending',
                            child: Text('Set Pending'),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem<String>(
                            value: 'admin',
                            child: Text('Make Admin'),
                          ),
                          const PopupMenuItem<String>(
                            value: 'resident',
                            child: Text('Make Resident'),
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
      ),
    );
  }
}

class _DueRow {
  _DueRow({
    required this.ownerUid,
    required this.wing,
    required this.flat,
  });

  final String ownerUid;
  final String wing;
  final String flat;
  final Set<String> names = <String>{};
  final Set<String> emails = <String>{};
  int sessionCount = 0;
  double units = 0;
  double billAmount = 0;
  double paidAmount = 0;
  int pendingRefs = 0;
  String lastTxnRef = '-';
  String lastPaymentStatus = '-';

  void addPerson(String name, String email) {
    final String trimmedName = name.trim();
    final String trimmedEmail = email.trim();
    if (trimmedName.isNotEmpty && trimmedName != '-') {
      names.add(trimmedName);
    }
    if (trimmedEmail.isNotEmpty && trimmedEmail != '-') {
      emails.add(trimmedEmail);
    }
  }

  String get nameLabel => names.isEmpty ? '-' : names.join(', ');

  String get emailLabel => emails.isEmpty ? '-' : emails.join(', ');

  double get dueAmount {
    final double due = billAmount - paidAmount;
    return due < 0 ? 0 : due;
  }
}
