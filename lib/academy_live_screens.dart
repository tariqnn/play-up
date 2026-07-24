import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'academy_service.dart';

class LiveCourtManagementScreen extends StatelessWidget {
  const LiveCourtManagementScreen({super.key});
  @override
  Widget build(BuildContext context) => _TenantScaffold(
    title: 'Court management',
    builder: (academyId) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: AcademyService.instance.courts(academyId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: FilledButton.icon(
                  onPressed: () => _edit(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Add court'),
                ),
              );
            }
            final doc = docs[index - 1];
            final data = doc.data();
            return Card(
              child: ListTile(
                title: Text(data['name']?.toString() ?? 'Court'),
                subtitle: Text(
                  '${data['sport'] ?? 'Sport'} • ${data['currency'] ?? 'JOD'} ${((data['basePriceMinor'] as num? ?? 0) / 100).toStringAsFixed(2)} / hr',
                ),
                trailing: IconButton(
                  tooltip: 'Edit court',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _edit(context, id: doc.id, data: data),
                ),
              ),
            );
          },
        );
      },
    ),
  );

  Future<void> _edit(
    BuildContext context, {
    String? id,
    Map<String, dynamic>? data,
  }) async {
    final name = TextEditingController(text: data?['name']?.toString());
    final sport = TextEditingController(text: data?['sport']?.toString());
    var currency = data?['currency']?.toString() ?? 'JOD';
    final price = TextEditingController(
      text: ((data?['basePriceMinor'] as num? ?? 0) / 100).toStringAsFixed(0),
    );
    final address = TextEditingController(text: data?['address']?.toString());
    final latitude = TextEditingController(text: data?['latitude']?.toString());
    final longitude = TextEditingController(
      text: data?['longitude']?.toString(),
    );
    final imageUrl = TextEditingController(text: data?['imageUrl']?.toString());
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(id == null ? 'Add court' : 'Edit court'),
        content: StatefulBuilder(
          builder: (context, setDialogState) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: sport.text.isEmpty ? 'Football' : sport.text,
                  decoration: const InputDecoration(labelText: 'Sport'),
                  items:
                      [
                            'Football',
                            'Basketball',
                            'Padel',
                            'Tennis',
                            'Volleyball',
                            'Cricket',
                            'Handball',
                          ]
                          .map(
                            (v) => DropdownMenuItem(value: v, child: Text(v)),
                          )
                          .toList(),
                  onChanged: (v) => sport.text = v!,
                ),
                DropdownButtonFormField<String>(
                  initialValue: currency,
                  decoration: const InputDecoration(labelText: 'Currency'),
                  items:
                      ['JOD', 'AED', 'SAR', 'QAR', 'KWD', 'BHD', 'OMR', 'USD']
                          .map(
                            (v) => DropdownMenuItem(value: v, child: Text(v)),
                          )
                          .toList(),
                  onChanged: (v) => setDialogState(() => currency = v!),
                ),
                TextField(
                  controller: price,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Hourly price'),
                ),
                TextField(
                  controller: address,
                  decoration: const InputDecoration(labelText: 'Full address'),
                ),
                TextField(
                  controller: latitude,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Latitude'),
                ),
                TextField(
                  controller: longitude,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Longitude'),
                ),
                TextField(
                  controller: imageUrl,
                  decoration: const InputDecoration(
                    labelText: 'Court photo URL',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final amount = double.tryParse(price.text);
              final lat = double.tryParse(latitude.text);
              final lng = double.tryParse(longitude.text);
              if (name.text.trim().isEmpty ||
                  sport.text.trim().isEmpty ||
                  amount == null ||
                  amount <= 0 ||
                  address.text.trim().isEmpty ||
                  lat == null ||
                  lng == null ||
                  lat < -90 ||
                  lat > 90 ||
                  lng < -180 ||
                  lng > 180) {
                return;
              }
              await AcademyService.instance.saveCourt(
                courtId: id,
                name: name.text,
                sport: sport.text,
                basePriceMinor: (amount * 100).round(),
                currency: currency,
                address: address.text,
                latitude: lat,
                longitude: lng,
                imageUrl: imageUrl.text,
              );
              if (dialog.mounted) Navigator.pop(dialog);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    name.dispose();
    sport.dispose();
    price.dispose();
    address.dispose();
    latitude.dispose();
    longitude.dispose();
    imageUrl.dispose();
  }
}

class LiveBookingManagementScreen extends StatelessWidget {
  const LiveBookingManagementScreen({super.key});
  @override
  Widget build(BuildContext context) => _TenantScaffold(
    title: 'Academy bookings',
    builder: (academyId) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: AcademyService.instance.bookings(academyId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text('No academy bookings yet.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data();
            final status = data['status']?.toString() ?? 'unknown';
            final start = (data['startUtc'] as Timestamp?)?.toDate().toLocal();
            return Card(
              child: ListTile(
                title: Text(data['courtName']?.toString() ?? 'Booking'),
                subtitle: Text('${start ?? 'Time unavailable'} • $status'),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) => value == 'cash'
                      ? _cash(context, doc.id)
                      : _change(context, doc.id, value),
                  itemBuilder: (_) => [
                    if (status == 'pending')
                      const PopupMenuItem(
                        value: 'confirmed',
                        child: Text('Confirm booking'),
                      ),
                    if (status == 'confirmed')
                      const PopupMenuItem(
                        value: 'checkedIn',
                        child: Text('Check in'),
                      ),
                    if (status == 'checkedIn')
                      const PopupMenuItem(
                        value: 'completed',
                        child: Text('Complete'),
                      ),
                    if (data['paymentStatus'] != 'collected')
                      const PopupMenuItem(
                        value: 'cash',
                        child: Text('Record cash received'),
                      ),
                    if (!['cancelled', 'completed'].contains(status))
                      const PopupMenuItem(
                        value: 'cancelled',
                        child: Text('Cancel booking'),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ),
  );
  Future<void> _change(BuildContext context, String id, String status) async {
    try {
      await AcademyService.instance.transitionBooking(id, status);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _cash(BuildContext context, String id) async {
    try {
      await AcademyService.instance.recordCashPayment(id);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }
}

class LiveAcademyAnalyticsScreen extends StatelessWidget {
  const LiveAcademyAnalyticsScreen({super.key});
  @override
  Widget build(BuildContext context) => _TenantScaffold(
    title: 'Academy analytics',
    builder: (academyId) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: AcademyService.instance.bookings(academyId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snapshot.data!.docs.map((e) => e.data()).toList();
        final completed = rows
            .where((e) => e['status'] == 'completed')
            .toList();
        final revenue = completed.fold<int>(
          0,
          (total, e) => total + (e['totalMinor'] as num? ?? 0).toInt(),
        );
        final cancelled = rows.where((e) => e['status'] == 'cancelled').length;
        return GridView.count(
          padding: const EdgeInsets.all(16),
          crossAxisCount: MediaQuery.sizeOf(context).width > 700 ? 4 : 2,
          childAspectRatio: 1.5,
          children: [
            _Metric('Bookings', '${rows.length}'),
            _Metric('Revenue', 'JOD ${(revenue / 100).toStringAsFixed(2)}'),
            _Metric('Completed', '${completed.length}'),
            _Metric('Cancelled', '$cancelled'),
          ],
        );
      },
    ),
  );
}

class AcademyProfileManagementScreen extends StatelessWidget {
  const AcademyProfileManagementScreen({super.key});
  @override
  Widget build(BuildContext context) => _TenantScaffold(
    title: 'Academy profile',
    builder: (id) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: AcademyService.instance.academy(id),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!.data() ?? {};
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              initialValue: data['name']?.toString(),
              decoration: const InputDecoration(labelText: 'Academy name'),
              onChanged: (v) => data['name'] = v,
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: data['phone']?.toString(),
              decoration: const InputDecoration(labelText: 'Contact phone'),
              onChanged: (v) => data['phone'] = v,
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: data['address']?.toString(),
              decoration: const InputDecoration(labelText: 'Address'),
              onChanged: (v) => data['address'] = v,
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: data['description']?.toString(),
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Description'),
              onChanged: (v) => data['description'] = v,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () async {
                try {
                  await AcademyService.instance.saveAcademy({
                    'name': data['name'] ?? '',
                    'phone': data['phone'] ?? '',
                    'address': data['address'] ?? '',
                    'description': data['description'] ?? '',
                  });
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Academy profile saved.')),
                    );
                  }
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(error.toString())));
                  }
                }
              },
              child: const Text('Save academy profile'),
            ),
          ],
        );
      },
    ),
  );
}

