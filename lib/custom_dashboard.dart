import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class DashboardWidgetSpec {
  const DashboardWidgetSpec(this.id, this.title, this.icon, this.value);
  final String id;
  final String title;
  final IconData icon;
  final String value;
}

const platformWidgets = <DashboardWidgetSpec>[
  DashboardWidgetSpec(
    'totalBookings',
    'Total bookings',
    Icons.calendar_month,
    '1,248',
  ),
  DashboardWidgetSpec('todayBookings', "Today's bookings", Icons.today, '42'),
  DashboardWidgetSpec(
    'activeUsers',
    'Active users',
    Icons.people_alt_outlined,
    '3,910',
  ),
  DashboardWidgetSpec(
    'academies',
    'Active academies',
    Icons.business_outlined,
    '18',
  ),
  DashboardWidgetSpec('courts', 'Total courts', Icons.sports_tennis, '64'),
  DashboardWidgetSpec(
    'revenue',
    'Booking revenue',
    Icons.payments_outlined,
    'JOD 48.2K',
  ),
  DashboardWidgetSpec(
    'pending',
    'Pending approvals',
    Icons.pending_actions,
    '3',
  ),
  DashboardWidgetSpec('matches', 'Open matches', Icons.groups_outlined, '27'),
];

const academyWidgets = <DashboardWidgetSpec>[
  DashboardWidgetSpec('todayBookings', "Today's bookings", Icons.today, '18'),
  DashboardWidgetSpec(
    'upcoming',
    'Upcoming bookings',
    Icons.event_available,
    '31',
  ),
  DashboardWidgetSpec(
    'availableCourts',
    'Available courts',
    Icons.sports_tennis,
    '5',
  ),
  DashboardWidgetSpec(
    'maintenance',
    'Under maintenance',
    Icons.build_outlined,
    '1',
  ),
  DashboardWidgetSpec(
    'revenue',
    'Revenue',
    Icons.payments_outlined,
    'JOD 3,780',
  ),
  DashboardWidgetSpec(
    'utilization',
    'Court utilization',
    Icons.donut_large,
    '76%',
  ),
  DashboardWidgetSpec('cancellations', 'Cancellations', Icons.event_busy, '4'),
  DashboardWidgetSpec('reviews', 'Customer reviews', Icons.star_outline, '4.8'),
];

class CustomDashboard extends StatefulWidget {
  const CustomDashboard({
    super.key,
    required this.scope,
    required this.available,
  });
  final String scope;
  final List<DashboardWidgetSpec> available;

  @override
  State<CustomDashboard> createState() => _CustomDashboardState();
}

class _CustomDashboardState extends State<CustomDashboard> {
  late List<String> _visible;
  final Set<String> _wide = {};
  bool _loading = true;
  bool _saving = false;

  DocumentReference<Map<String, dynamic>>? get _ref {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null
        ? null
        : FirebaseFirestore.instance.collection('dashboardLayouts').doc(uid);
  }

  @override
  void initState() {
    super.initState();
    _visible = widget.available.take(6).map((e) => e.id).toList();
    _load();
  }

  Future<void> _load() async {
    try {
      final snap = await _ref?.get();
      final layout = snap?.data()?[widget.scope] as Map<String, dynamic>?;
      final allowed = widget.available.map((e) => e.id).toSet();
      final stored = (layout?['visible'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .where(allowed.contains)
          .toList();
      if (stored.isNotEmpty) _visible = stored;
      _wide.addAll(
        (layout?['wide'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .where(allowed.contains),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final ref = _ref;
    if (ref == null) return;
    setState(() => _saving = true);
    try {
      await ref.set({
        widget.scope: {'visible': _visible, 'wide': _wide.toList()},
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dashboard layout saved.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final byId = {for (final item in widget.available) item.id: item};
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customize dashboard'),
        actions: [
          IconButton(
            tooltip: 'Add widget',
            onPressed: _addWidget,
            icon: const Icon(Icons.add_box_outlined),
          ),
          IconButton(
            tooltip: 'Restore default layout',
            onPressed: _reset,
            icon: const Icon(Icons.restart_alt),
          ),
          IconButton(
            tooltip: 'Save layout',
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
          ),
        ],
      ),
      body: ReorderableListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _visible.length,
        onReorderItem: (oldIndex, newIndex) => setState(() {
          _visible.insert(newIndex, _visible.removeAt(oldIndex));
        }),
        itemBuilder: (context, index) {
          final item = byId[_visible[index]]!;
          return Card(
            key: ValueKey(item.id),
            margin: const EdgeInsets.only(bottom: 12),
            child: SizedBox(
              height: _wide.contains(item.id) ? 148 : 104,
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: CircleAvatar(child: Icon(item.icon)),
                title: Text(
                  item.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  item.value,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                trailing: PopupMenuButton<String>(
                  tooltip: 'Widget options',
                  onSelected: (value) => setState(() {
                    if (value == 'hide') _visible.remove(item.id);
                    if (value == 'size') {
                      _wide.contains(item.id)
                          ? _wide.remove(item.id)
                          : _wide.add(item.id);
                    }
                  }),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'size',
                      child: Text(
                        _wide.contains(item.id)
                            ? 'Use compact size'
                            : 'Use expanded size',
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'hide',
                      child: Text('Hide widget'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _addWidget() async {
    final hidden = widget.available
        .where((e) => !_visible.contains(e.id))
        .toList();
    if (hidden.isEmpty) return;
    final id = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Add widget'),
        children: [
          for (final item in hidden)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, item.id),
              child: Text(item.title),
            ),
        ],
      ),
    );
    if (id != null) setState(() => _visible.add(id));
  }

  void _reset() => setState(() {
    _visible = widget.available.take(6).map((e) => e.id).toList();
    _wide.clear();
  });
}
