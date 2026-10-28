import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../core/flat_billing.dart';
import '../../core/flat_payment_linker.dart';
import '../../core/flat_session_merge.dart';

class BillingPage extends StatefulWidget {
  const BillingPage({super.key});

  static const String routeName = '/billing';

  @override
  State<BillingPage> createState() => _BillingPageState();
}

class _BillingPageState extends State<BillingPage> {
  DateTime _selectedMonth = DateTime.now();
  final TextEditingController _txnRefController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  bool _isPdfBusy = false;
  bool _showUsageHistory = false;
  HistoryScope _historyScope = HistoryScope.daily;

  String get _monthKey => DateFormat('yyyy-MM').format(_selectedMonth);

  @override
  void dispose() {
    _txnRefController.dispose();
    _amountController.dispose();
    super.dispose();
  }

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
    });
  }

  Future<void> _submitPaymentVerificationRequest({
    required String monthKey,
  }) async {
    final String uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final double amount = double.tryParse(_amountController.text.trim()) ?? 0;
    final String? error = await FlatPaymentLinker.submitPaymentRequest(
      uid: uid,
      txnRef: _txnRefController.text,
      amount: amount,
      monthKey: monthKey,
    );
    if (!mounted) {
      return;
    }
    if (error != null) {
      _toast(error);
      return;
    }
    Navigator.of(context).pop();
    _txnRefController.clear();
    _amountController.clear();
    _toast('Verification request sent to admin for this flat.');
  }

  Future<void> _openPaymentRequestDialog({
    required String monthKey,
    required double suggestedAmount,
  }) async {
    _amountController.text =
        suggestedAmount > 0 ? suggestedAmount.toStringAsFixed(2) : '';
    _txnRefController.clear();
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Request Payment Verification'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Amount Paid (INR)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _txnRefController,
              decoration: const InputDecoration(
                labelText: 'Transaction Reference',
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                _submitPaymentVerificationRequest(monthKey: monthKey),
            child: const Text('Send Request'),
          ),
        ],
      ),
    );
  }

  String _statusLabel(String status) {
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

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  MonthlyBillSummary _buildSummary({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> sessionDocs,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> paymentDocs,
  }) {
    final List<SessionBillRow> sessions = sessionDocs
        .map((QueryDocumentSnapshot<Map<String, dynamic>> d) =>
            SessionBillRow.fromMap(d.data()))
        .toList();
    final List<PaymentRecord> payments = paymentDocs
        .map((QueryDocumentSnapshot<Map<String, dynamic>> d) =>
            PaymentRecord.fromMap(d.data()))
        .toList();
    return MonthlyBillSummary(
      monthKey: _monthKey,
      sessions: sessions,
      payments: payments,
      statusLabelResolver: _statusLabel,
    );
  }

  Future<void> _downloadMonthlyPdf({
    required MonthlyBillSummary summary,
    required String userName,
    required String wing,
    required String flat,
  }) async {
    setState(() => _isPdfBusy = true);
    try {
      final pw.Document doc = pw.Document();
      doc.addPage(
        pw.MultiPage(
          build: (pw.Context context) => <pw.Widget>[
            pw.Header(
              level: 0,
              child: pw.Text('Society EV Billing Statement'),
            ),
            pw.Text('Month: ${summary.monthDisplay}'),
            pw.Text('Name: ${userName.isEmpty ? '-' : userName}'),
            pw.Text(
                'Flat: ${wing.isEmpty ? '-' : wing}${flat.isEmpty ? '' : ' - $flat'}'),
            pw.Text(
                'This statement combines every login registered for this flat.'),
            pw.SizedBox(height: 12),
            pw.Text(
              'Summary',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Bullet(
                text:
                    'Total Units: ${summary.totalUnits.toStringAsFixed(2)} kWh'),
            pw.Bullet(
                text:
                    'Total Charges: INR ${summary.totalAmount.toStringAsFixed(2)}'),
            pw.Bullet(
                text:
                    'Total Paid: INR ${summary.totalPaid.toStringAsFixed(2)}'),
            pw.Bullet(
                text: 'Total Due: INR ${summary.totalDue.toStringAsFixed(2)}'),
            pw.Bullet(text: 'Status: ${summary.overallStatus}'),
            pw.SizedBox(height: 12),
            pw.Text(
              'Session Details',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.TableHelper.fromTextArray(
              headers: <String>[
                'Date/Time',
                'Point',
                'Vehicle',
                'Start',
                'End',
                'Units',
                'Amount',
              ],
              data: summary.sessions
                  .map((SessionBillRow s) => <String>[
                        DateFormat('dd MMM yyyy, hh:mm a').format(s.shownAt),
                        s.pointKey,
                        s.vehicleNumber,
                        s.startMeter.toStringAsFixed(2),
                        s.endMeter.toStringAsFixed(2),
                        s.units.toStringAsFixed(2),
                        s.amount.toStringAsFixed(2),
                      ])
                  .toList(),
            ),
            pw.SizedBox(height: 12),
            pw.Text(
              'Payment History',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            if (summary.payments.isEmpty)
              pw.Text('No payment records for this month.')
            else
              pw.TableHelper.fromTextArray(
                headers: <String>[
                  'Txn Ref',
                  'Amount',
                  'Status',
                  'Requested',
                  'Updated',
                ],
                data: summary.payments
                    .map((PaymentRecord p) => <String>[
                          p.txnRef,
                          p.amount.toStringAsFixed(2),
                          _statusLabel(p.status),
                          p.requestedAt == null
                              ? '-'
                              : DateFormat('dd MMM yyyy, hh:mm a')
                                  .format(p.requestedAt!),
                          p.updatedAt == null
                              ? '-'
                              : DateFormat('dd MMM yyyy, hh:mm a')
                                  .format(p.updatedAt!),
                        ])
                    .toList(),
              ),
          ],
        ),
      );
      final List<int> bytes = await doc.save();
      final Directory dir = await getApplicationDocumentsDirectory();
      final File file = File(
        '${dir.path}/ev_bill_${summary.monthKey}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf',
      );
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles(<XFile>[XFile(file.path)],
          subject: 'EV Billing Statement ${summary.monthDisplay}');
    } catch (_) {
      _toast('Unable to generate PDF. Please retry.');
    } finally {
      if (mounted) {
        setState(() => _isPdfBusy = false);
      }
    }
  }

  Future<void> _openMonthlyDetails(
    BuildContext context, {
    required MonthlyBillSummary summary,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.88,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (BuildContext context, ScrollController controller) {
            return ListView(
              controller: controller,
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                Text(
                  'Bill Details - ${summary.monthDisplay}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 10),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                            'Total Units: ${summary.totalUnits.toStringAsFixed(2)} kWh'),
                        Text(
                            'Total Charges: INR ${summary.totalAmount.toStringAsFixed(2)}'),
                        Text(
                            'Total Paid: INR ${summary.totalPaid.toStringAsFixed(2)}'),
                        Text(
                            'Total Due: INR ${summary.totalDue.toStringAsFixed(2)}'),
                        Text('Status: ${summary.overallStatus}'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Session-wise Charges',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                if (summary.sessions.isEmpty)
                  const Text('No completed charging sessions in this month.')
                else
                  ...summary.sessions.map((SessionBillRow row) => Card(
                        child: ListTile(
                          title: Text(
                              '${row.vehicleNumber} | ${row.pointKey} | ${DateFormat('dd MMM yyyy, hh:mm a').format(row.shownAt)}'),
                          subtitle: Text(
                            'Start: ${row.startMeter.toStringAsFixed(2)} | End: ${row.endMeter.toStringAsFixed(2)}\n'
                            'Units: ${row.units.toStringAsFixed(2)} kWh',
                          ),
                          trailing: Text(
                            'INR ${row.amount.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          isThreeLine: true,
                        ),
                      )),
                const SizedBox(height: 10),
                const Text(
                  'Payment History',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                if (summary.payments.isEmpty)
                  const Text('No payment records for this month.')
                else
                  ...summary.payments.map((PaymentRecord p) => Card(
                        child: ListTile(
                          title: Text(
                              'Txn ${p.txnRef} | INR ${p.amount.toStringAsFixed(2)}'),
                          subtitle: Text(
                            'Status: ${_statusLabel(p.status)}'
                            '${p.requestedAt == null ? '' : '\nRequested: ${DateFormat('dd MMM yyyy, hh:mm a').format(p.requestedAt!)}'}'
                            '${p.updatedAt == null ? '' : '\nUpdated: ${DateFormat('dd MMM yyyy, hh:mm a').format(p.updatedAt!)}'}',
                          ),
                          isThreeLine: true,
                        ),
                      )),
              ],
            );
          },
        );
      },
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Paid':
        return Colors.green;
      case 'Pending Verification':
        return Colors.orange;
      case 'Rejected':
        return Colors.red;
      case 'No Dues':
        return Colors.blueGrey;
      default:
        return Colors.blue;
    }
  }

  List<UsageHistoryGroup> _buildHistoryGroups(List<SessionBillRow> sessions) {
    final Map<String, UsageHistoryGroupBuilder> grouped =
        <String, UsageHistoryGroupBuilder>{};
    for (final SessionBillRow session in sessions) {
      final DateTime at = session.shownAt;
      late final String groupKey;
      late final String label;
      switch (_historyScope) {
        case HistoryScope.daily:
          groupKey = DateFormat('yyyy-MM-dd').format(at);
          label = DateFormat('dd MMM yyyy').format(at);
          break;
        case HistoryScope.weekly:
          final DateTime start = at.subtract(Duration(days: at.weekday - 1));
          final DateTime end = start.add(const Duration(days: 6));
          groupKey = DateFormat('yyyy-MM-dd').format(start);
          label =
              '${DateFormat('dd MMM').format(start)} - ${DateFormat('dd MMM yyyy').format(end)}';
          break;
        case HistoryScope.monthly:
          groupKey = DateFormat('yyyy-MM').format(at);
          label = DateFormat('MMMM yyyy').format(at);
          break;
      }
      final UsageHistoryGroupBuilder builder =
          grouped.putIfAbsent(groupKey, () => UsageHistoryGroupBuilder(label));
      builder.add(session);
    }
    final List<MapEntry<String, UsageHistoryGroupBuilder>> entries = grouped
        .entries
        .toList()
      ..sort((MapEntry<String, UsageHistoryGroupBuilder> a,
              MapEntry<String, UsageHistoryGroupBuilder> b) =>
          b.key.compareTo(a.key));
    return entries
        .take(12)
        .map((MapEntry<String, UsageHistoryGroupBuilder> entry) =>
            entry.value.toGroup())
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final String uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Monthly Billing')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          OutlinedButton.icon(
            onPressed: _pickMonth,
            icon: const Icon(Icons.calendar_month),
            label: Text(DateFormat('MMMM yyyy').format(_selectedMonth)),
          ),
          const SizedBox(height: 12),
          if (uid.isEmpty)
            const Text('Please login to view billing.')
          else
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .snapshots(),
              builder: (BuildContext context,
                  AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>>
                      userSnap) {
                final Map<String, dynamic> userData =
                    userSnap.data?.data() ?? <String, dynamic>{};
                final String userName = (userData['name'] ?? '').toString();
                final String wing = (userData['wing'] ?? '').toString();
                final String flat = (userData['flatNumber'] ?? '').toString();
                final FlatProfileScope? scope =
                    FlatProfileScope.fromUser(userData);
                if (scope != null) {
                  FlatPaymentLinker.ensureOwn(uid, scope);
                  FlatPaymentLinker.ensureOwnSessions(uid, scope);
                }
                return FlatSessionMerge(
                  uid: uid,
                  scope: scope,
                  builder: (List<QueryDocumentSnapshot<Map<String, dynamic>>>
                      loadedSessions) {
                    final List<QueryDocumentSnapshot<Map<String, dynamic>>>
                        sessionDocs = loadedSessions
                            .where((QueryDocumentSnapshot<Map<String, dynamic>>
                                    doc) =>
                                FlatBillMath.sessionCounts(
                                  data: doc.data(),
                                  scope: scope,
                                  viewerUid: uid,
                                  monthKey: _monthKey,
                                ))
                            .toList();
                    return _MergedPaymentDocs(
                      uid: uid,
                      scope: scope,
                      monthKey: _monthKey,
                      builder:
                          (List<QueryDocumentSnapshot<Map<String, dynamic>>>
                              paymentDocs) {
                        final MonthlyBillSummary summary = _buildSummary(
                          sessionDocs: sessionDocs,
                          paymentDocs: paymentDocs,
                        );
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Card(
                              elevation: 1,
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Row(
                                      children: <Widget>[
                                        Expanded(
                                          child: Text(
                                            summary.monthDisplay,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 18,
                                            ),
                                          ),
                                        ),
                                        Chip(
                                          label: Text(summary.overallStatus),
                                          backgroundColor: _statusColor(
                                                  summary.overallStatus)
                                              .withValues(alpha: 0.18),
                                        ),
                                      ],
                                    ),
                                    if (scope != null) ...<Widget>[
                                      const SizedBox(height: 6),
                                      Text(
                                        'Combined for flat ${scope.wing}-${scope.flat} across all logins.',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 10,
                                      runSpacing: 10,
                                      children: <Widget>[
                                        _MetricTile(
                                          label: 'Used',
                                          value:
                                              '${summary.totalUnits.toStringAsFixed(2)} kWh',
                                        ),
                                        _MetricTile(
                                          label: 'Charged',
                                          value:
                                              'INR ${summary.totalAmount.toStringAsFixed(2)}',
                                        ),
                                        _MetricTile(
                                          label: 'Paid',
                                          value:
                                              'INR ${summary.totalPaid.toStringAsFixed(2)}',
                                        ),
                                        _MetricTile(
                                          label: 'Due',
                                          value:
                                              'INR ${summary.totalDue.toStringAsFixed(2)}',
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: <Widget>[
                                        Expanded(
                                          child: FilledButton.icon(
                                            onPressed: () =>
                                                _openMonthlyDetails(
                                              context,
                                              summary: summary,
                                            ),
                                            icon:
                                                const Icon(Icons.receipt_long),
                                            label: const Text('View Details'),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: <Widget>[
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: _isPdfBusy
                                                ? null
                                                : () => _downloadMonthlyPdf(
                                                      summary: summary,
                                                      userName: userName,
                                                      wing: wing,
                                                      flat: flat,
                                                    ),
                                            icon: const Icon(
                                                Icons.picture_as_pdf),
                                            label: Text(_isPdfBusy
                                                ? 'Generating PDF...'
                                                : 'Download PDF'),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (summary.totalDue > 0) ...<Widget>[
                                      const SizedBox(height: 8),
                                      Row(
                                        children: <Widget>[
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              onPressed: () =>
                                                  _openPaymentRequestDialog(
                                                monthKey: _monthKey,
                                                suggestedAmount:
                                                    summary.totalDue,
                                              ),
                                              icon: const Icon(
                                                  Icons.verified_user_outlined),
                                              label: const Text(
                                                  'Request Admin Verification (Payment Done)'),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Month Payment History',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            if (summary.payments.isEmpty)
                              const Text(
                                  'No payment references submitted for this month.')
                            else
                              ...summary.payments.map((PaymentRecord p) => Card(
                                    child: ListTile(
                                      title: Text(
                                        'Txn ${p.txnRef} | INR ${p.amount.toStringAsFixed(2)}',
                                      ),
                                      subtitle: Text(
                                        'Status: ${_statusLabel(p.status)}'
                                        '${p.requestedAt == null ? '' : '\nRequested: ${DateFormat('dd MMM yyyy, hh:mm a').format(p.requestedAt!)}'}'
                                        '${p.updatedAt == null ? '' : '\nUpdated: ${DateFormat('dd MMM yyyy, hh:mm a').format(p.updatedAt!)}'}',
                                      ),
                                      isThreeLine: true,
                                    ),
                                  )),
                            const SizedBox(height: 12),
                            Card(
                              child: Column(
                                children: <Widget>[
                                  ListTile(
                                    title: const Text(
                                      'Usage History',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700),
                                    ),
                                    subtitle: const Text(
                                      'Daily / Weekly / Monthly (hidden by default)',
                                    ),
                                    trailing: IconButton(
                                      onPressed: () {
                                        setState(() {
                                          _showUsageHistory =
                                              !_showUsageHistory;
                                        });
                                      },
                                      icon: Icon(_showUsageHistory
                                          ? Icons.expand_less
                                          : Icons.expand_more),
                                    ),
                                  ),
                                  if (_showUsageHistory)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          12, 0, 12, 12),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Wrap(
                                            spacing: 8,
                                            children: <Widget>[
                                              ChoiceChip(
                                                label: const Text('Daily'),
                                                selected: _historyScope ==
                                                    HistoryScope.daily,
                                                onSelected: (bool selected) {
                                                  if (!selected) {
                                                    return;
                                                  }
                                                  setState(() {
                                                    _historyScope =
                                                        HistoryScope.daily;
                                                  });
                                                },
                                              ),
                                              ChoiceChip(
                                                label: const Text('Weekly'),
                                                selected: _historyScope ==
                                                    HistoryScope.weekly,
                                                onSelected: (bool selected) {
                                                  if (!selected) {
                                                    return;
                                                  }
                                                  setState(() {
                                                    _historyScope =
                                                        HistoryScope.weekly;
                                                  });
                                                },
                                              ),
                                              ChoiceChip(
                                                label: const Text('Monthly'),
                                                selected: _historyScope ==
                                                    HistoryScope.monthly,
                                                onSelected: (bool selected) {
                                                  if (!selected) {
                                                    return;
                                                  }
                                                  setState(() {
                                                    _historyScope =
                                                        HistoryScope.monthly;
                                                  });
                                                },
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          Builder(
                                            builder: (BuildContext context) {
                                              final List<UsageHistoryGroup>
                                                  groups = _buildHistoryGroups(
                                                summary.sessions,
                                              );
                                              if (groups.isEmpty) {
                                                return const Text(
                                                  'No completed usage history for selected month.',
                                                );
                                              }
                                              return Column(
                                                children: groups
                                                    .map(
                                                        (UsageHistoryGroup g) =>
                                                            Card(
                                                              child:
                                                                  ExpansionTile(
                                                                title: Text(
                                                                    g.label),
                                                                subtitle: Text(
                                                                  'Sessions: ${g.sessionsCount} | Units: ${g.totalUnits.toStringAsFixed(2)} kWh',
                                                                ),
                                                                trailing: Text(
                                                                  'INR ${g.totalAmount.toStringAsFixed(2)}',
                                                                  style:
                                                                      const TextStyle(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700,
                                                                  ),
                                                                ),
                                                                children: g.rows
                                                                    .map((SessionBillRow
                                                                            row) =>
                                                                        ListTile(
                                                                          dense:
                                                                              true,
                                                                          title:
                                                                              Text('${row.vehicleNumber} | ${row.pointKey}'),
                                                                          subtitle:
                                                                              Text(
                                                                            DateFormat('dd MMM yyyy, hh:mm a').format(row.shownAt),
                                                                          ),
                                                                          trailing:
                                                                              Text(
                                                                            'INR ${row.amount.toStringAsFixed(2)}',
                                                                          ),
                                                                        ))
                                                                    .toList(),
                                                              ),
                                                            ))
                                                    .toList(),
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            ),
        ],
      ),
    );
  }
}

class _MergedPaymentDocs extends StatelessWidget {
  const _MergedPaymentDocs({
    required this.uid,
    required this.scope,
    required this.monthKey,
    required this.builder,
  });

  final String uid;
  final FlatProfileScope? scope;
  final String monthKey;
  final Widget Function(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs)
      builder;

  @override
  Widget build(BuildContext context) {
    final FlatProfileScope? flatScope = scope;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('payments')
          .where('ownerUid', isEqualTo: uid)
          .snapshots(),
      builder: (BuildContext context,
          AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> ownSnap) {
        if (flatScope == null) {
          return _loaded(ownSnap, null);
        }
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('payments')
              .where('billingFlatKey', isEqualTo: flatScope.key)
              .snapshots(),
          builder: (BuildContext context,
              AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> flatSnap) {
            return _loaded(ownSnap, flatSnap);
          },
        );
      },
    );
  }

  Widget _loaded(
    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> ownSnap,
    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>>? flatSnap,
  ) {
    if (ownSnap.hasError || (flatSnap?.hasError ?? false)) {
      return Text('Payments load failed: ${ownSnap.error ?? flatSnap?.error}');
    }
    if (!ownSnap.hasData || (flatSnap != null && !flatSnap.hasData)) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> merged =
        <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
        in ownSnap.data!.docs) {
      merged[doc.id] = doc;
    }
    if (flatSnap != null) {
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in flatSnap.data!.docs) {
        merged[doc.id] = doc;
      }
    }
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs = merged.values
        .where((QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
            FlatBillMath.paymentCounts(
              data: doc.data(),
              scope: scope,
              viewerUid: uid,
              monthKey: monthKey,
            ))
        .toList()
      ..sort((QueryDocumentSnapshot<Map<String, dynamic>> a,
          QueryDocumentSnapshot<Map<String, dynamic>> b) {
        final int aTime =
            (a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        final int bTime =
            (b.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        return bTime.compareTo(aTime);
      });
    return builder(docs);
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class MonthlyBillSummary {
  MonthlyBillSummary({
    required this.monthKey,
    required this.sessions,
    required this.payments,
    required this.statusLabelResolver,
  }) {
    totalUnits =
        sessions.fold<double>(0, (double p, SessionBillRow e) => p + e.units);
    totalAmount =
        sessions.fold<double>(0, (double p, SessionBillRow e) => p + e.amount);
    totalPaid = payments
        .where(
            (PaymentRecord p) => p.status == 'paid' || p.status == 'verified')
        .fold<double>(0, (double p, PaymentRecord e) => p + e.amount);
    final int pending =
        payments.where((PaymentRecord p) => p.status == 'submitted').length;
    final int rejected =
        payments.where((PaymentRecord p) => p.status == 'rejected').length;
    final double rawDue = totalAmount - totalPaid;
    totalDue = rawDue < 0 ? 0 : rawDue;
    if (totalAmount <= 0) {
      overallStatus = 'No Dues';
    } else if (totalPaid >= totalAmount) {
      overallStatus = 'Paid';
    } else if (pending > 0) {
      overallStatus = statusLabelResolver('submitted');
    } else if (rejected > 0) {
      overallStatus = statusLabelResolver('rejected');
    } else {
      overallStatus = 'Pending';
    }
  }

  final String monthKey;
  final List<SessionBillRow> sessions;
  final List<PaymentRecord> payments;
  final String Function(String) statusLabelResolver;
  late final double totalUnits;
  late final double totalAmount;
  late final double totalPaid;
  late final double totalDue;
  late final String overallStatus;

  String get monthDisplay {
    final DateTime monthDate = DateTime.parse('$monthKey-01');
    return DateFormat('MMMM yyyy').format(monthDate);
  }
}

class SessionBillRow {
  SessionBillRow({
    required this.pointKey,
    required this.vehicleNumber,
    required this.startMeter,
    required this.endMeter,
    required this.units,
    required this.amount,
    required this.shownAt,
  });

  factory SessionBillRow.fromMap(Map<String, dynamic> data) {
    return SessionBillRow(
      pointKey: (data['pointKey'] ?? '-').toString(),
      vehicleNumber: (data['vehicleNumber'] ?? '-').toString(),
      startMeter: (data['startMeter'] as num?)?.toDouble() ?? 0,
      endMeter: (data['endMeter'] as num?)?.toDouble() ?? 0,
      units: (data['units'] as num?)?.toDouble() ?? 0,
      amount: (data['amount'] as num?)?.toDouble() ?? 0,
      shownAt: (data['endTime'] as Timestamp?)?.toDate() ??
          (data['createdAt'] as Timestamp?)?.toDate() ??
          DateTime.now(),
    );
  }

  final String pointKey;
  final String vehicleNumber;
  final double startMeter;
  final double endMeter;
  final double units;
  final double amount;
  final DateTime shownAt;
}

class PaymentRecord {
  PaymentRecord({
    required this.txnRef,
    required this.amount,
    required this.status,
    required this.requestedAt,
    required this.updatedAt,
  });

  factory PaymentRecord.fromMap(Map<String, dynamic> data) {
    return PaymentRecord(
      txnRef: (data['txnRef'] ?? '-').toString(),
      amount: (data['amount'] as num?)?.toDouble() ?? 0,
      status: (data['status'] ?? 'submitted').toString(),
      requestedAt: (data['requestedAt'] as Timestamp?)?.toDate() ??
          (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['paidAt'] as Timestamp?)?.toDate() ??
          (data['verifiedAt'] as Timestamp?)?.toDate(),
    );
  }

  final String txnRef;
  final double amount;
  final String status;
  final DateTime? requestedAt;
  final DateTime? updatedAt;
}

enum HistoryScope {
  daily,
  weekly,
  monthly,
}

class UsageHistoryGroupBuilder {
  UsageHistoryGroupBuilder(this.label);

  final String label;
  final List<SessionBillRow> rows = <SessionBillRow>[];

  void add(SessionBillRow row) {
    rows.add(row);
  }

  UsageHistoryGroup toGroup() {
    final double totalUnits =
        rows.fold<double>(0, (double p, SessionBillRow e) => p + e.units);
    final double totalAmount =
        rows.fold<double>(0, (double p, SessionBillRow e) => p + e.amount);
    return UsageHistoryGroup(
      label: label,
      rows: rows,
      sessionsCount: rows.length,
      totalUnits: totalUnits,
      totalAmount: totalAmount,
    );
  }
}

class UsageHistoryGroup {
  UsageHistoryGroup({
    required this.label,
    required this.rows,
    required this.sessionsCount,
    required this.totalUnits,
    required this.totalAmount,
  });

  final String label;
  final List<SessionBillRow> rows;
  final int sessionsCount;
  final double totalUnits;
  final double totalAmount;
}
