import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
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
                child: FutureBuilder<OwnerScope>(
                  future: AcademyService.instance.ownerScope(),
                  builder: (context, scope) => FilledButton.icon(
                    onPressed: scope.data?.isCourtOwner == true
                        ? null
                        : () => _edit(context),
                    icon: const Icon(Icons.add),
                    label: Text(
                      scope.data?.isCourtOwner == true
                          ? 'Court owner access'
                          : 'Add court',
                    ),
                  ),
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
    Uint8List? pickedImage;
    String? pickedImageName;
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
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final initial = LatLng(
                      double.tryParse(latitude.text) ?? 31.9539,
                      double.tryParse(longitude.text) ?? 35.9106,
                    );
                    final point = await Navigator.of(context).push<LatLng>(
                      MaterialPageRoute(
                        fullscreenDialog: true,
                        builder: (_) => _CourtLocationPicker(initial: initial),
                      ),
                    );
                    if (point != null) {
                      setDialogState(() {
                        latitude.text = point.latitude.toStringAsFixed(6);
                        longitude.text = point.longitude.toStringAsFixed(6);
                      });
                    }
                  },
                  icon: const Icon(Icons.map_outlined),
                  label: Text(
                    latitude.text.isEmpty
                        ? 'Choose location on map'
                        : 'Location selected • change',
                  ),
                ),
                const SizedBox(height: 12),
                if (pickedImage != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      pickedImage!,
                      height: 130,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  )
                else if (imageUrl.text.trim().isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      imageUrl.text.trim(),
                      height: 130,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final file = await ImagePicker().pickImage(
                      source: ImageSource.gallery,
                      imageQuality: 86,
                      maxWidth: 1800,
                    );
                    if (file == null) return;
                    final bytes = await file.readAsBytes();
                    if (bytes.lengthInBytes > 5 * 1024 * 1024) return;
                    setDialogState(() {
                      pickedImage = bytes;
                      pickedImageName = file.name;
                    });
                  },
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(
                    pickedImage == null ? 'Add court photo' : 'Change photo',
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
              final courtId =
                  id ?? AcademyService.instance.newCourtId();
              var savedImageUrl = imageUrl.text.trim();
              if (pickedImage != null) {
                savedImageUrl = await AcademyService.instance.uploadCourtImage(
                  courtId: courtId,
                  bytes: pickedImage!,
                  fileName: pickedImageName ?? 'court.jpg',
                );
              }
              await AcademyService.instance.saveCourt(
                courtId: courtId,
                name: name.text,
                sport: sport.text,
                basePriceMinor: (amount * 100).round(),
                currency: currency,
                address: address.text,
                latitude: lat,
                longitude: lng,
                imageUrl: savedImageUrl,
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

class _CourtLocationPicker extends StatefulWidget {
  const _CourtLocationPicker({required this.initial});
  final LatLng initial;

  @override
  State<_CourtLocationPicker> createState() => _CourtLocationPickerState();
}

class _CourtLocationPickerState extends State<_CourtLocationPicker> {
  late LatLng _selected = widget.initial;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Court location'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, _selected),
          child: const Text('Use location'),
        ),
      ],
    ),
    body: FlutterMap(
      options: MapOptions(
        initialCenter: widget.initial,
        initialZoom: 14,
        onTap: (_, point) => setState(() => _selected = point),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.playup.app',
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: _selected,
              width: 52,
              height: 52,
              child: const Icon(
                Icons.location_pin,
                size: 48,
                color: Colors.red,
              ),
            ),
          ],
        ),
        const RichAttributionWidget(
          attributions: [
            TextSourceAttribution('OpenStreetMap contributors'),
          ],
        ),
      ],
    ),
  );
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
