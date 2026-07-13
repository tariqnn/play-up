import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'main.dart';

class TournamentsScreen extends StatelessWidget {
  const TournamentsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: AppScrollPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageTopBar(
            title: 'Tournaments',
            onBack: () => Navigator.pop(context),
          ),
          const SizedBox(height: 16),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('tournaments')
                .where('status', isEqualTo: 'registrationOpen')
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.data!.docs.isEmpty) {
                return EmptyState(
                  icon: CupertinoIcons.rosette,
                  title: 'No open tournaments',
                  message:
                      'Academies near you have not opened registration yet.',
                  action: 'Go back',
                  onTap: () => Navigator.pop(context),
                );
              }
              return Column(
                children: snapshot.data!.docs.map((doc) {
                  final d = doc.data();
                  final start = (d['startsAt'] as Timestamp?)?.toDate();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: CardBox(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if ((d['imageUrl'] ?? '').toString().isNotEmpty)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Image.network(
                                d['imageUrl'],
                                height: 140,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            ),
                          const SizedBox(height: 10),
                          Text(
                            (d['name'] ?? 'Tournament').toString(),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            '${d['sport']} • ${_formatName(d['format'])} • ${d['teamSize']} per team',
                            style: const TextStyle(color: AppColors.muted),
                          ),
                          if (start != null)
                            Text(
                              DateFormat(
                                'EEE, d MMM • h:mm a',
                              ).format(start.toLocal()),
                            ),
                          const SizedBox(height: 12),
                          PrimaryButton(
                            label: 'Register • Cash pending',
                            onPressed: () => _register(context, doc.id),
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
    ),
  );

  static String _formatName(dynamic value) => value.toString().replaceAllMapped(
    RegExp(r'([A-Z])'),
    (m) => ' ${m[1]!.toLowerCase()}',
  );

  static Future<void> _register(BuildContext context, String id) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      await showAdaptiveMessage(
        context,
        title: 'Account required',
        message: 'Sign in to register for tournaments.',
      );
      return;
    }
    try {
      await FirebaseFunctions.instanceFor(
        region: 'me-central1',
      ).httpsCallable('registerTournament').call({'tournamentId': id});
      if (context.mounted) {
        await showAdaptiveMessage(
          context,
          title: 'Registration confirmed',
          message:
              'Your place is reserved. Cash payment is pending at the academy.',
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (context.mounted) {
        await showAdaptiveMessage(
          context,
          title: 'Unable to register',
          message: e.message ?? 'Please try again.',
        );
      }
    }
  }
}

class CreateTournamentScreen extends StatefulWidget {
  const CreateTournamentScreen({super.key});
  @override
  State<CreateTournamentScreen> createState() => _CreateTournamentScreenState();
}

class _CreateTournamentScreenState extends State<CreateTournamentScreen> {
  final name = TextEditingController();
  final rules = TextEditingController();
  String sport = 'Football', format = 'singleElimination';
  int teamSize = 5, maxEntries = 16;
  bool busy = false;
  @override
  void dispose() {
    name.dispose();
    rules.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: AppScrollPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageTopBar(
            title: 'Create tournament',
            onBack: () => Navigator.pop(context),
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Tournament name',
            controller: name,
            icon: CupertinoIcons.rosette,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField(
            initialValue: sport,
            decoration: const InputDecoration(labelText: 'Sport'),
            items: [
              'Football',
              'Basketball',
              'Padel',
              'Tennis',
              'Volleyball',
              'Cricket',
              'Handball',
            ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: (v) => setState(() => sport = v!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField(
            initialValue: format,
            decoration: const InputDecoration(labelText: 'Competition format'),
            items:
                const {
                      'singleElimination': 'Single elimination',
                      'doubleElimination': 'Double elimination',
                      'roundRobin': 'Round robin',
                      'groupKnockout': 'Groups + knockout',
                    }.entries
                    .map(
                      (e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                    )
                    .toList(),
            onChanged: (v) => setState(() => format = v!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField(
            initialValue: teamSize,
            decoration: const InputDecoration(labelText: 'Players per entry'),
            items: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
                .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
                .toList(),
            onChanged: (v) => setState(() => teamSize = v!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField(
            initialValue: maxEntries,
            decoration: const InputDecoration(labelText: 'Maximum entries'),
            items: [4, 8, 16, 32, 64]
                .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
                .toList(),
            onChanged: (v) => setState(() => maxEntries = v!),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: rules,
            minLines: 4,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Rules and eligibility',
              prefixIcon: Icon(CupertinoIcons.doc_text),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 20),
          PrimaryButton(
            label: busy ? 'Creating…' : 'Publish tournament',
            onPressed: busy ? null : _create,
          ),
        ],
      ),
    ),
  );
  Future<void> _create() async {
    setState(() => busy = true);
    try {
      final now = DateTime.now();
      await FirebaseFunctions.instanceFor(
        region: 'me-central1',
      ).httpsCallable('createTournament').call({
        'name': name.text,
        'sport': sport,
        'format': format,
        'teamSize': teamSize,
        'maxEntries': maxEntries,
        'registrationEndsAt': now
            .add(const Duration(days: 7))
            .toUtc()
            .toIso8601String(),
        'startsAt': now.add(const Duration(days: 8)).toUtc().toIso8601String(),
        'rules': rules.text,
      });
      if (mounted) Navigator.pop(context);
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        await showAdaptiveMessage(
          context,
          title: 'Unable to publish',
          message: e.message ?? 'Please check every field.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}
