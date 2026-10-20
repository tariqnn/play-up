import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'catalog.dart';
import 'main.dart';
import 'custom_dashboard.dart';
import 'location_service.dart';

// ---------------------------------------------------------------------------
// Admin hub
// ---------------------------------------------------------------------------

class AdminPanelScreen extends StatelessWidget {
  const AdminPanelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppScrollPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTopBar(
              title: 'Admin Panel',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 16),
            CardBox(
              color: AppColors.dark,
              borderColor: AppColors.dark,
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  const Icon(
                    CupertinoIcons.lock_shield_fill,
                    color: AppColors.gold,
                    size: 30,
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      'Manage all app data — courts, academies, offers, events and players.',
                      style: TextStyle(color: Colors.white, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _AdminTile(
              icon: CupertinoIcons.square_grid_2x2,
              title: 'Custom dashboard',
              subtitle: 'Reorder, resize, hide and persist widgets',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const CustomDashboard(
                    scope: 'platform',
                    available: platformWidgets,
                  ),
                ),
              ),
            ),
            _AdminTile(
              icon: CupertinoIcons.sportscourt,
              title: 'Courts',
              subtitle: 'Add, edit and remove courts',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AdminCourtsScreen()),
              ),
            ),
            _AdminTile(
              icon: CupertinoIcons.building_2_fill,
              title: 'Academies',
              subtitle: 'Manage academy listings',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AdminAcademiesScreen()),
              ),
            ),
            _AdminTile(
              icon: CupertinoIcons.gift_fill,
              title: 'Offers',
              subtitle: 'Manage reward offers',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AdminOffersScreen()),
              ),
            ),
            _AdminTile(
              icon: CupertinoIcons.rosette,
              title: 'Events',
              subtitle: 'Manage tournaments and events',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AdminEventsScreen()),
              ),
            ),
            _AdminTile(
              icon: CupertinoIcons.person_2_fill,
              title: 'Players',
              subtitle: 'View registered players',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AdminUsersScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminTile extends StatelessWidget {
  const _AdminTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CardBox(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.purple.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppColors.purple),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                CupertinoIcons.chevron_right,
                color: AppColors.muted,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Generic collection editor
// ---------------------------------------------------------------------------

class AdminField {
  const AdminField(this.key, this.label, {this.number = false});
  final String key;
  final String label;
  final bool number;
}

class AdminCollectionScreen extends StatelessWidget {
  const AdminCollectionScreen({
    super.key,
    required this.collection,
    required this.title,
    required this.fields,
    required this.titleKey,
    required this.subtitleKey,
    this.hasGradient = false,
    this.hasIcon = false,
    this.hasFeatured = false,
    this.showTestCourtAction = false,
  });

  final String collection;
  final String title;
  final List<AdminField> fields;
  final String titleKey;
  final String subtitleKey;
  final bool hasGradient;
  final bool hasIcon;
  final bool hasFeatured;
  final bool showTestCourtAction;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: showTestCourtAction
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.extended(
                  heroTag: 'create-playup-test-court',
                  backgroundColor: AppColors.dark,
                  onPressed: () => _createTestCourt(context),
                  icon: const Icon(
                    CupertinoIcons.sportscourt,
                    color: Colors.white,
                  ),
                  label: const Text(
                    'Create test court',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.extended(
                  heroTag: 'add-court',
                  backgroundColor: AppColors.purple,
                  onPressed: () => _openEditor(context),
                  icon: const Icon(CupertinoIcons.add, color: Colors.white),
                  label: const Text(
                    'Add court',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            )
          : FloatingActionButton.extended(
              backgroundColor: AppColors.purple,
              onPressed: () => _openEditor(context),
              icon: const Icon(CupertinoIcons.add, color: Colors.white),
              label: const Text(
                'Add',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
      body: AppScrollPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTopBar(title: title, onBack: () => Navigator.of(context).pop()),
            const SizedBox(height: 12),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: CatalogService.instance.raw(collection),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _ErrorCard(message: '${snapshot.error}');
                }
                if (!snapshot.hasData) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: CupertinoActivityIndicator(),
                    ),
                  );
                }
                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return EmptyState(
                    icon: CupertinoIcons.tray,
                    title: 'No $title yet',
                    message: 'Tap Add to create the first entry.',
                    action: 'Add',
                    onTap: () => _openEditor(context),
                  );
                }
                return Column(
                  children: [
                    for (final doc in docs)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: CardBox(
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (doc.data()[titleKey] ?? '—').toString(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    Text(
                                      (doc.data()[subtitleKey] ?? '')
                                          .toString(),
                                      style: const TextStyle(
                                        color: AppColors.muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () => _openEditor(context, doc: doc),
                                icon: const Icon(
                                  CupertinoIcons.pencil,
                                  color: AppColors.purple,
                                ),
                              ),
                              IconButton(
                                onPressed: () =>
                                    _confirmDelete(context, doc.id),
                                icon: const Icon(
                                  CupertinoIcons.trash,
                                  color: AppColors.danger,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, String id) async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Delete this entry?'),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('Delete'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      try {
        await CatalogService.instance.delete(collection, id);
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Delete failed: $error')));
        }
      }
    }
  }

  Future<void> _createTestCourt(BuildContext context) async {
    final create = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Create test court?'),
        content: const Text(
          'Adds a clearly marked test-only academy and court so booking and match flows can reach the live backend. Neither is a real venue. Remove both from the Academies and Courts admin lists when testing is finished.',
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('Create test court'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (create != true || !context.mounted) return;
    try {
      final db = FirebaseFirestore.instance;
      final batch = db.batch();
      final now = FieldValue.serverTimestamp();
      final location = LocationService.instance.current.value;
      final testLatitude = location?.latitude ?? 31.9539;
      final testLongitude = location?.longitude ?? 35.9106;
      final testLocationLabel = location?.label ?? 'Amman';
      batch.set(
        db.collection('academies').doc('playup-test-academy'),
        {
          'name': 'PlayUp Test Academy - TEST ONLY',
          'sports': 'Basketball',
          'rating': 'Test venue',
          'distance': 'Test location',
          'featured': false,
          'gradient': 'teal',
          'icon': 'court',
          'address': 'Test location - $testLocationLabel (not a real venue)',
          'latitude': testLatitude,
          'longitude': testLongitude,
          'imageUrl': '',
          'description': 'Test-only venue for PlayUp booking flow checks.',
          'status': 'active',
          'isTestData': true,
          'trainingPackages': <String>[],
          'packages': <Map<String, dynamic>>[],
          'createdAt': now,
          'updatedAt': now,
        },
        SetOptions(merge: true),
      );
      batch.set(db.collection('courts').doc('playup-test-court'), {
        'academyId': 'playup-test-academy',
        'name': 'PlayUp Test Court — TEST ONLY',
        'subtitle': 'TEST ONLY • Basketball • Not a real venue',
        'sport': 'Basketball',
        'rating': 'Test venue',
        'distance': 'Test location',
        'price': 'JOD 1.00 / hr (test)',
        'basePriceMinor': 100,
        'currency': 'JOD',
        'address': 'Test location - $testLocationLabel (not a real venue)',
        'latitude': testLatitude,
        'longitude': testLongitude,
        'imageUrl': '',
        'description':
            'Demo listing for PlayUp booking and match testing only.',
        'active': true,
        'bookable': true,
        'openingHour': 6,
        'closingHour': 23,
        'timezone': 'Asia/Amman',
        'blockedPeriods': <Map<String, dynamic>>[],
        'maintenancePeriods': <Map<String, dynamic>>[],
        'isTestCourt': true,
        'isTestData': true,
        'gradient': 'teal',
        'icon': 'court',
        'createdAt': now,
        'updatedAt': now,
      }, SetOptions(merge: true));
      await batch.commit();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Test academy and court are live. Delete them from the Academies and Courts admin lists when finished.',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create test court: $error')),
      );
    }
  }

  void _openEditor(
    BuildContext context, {
    QueryDocumentSnapshot<Map<String, dynamic>>? doc,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _CollectionEditor(
        collection: collection,
        fields: fields,
        hasGradient: hasGradient,
        hasIcon: hasIcon,
        hasFeatured: hasFeatured,
        doc: doc,
      ),
    );
  }
}

class _CollectionEditor extends StatefulWidget {
  const _CollectionEditor({
    required this.collection,
    required this.fields,
    required this.hasGradient,
    required this.hasIcon,
    required this.hasFeatured,
    this.doc,
  });

  final String collection;
  final List<AdminField> fields;
  final bool hasGradient;
  final bool hasIcon;
  final bool hasFeatured;
  final QueryDocumentSnapshot<Map<String, dynamic>>? doc;

  @override
  State<_CollectionEditor> createState() => _CollectionEditorState();
}

class _CollectionEditorState extends State<_CollectionEditor> {
  late final Map<String, TextEditingController> _controllers;
  late String _gradient;
  late String _icon;
  late bool _featured;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final data = widget.doc?.data() ?? {};
    _controllers = {
      for (final f in widget.fields)
        f.key: TextEditingController(text: (data[f.key] ?? '').toString()),
    };
    _gradient = (data['gradient'] ?? 'teal').toString();
    _icon = (data['icon'] ?? 'court').toString();
    _featured = data['featured'] == true;
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final payload = <String, dynamic>{
      for (final f in widget.fields) f.key: _controllers[f.key]!.text.trim(),
      if (widget.hasGradient) 'gradient': _gradient,
      if (widget.hasIcon) 'icon': _icon,
      if (widget.hasFeatured) 'featured': _featured,
    };
    try {
      await CatalogService.instance.upsert(
        widget.collection,
        widget.doc?.id,
        payload,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Save failed: $error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        18,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.doc == null ? 'New entry' : 'Edit entry',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 16),
            for (final f in widget.fields) ...[
              AppTextField(
                controller: _controllers[f.key]!,
                label: f.label,
                icon: CupertinoIcons.textformat,
                keyboardType: f.number
                    ? TextInputType.number
                    : TextInputType.text,
              ),
              const SizedBox(height: 12),
            ],
            if (widget.hasGradient) ...[
              _PresetPicker(
                label: 'Theme',
                keys: kGradientPresets.keys.toList(),
                selected: _gradient,
                onSelect: (v) => setState(() => _gradient = v),
                colorFor: (k) => gradientFor(k).last,
              ),
              const SizedBox(height: 12),
            ],
            if (widget.hasIcon) ...[
              _PresetPicker(
                label: 'Icon',
                keys: kIconPresets.keys.toList(),
                selected: _icon,
                onSelect: (v) => setState(() => _icon = v),
                iconFor: (k) => iconFor(k),
              ),
              const SizedBox(height: 12),
            ],
            if (widget.hasFeatured)
              CardBox(
                child: SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _featured,
                  activeThumbColor: AppColors.purple,
                  title: const Text(
                    'Featured',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  onChanged: (v) => setState(() => _featured = v),
                ),
              ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: _saving ? 'Saving...' : 'Save',
              onPressed: _saving ? () {} : _save,
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetPicker extends StatelessWidget {
  const _PresetPicker({
    required this.label,
    required this.keys,
    required this.selected,
    required this.onSelect,
    this.colorFor,
    this.iconFor,
  });

  final String label;
  final List<String> keys;
  final String selected;
  final ValueChanged<String> onSelect;
  final Color Function(String)? colorFor;
  final IconData Function(String)? iconFor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final key in keys)
              GestureDetector(
                onTap: () => onSelect(key),
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: colorFor?.call(key) ?? AppColors.background,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected == key
                          ? AppColors.purple
                          : AppColors.line,
                      width: selected == key ? 3 : 1,
                    ),
                  ),
                  child: iconFor != null
                      ? Icon(iconFor!(key), color: AppColors.purple)
                      : null,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return CardBox(
      child: Column(
        children: [
          const Icon(
            CupertinoIcons.exclamationmark_triangle,
            color: AppColors.danger,
            size: 32,
          ),
          const SizedBox(height: 10),
          const Text(
            'Could not load data',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Concrete admin screens
// ---------------------------------------------------------------------------

class AdminCourtsScreen extends StatelessWidget {
  const AdminCourtsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminCollectionScreen(
      collection: 'courts',
      title: 'Courts',
      titleKey: 'name',
      subtitleKey: 'subtitle',
      hasGradient: true,
      hasIcon: true,
      showTestCourtAction: true,
      fields: [
        AdminField('name', 'Court name'),
        AdminField('subtitle', 'Sport / type'),
        AdminField('rating', 'Rating (e.g. 4.8 (128))'),
        AdminField('distance', 'Distance (e.g. 1.2 km)'),
        AdminField('price', 'Price (e.g. JOD 21 / hr)'),
        AdminField('image', 'Image URL (https://...)'),
      ],
    );
  }
}

class AdminAcademiesScreen extends StatelessWidget {
  const AdminAcademiesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminCollectionScreen(
      collection: 'academies',
      title: 'Academies',
      titleKey: 'name',
      subtitleKey: 'sports',
      hasGradient: true,
      hasIcon: true,
      hasFeatured: true,
      fields: [
        AdminField('name', 'Academy name'),
        AdminField('sports', 'Sports (e.g. Basketball • Padel)'),
        AdminField('rating', 'Rating'),
        AdminField('distance', 'Distance'),
        AdminField('image', 'Image URL (https://...)'),
      ],
    );
  }
}

class AdminOffersScreen extends StatelessWidget {
  const AdminOffersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminCollectionScreen(
      collection: 'offers',
      title: 'Offers',
      titleKey: 'title',
      subtitleKey: 'partner',
      hasGradient: true,
      fields: [
        AdminField('title', 'Offer title'),
        AdminField('partner', 'Brand / academy'),
        AdminField('points', 'Points required', number: true),
      ],
    );
  }
}

class AdminEventsScreen extends StatelessWidget {
  const AdminEventsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminCollectionScreen(
      collection: 'events',
      title: 'Events',
      titleKey: 'title',
      subtitleKey: 'date',
      fields: [
        AdminField('title', 'Event title'),
        AdminField('date', 'Date / entry'),
        AdminField('prize', 'Prize / notes'),
      ],
    );
  }
}

class AdminUsersScreen extends StatelessWidget {
  const AdminUsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppScrollPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTopBar(
              title: 'Players',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 12),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _ErrorCard(message: '${snapshot.error}');
                }
                if (!snapshot.hasData) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: CupertinoActivityIndicator(),
                    ),
                  );
                }
                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return const CardBox(
                    child: Text(
                      'No players registered yet.',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final doc in docs)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: CardBox(
                          child: Row(
                            children: [
                              Avatar(
                                name: (doc.data()['displayName'] ?? 'P')
                                    .toString()
                                    .characters
                                    .first,
                                size: 42,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (doc.data()['displayName'] ?? 'Player')
                                          .toString(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    Text(
                                      (doc.data()['email'] ?? 'Guest')
                                          .toString(),
                                      style: const TextStyle(
                                        color: AppColors.muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                'Lv ${doc.data()['level'] ?? 1}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.purple,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
