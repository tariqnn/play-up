enum PlayUpInviteType { booking, match }

class PlayUpInvite {
  const PlayUpInvite({required this.type, required this.id});

  final PlayUpInviteType type;
  final String id;
}

PlayUpInvite? parsePlayUpInvite(Uri uri) {
  if (uri.scheme == 'playup') {
    if (!const {'booking', 'match'}.contains(uri.host) ||
        uri.pathSegments.length != 1) {
      return null;
    }
    return _invite(uri.host, uri.pathSegments.single);
  }

  if (uri.scheme != 'https' || uri.host != 'play-up.fit') return null;
  final parts = uri.pathSegments;
  if (parts.length != 3 || parts[0] != 'join') return null;
  return _invite(parts[1], parts[2]);
}

PlayUpInvite? _invite(String type, String id) {
  if (type == 'booking' && !RegExp(r'^[A-Za-z0-9_-]{24,64}$').hasMatch(id)) {
    return null;
  }
  if (type == 'match' && !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id)) {
    return null;
  }
  final inviteType = switch (type) {
    'booking' => PlayUpInviteType.booking,
    'match' => PlayUpInviteType.match,
    _ => null,
  };
  return inviteType == null ? null : PlayUpInvite(type: inviteType, id: id);
}
