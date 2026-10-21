import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

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
      if (snapshot.connectionState == ConnectionState.waiting)
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      if (snapshot.hasError)
        return const Scaffold(
          body: Center(
            child: Text(
              'Your community account could not be loaded. Sign in again or contact support.',
            ),
          ),
        );
      final id = snapshot.data?.data()?['communityId']?.toString() ?? '';
      if (id.isEmpty)
        return const Scaffold(
          body: Center(
            child: Text(
              'This account is not assigned to a community. Contact PlayUp support.',
            ),
          ),
        );
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
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Choose a photo smaller than 5 MB.')),
        );
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
      if (mounted)
        setState(() {
          _imageUrl = url;
          _uploading = false;
        });
    } catch (error) {
      if (mounted) {
        setState(() => _uploading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Photo upload failed: $error')));
      }
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
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Community page saved.')));
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _publishEvent() async {
    final title = TextEditingController();
    final description = TextEditingController();
    final location = TextEditingController();
    DateTime? date;
    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Publish a community event'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
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
                      initialDate: DateTime.now().add(const Duration(days: 1)),
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
              child: const Text('Publish'),
            ),
          ],
        ),
      ),
    );
    if (shouldSave == true && date != null) {
      await FirebaseFirestore.instance.collection('events').add({
        'communityId': widget.communityId,
        'title': title.text.trim(),
        'description': description.text.trim(),
        'location': location.text.trim(),
        'date':
            '${date!.year.toString().padLeft(4, '0')}-${date!.month.toString().padLeft(2, '0')}-${date!.day.toString().padLeft(2, '0')}',
        'status': 'published',
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Event published.')));
    }
    title.dispose();
    description.dispose();
    location.dispose();
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
            !snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError)
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
        if (snapshot.data?.exists != true)
          return const Center(
            child: Text('This community page has not been created yet.'),
          );
        _hydrate(snapshot.data!.data()!);
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Text(
              'Manage your group page, photos and events.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                height: 180,
                child: _imageUrl.isEmpty
                    ? ColoredBox(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.groups_rounded, size: 52),
                      )
                    : Image.network(
                        _imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const ColoredBox(
                          color: Color(0xFFE8F2EA),
                          child: Icon(Icons.groups_rounded, size: 48),
                        ),
                      ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _uploading ? null : _choosePhoto,
                icon: _uploading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.photo_library_outlined),
                label: Text(_uploading ? 'Uploading…' : 'Change cover photo'),
              ),
            ),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Community name'),
            ),
            TextField(
              controller: _sport,
              decoration: const InputDecoration(labelText: 'Sport'),
            ),
            TextField(
              controller: _description,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'About the group'),
            ),
            TextField(
              controller: _city,
              decoration: const InputDecoration(
                labelText: 'City / meeting area',
              ),
            ),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Public contact phone',
              ),
            ),
            TextField(
              controller: _website,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Website'),
            ),
            TextField(
              controller: _instagram,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Instagram'),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(_saving ? 'Saving…' : 'Save community page'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _publishEvent,
              icon: const Icon(Icons.event_available_outlined),
              label: const Text('Publish an event'),
            ),
          ],
        );
      },
    ),
  );
}
