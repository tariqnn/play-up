import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'academy_profile_data.dart';

class CommunityModeDashboard extends StatelessWidget {
  const CommunityModeDashboard({super.key});

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    future: FirebaseFirestore.instance
        .collection('users')
        .doc(FirebaseAuth.instance.currentUser?.uid)
        .get(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (snapshot.hasError) {
        return const Scaffold(
          body: Center(
            child: Text(
              'Your community account could not be loaded. Sign in again or contact support.',
            ),
          ),
        );
      }
      final id = snapshot.data?.data()?['communityId']?.toString() ?? '';
      if (id.isEmpty) {
        return const Scaffold(
          body: Center(
            child: Text(
              'This account is not assigned to a community. Contact PlayUp support.',
            ),
          ),
        );
      }
      return CommunityOwnerStudio(communityId: id);
    },
  );
}

class CommunityOwnerStudio extends StatefulWidget {
  const CommunityOwnerStudio({super.key, required this.communityId});
  final String communityId;
  @override
  State<CommunityOwnerStudio> createState() => _CommunityOwnerStudioState();
}

class _CommunityOwnerStudioState extends State<CommunityOwnerStudio> {
  final _name = TextEditingController();
  final _sport = TextEditingController();
  final _description = TextEditingController();
  final _city = TextEditingController();
  final _phone = TextEditingController();
  final _website = TextEditingController();
  final _instagram = TextEditingController();
  String _imageUrl = '';
  List<String> _imageUrls = [];
  bool _hydrated = false;
  bool _saving = false;
  bool _uploading = false;

  @override
  void dispose() {
    _name.dispose();
    _sport.dispose();
    _description.dispose();
    _city.dispose();
    _phone.dispose();
    _website.dispose();
    _instagram.dispose();
    super.dispose();
  }

  void _hydrate(Map<String, dynamic> data) {
    if (_hydrated) return;
    _name.text = data['name']?.toString() ?? '';
    _sport.text = data['sport']?.toString() ?? '';
    _description.text = data['description']?.toString() ?? '';
    _city.text = data['city']?.toString() ?? '';
    _phone.text = data['contactPhone']?.toString() ?? '';
    _website.text = data['websiteUrl']?.toString() ?? '';
    _instagram.text = data['instagramUrl']?.toString() ?? '';
    _imageUrl = data['imageUrl']?.toString() ?? '';
    _imageUrls = academyImageList(data['imageUrls']);
    _hydrated = true;
  }