class AcademyStaffManagementScreen extends StatelessWidget {
  const AcademyStaffManagementScreen({super.key});
  @override
  Widget build(BuildContext context) => _TenantScaffold(
    title: 'Staff management',
    builder: (id) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: AcademyService.instance.staff(id),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs
            .where((d) => d.data()['role'] == 'academyStaff')
            .toList();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FilledButton.icon(
              onPressed: () => _add(context),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Add staff account'),
            ),
            const SizedBox(height: 12),
            if (docs.isEmpty)
              const Card(
                child: ListTile(title: Text('No staff accounts yet.')),
              ),
            ...docs.map(
              (d) => Card(
                child: ListTile(
                  title: Text(d.data()['displayName']?.toString() ?? 'Staff'),
                  subtitle: Text(
                    '${d.data()['email'] ?? ''}\n${(d.data()['permissions'] as List? ?? []).join(', ')}',
                  ),
                  isThreeLine: true,
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
  Future<void> _add(BuildContext context) async {
    final name = TextEditingController(),
        email = TextEditingController(),
        password = TextEditingController();
    final permissions = <String>{
      'academy.bookings.manage',
      'academy.bookings.checkin',
    };
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Add staff account'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Full name'),
              ),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Temporary password (12+ characters)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await AcademyService.instance.createStaff(
                  displayName: name.text,
                  email: email.text,
                  temporaryPassword: password.text,
                  permissions: permissions.toList(),
                );
                if (dialog.mounted) Navigator.pop(dialog);
              } catch (error) {
                if (dialog.mounted) {
                  ScaffoldMessenger.of(
                    dialog,
                  ).showSnackBar(SnackBar(content: Text(error.toString())));
                }
              }
            },
            child: const Text('Create staff'),
          ),
        ],
      ),
    );
    name.dispose();
    email.dispose();
    password.dispose();
  }
}

class _TenantScaffold extends StatelessWidget {
  const _TenantScaffold({required this.title, required this.builder});
  final String title;
  final Widget Function(String) builder;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: FutureBuilder<String>(
      future: AcademyService.instance.academyId(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || snapshot.data == null) {
          return Center(child: Text(snapshot.error.toString()));
        }
        return builder(snapshot.data!);
      },
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Card(
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: Theme.of(context).textTheme.headlineSmall),
          Text(label),
        ],
      ),
    ),
  );
}