  Future<void> _choosePhoto() async {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (photo == null) return;
    final bytes = await photo.readAsBytes();
    if (bytes.lengthInBytes > 5 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Choose a photo smaller than 5 MB.')),
        );
      }
      return;
    }
    setState(() => _uploading = true);
    try {
      final extension = photo.name.split('.').last.toLowerCase();
      final mime = extension == 'png'
          ? 'image/png'
          : extension == 'webp'
          ? 'image/webp'
          : 'image/jpeg';
      final ref = FirebaseStorage.instance.ref(
        'community-images/${widget.communityId}/cover.$extension',
      );
      await ref.putData(bytes, SettableMetadata(contentType: mime));
      final url = await ref.getDownloadURL();
      if (mounted) {
        setState(() {
          _imageUrl = url;
          _uploading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _uploading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Photo upload failed: $error')));
      }
    }
  }

  Future<void> _addGalleryPhoto() async {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 84,
      maxWidth: 1600,
    );
    if (photo == null) return;
    final bytes = await photo.readAsBytes();
    if (bytes.lengthInBytes > 5 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Choose a photo smaller than 5 MB.')),
        );
      }
      return;
    }
    setState(() => _uploading = true);
    try {
      final extension = photo.name.split('.').last.toLowerCase();
      final mime = extension == 'png'
          ? 'image/png'
          : extension == 'webp'
          ? 'image/webp'
          : 'image/jpeg';
      final asset = 'gallery-${DateTime.now().microsecondsSinceEpoch}';
      final ref = FirebaseStorage.instance.ref(
        'community-images/${widget.communityId}/$asset.$extension',
      );
      await ref.putData(bytes, SettableMetadata(contentType: mime));
      final url = await ref.getDownloadURL();
      if (mounted) setState(() => _imageUrls = [..._imageUrls, url]);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Photo upload failed: $error')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('communities')
          .doc(widget.communityId)
          .set({
            'name': _name.text.trim(),
            'sport': _sport.text.trim(),
            'description': _description.text.trim(),
            'city': _city.text.trim(),
            'contactPhone': _phone.text.trim(),
            'websiteUrl': _website.text.trim(),
            'instagramUrl': _instagram.text.trim(),
            'imageUrl': _imageUrl,
            'imageUrls': _imageUrls,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Community page saved.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save: $error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _publishEvent([
    String? eventId,
    Map<String, dynamic>? initial,
  ]) async {
    final title = TextEditingController(text: initial?['title']?.toString());
    final description = TextEditingController(
      text: initial?['description']?.toString(),
    );
    final location = TextEditingController(
      text: initial?['location']?.toString(),
    );
    DateTime? date = DateTime.tryParse(initial?['date']?.toString() ?? '');
    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            eventId == null ? 'Publish a community event' : 'Edit event',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: const InputDecoration(labelText: 'Event name'),
                ),
                TextField(
                  controller: description,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Details'),
                ),
                TextField(
                  controller: location,
                  decoration: const InputDecoration(labelText: 'Meeting place'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      initialDate:
                          date ?? DateTime.now().add(const Duration(days: 1)),
                    );
                    if (picked != null) setDialogState(() => date = picked);
                  },
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(
                    date == null
                        ? 'Choose date'
                        : '${date!.day}/${date!.month}/${date!.year}',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: title.text.trim().isEmpty || date == null
                  ? null
                  : () => Navigator.pop(dialog, true),
              child: Text(eventId == null ? 'Publish' : 'Save event'),
            ),
          ],
        ),
      ),
    );
    try {
      if (shouldSave == true && date != null) {
        final payload = <String, dynamic>{
          'communityId': widget.communityId,
          'title': title.text.trim(),
          'description': description.text.trim(),
          'location': location.text.trim(),
          'date':
              '${date!.year.toString().padLeft(4, '0')}-${date!.month.toString().padLeft(2, '0')}-${date!.day.toString().padLeft(2, '0')}',
          'status': 'published',
          'updatedAt': FieldValue.serverTimestamp(),
        };
        if (eventId == null) {
          payload['createdAt'] = FieldValue.serverTimestamp();
          await FirebaseFirestore.instance.collection('events').add(payload);
        } else {
          await FirebaseFirestore.instance
              .collection('events')
              .doc(eventId)
              .update(payload);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                eventId == null ? 'Event published.' : 'Event updated.',
              ),
            ),
          );
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save event: $error')),
        );
      }
    } finally {
      title.dispose();
      description.dispose();
      location.dispose();
    }
  }

  Future<void> _deleteEvent(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Delete this event?'),
        content: const Text(
          'It will be removed from your public community page.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await FirebaseFirestore.instance.collection('events').doc(id).delete();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete event: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Community Studio')),
    body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('communities')
          .doc(widget.communityId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Your community page could not load.'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => setState(() {}),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                  ),
                ],
              ),
            ),
          );
        }
        if (snapshot.data?.exists != true) {
          return const Center(
            child: Text('This community page has not been created yet.'),
          );
        }
        _hydrate(snapshot.data!.data()!);
        final colors = Theme.of(context).colorScheme;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: SizedBox(
                height: 220,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _imageUrl.isEmpty
                        ? ColoredBox(
                            color: colors.primaryContainer,
                            child: Icon(
                              Icons.groups_rounded,
                              size: 56,
                              color: colors.primary,
                            ),
                          )
                        : Image.network(
                            _imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => ColoredBox(
                              color: colors.primaryContainer,
                              child: Icon(
                                Icons.groups_rounded,
                                size: 56,
                                color: colors.primary,
                              ),
                            ),
                          ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x00000000), Color(0xD9101B15)],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 18,
                      right: 16,
                      bottom: 16,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: colors.primary,
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: const Text(
                              'COMMUNITY PAGE',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.1,
                              ),
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            _name.text.isEmpty
                                ? 'Your sports community'
                                : _name.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Bring your group together on PlayUp',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      right: 12,
                      top: 12,
                      child: FilledButton.tonalIcon(
                        onPressed: _uploading ? null : _choosePhoto,
                        icon: _uploading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.photo_library_outlined),
                        label: Text(_uploading ? 'Uploading' : 'Change photo'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            _CommunityEditorSection(
              icon: Icons.groups_rounded,
              title: 'About your group',
              subtitle: 'Help players find and understand your community.',
              children: [
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Community name',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _sport,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Main sport'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _description,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _CommunityGalleryEditor(
              imageUrls: _imageUrls,
              uploading: _uploading,
              onAdd: _addGalleryPhoto,
              onRemove: (url) => setState(
                () => _imageUrls = _imageUrls
                    .where((item) => item != url)
                    .toList(),
              ),
            ),
            const SizedBox(height: 12),
            _CommunityEditorSection(
              icon: Icons.link_rounded,
              title: 'Location and links',
              subtitle: 'Give members a clear way to reach the group.',
              children: [
                TextField(
                  controller: _city,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'City / meeting area',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Public contact phone',
                    prefixIcon: Icon(Icons.call_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _website,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Website',
                    prefixIcon: Icon(Icons.language_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _instagram,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Instagram',
                    prefixIcon: Icon(Icons.camera_alt_outlined),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(_saving ? 'Saving...' : 'Save community page'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _publishEvent,
              icon: const Icon(Icons.event_available_outlined),
              label: const Text('Publish a group event'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
            ),
            const SizedBox(height: 18),
            _CommunityEditorSection(
              icon: Icons.event_note_rounded,
              title: 'Your events',
              subtitle:
                  'Edit or remove events shown on your public group page.',
              children: [
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('events')
                      .where('communityId', isEqualTo: widget.communityId)
                      .snapshots(),
                  builder: (context, events) {
                    if (events.hasError) {
                      return const Text(
                        'Events could not load. Try again later.',
                      );
                    }
                    if (events.connectionState == ConnectionState.waiting &&
                        !events.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final docs = [...?events.data?.docs]
                      ..sort(
                        (a, b) => (a.data()['date']?.toString() ?? '')
                            .compareTo(b.data()['date']?.toString() ?? ''),
                      );
                    if (docs.isEmpty) {
                      return const Text(
                        'No events yet. Publish one to share it with members.',
                      );
                    }
                    return Column(
                      children: [
                        for (final event in docs)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              event.data()['title']?.toString() ??
                                  'Community event',
                            ),
                            subtitle: Text(
                              [event.data()['date'], event.data()['location']]
                                  .where(
                                    (value) =>
                                        value != null &&
                                        value.toString().isNotEmpty,
                                  )
                                  .join(' · '),
                            ),
                            trailing: Wrap(
                              spacing: 2,
                              children: [
                                IconButton(
                                  tooltip: 'Edit event',
                                  onPressed: () =>
                                      _publishEvent(event.id, event.data()),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  tooltip: 'Delete event',
                                  onPressed: () => _deleteEvent(event.id),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ],
        );
      },
    ),
  );
}

class _CommunityEditorSection extends StatelessWidget {
  const _CommunityEditorSection({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: colors.primary, size: 21),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _CommunityGalleryEditor extends StatelessWidget {
  const _CommunityGalleryEditor({
    required this.imageUrls,
    required this.uploading,
    required this.onAdd,
    required this.onRemove,
  });

  final List<String> imageUrls;
  final bool uploading;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Community gallery',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      SizedBox(height: 3),
                      Text('Add photos of your activities and members.'),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'Add gallery photo',
                  onPressed: uploading ? null : onAdd,
                  icon: uploading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_photo_alternate_outlined),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (imageUrls.isEmpty)
              const Text(
                'No gallery photos yet. Add a few to make your group page feel alive.',
              )
            else
              SizedBox(
                height: 112,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: imageUrls.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 9),
                  itemBuilder: (context, index) => SizedBox(
                    width: 142,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.network(
                            imageUrls[index],
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => ColoredBox(
                              color: colors.surfaceContainerHighest,
                              child: const Icon(Icons.broken_image_outlined),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 4,
                          top: 4,
                          child: IconButton.filledTonal(
                            tooltip: 'Remove photo',
                            onPressed: () => onRemove(imageUrls[index]),
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
