// The state behind the profile picture, the Public Profile switch and the notification bell. The
// stores are fakes in memory, so these need neither Hive nor the network.

import 'package:atomic_notes/database/notification_models.dart';
import 'package:atomic_notes/database/notifications_source.dart';
import 'package:atomic_notes/profile/profile_source.dart';
import 'package:atomic_notes/profile/profile_store.dart' show Avatars;
import 'package:atomic_notes/state/notifications/notifications_cubit.dart';
import 'package:atomic_notes/state/profile/profile_cubit.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeProfile extends ChangeNotifier implements ProfileSource {
  String? chosen;
  bool isPublic = true;

  @override
  String get avatarAsset => chosen ?? Avatars.defaultAsset;

  @override
  bool get publicProfile => isPublic;

  @override
  Future<void> setAvatar(String? asset) async {
    if (asset == null || Avatars.isKnown(asset)) {
      chosen = asset;
      notifyListeners();
    }
  }

  @override
  Future<void> setPublicProfile(bool value) async {
    isPublic = value;
    notifyListeners();
  }

  void poke() => notifyListeners();
}

AppNotification _n(String id, {bool isRead = false}) => AppNotification(
      id: id,
      type: 'info',
      subject: 'Subject $id',
      description: 'Description $id',
      priority: 'normal',
      status: 'active',
      action: null,
      actionUrl: null,
      icon: null,
      createdAt: DateTime.utc(2026, 9, 21),
      expiresAt: null,
      isRead: isRead,
      dismissedAt: null,
      dismissible: true,
    );

class _FakeFeed extends ChangeNotifier implements NotificationsSource {
  _FakeFeed(this.items);

  @override
  List<AppNotification> items;

  @override
  bool loading = false;

  @override
  String? error;

  int refreshCalls = 0;

  @override
  Future<void> refresh() async {
    refreshCalls++;
    notifyListeners();
  }

  @override
  Future<void> markRead(String id) async {
    items = [for (final n in items) n.id == id ? _n(n.id, isRead: true) : n];
    notifyListeners();
  }

  @override
  Future<void> markAllRead() async {
    items = [for (final n in items) _n(n.id, isRead: true)];
    notifyListeners();
  }

  @override
  Future<void> dismiss(String id) async {
    items = [for (final n in items) if (n.id != id) n];
    notifyListeners();
  }

  void poke() => notifyListeners();
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  group('profile', () {
    test('starts on the default photo with the switch on', () {
      final cubit = ProfileCubit(store: _FakeProfile());
      addTearDown(cubit.close);
      expect(cubit.state.avatarAsset, Avatars.defaultAsset);
      expect(cubit.state.hasCustomAvatar, isFalse);
      expect(cubit.state.publicProfile, isTrue);
    });

    test('a chosen avatar reaches the state, and the default photo comes back', () async {
      final cubit = ProfileCubit(store: _FakeProfile());
      addTearDown(cubit.close);

      await cubit.setAvatar(Avatars.all[4]);
      await _settle();
      expect(cubit.state.avatarAsset, Avatars.all[4]);
      expect(cubit.state.hasCustomAvatar, isTrue);

      await cubit.setAvatar(null);
      await _settle();
      expect(cubit.state.avatarAsset, Avatars.defaultAsset);
      expect(cubit.state.hasCustomAvatar, isFalse);
    });

    test('something that is not a bundled avatar changes nothing', () async {
      final cubit = ProfileCubit(store: _FakeProfile());
      addTearDown(cubit.close);
      final seen = <ProfileState>[];
      final sub = cubit.stream.listen(seen.add);
      addTearDown(sub.cancel);

      await cubit.setAvatar('assets/../secret.png');
      await _settle();

      expect(seen, isEmpty);
    });

    test('the public profile switch is remembered', () async {
      final cubit = ProfileCubit(store: _FakeProfile());
      addTearDown(cubit.close);

      await cubit.setPublicProfile(false);
      await _settle();

      expect(cubit.state.publicProfile, isFalse);
    });

    test('a store that says nothing new emits nothing', () async {
      final store = _FakeProfile();
      final cubit = ProfileCubit(store: store);
      addTearDown(cubit.close);
      final seen = <ProfileState>[];
      final sub = cubit.stream.listen(seen.add);
      addTearDown(sub.cancel);

      store.poke();
      await _settle();

      expect(seen, isEmpty);
    });

    test('refresh picks up a choice that changed without a word, like a different account', () async {
      final store = _FakeProfile();
      final cubit = ProfileCubit(store: store);
      addTearDown(cubit.close);
      expect(cubit.state.avatarAsset, Avatars.defaultAsset);

      store.chosen = Avatars.all[9]; // the next account's picture, no notification
      cubit.refresh();

      expect(cubit.state.avatarAsset, Avatars.all[9]);
    });

    test('a closed cubit stops listening', () async {
      final store = _FakeProfile();
      final cubit = ProfileCubit(store: store);
      await cubit.close();
      store.poke();
      cubit.refresh();
      expect(cubit.isClosed, isTrue);
    });
  });

  group('notifications', () {
    test('counts the unread ones for the bell', () {
      final cubit = NotificationsCubit(
          source: _FakeFeed([_n('a'), _n('b', isRead: true), _n('c')]));
      addTearDown(cubit.close);
      expect(cubit.state.items, hasLength(3));
      expect(cubit.state.unreadCount, 2);
    });

    test('an empty feed has an empty bell', () {
      final cubit = NotificationsCubit(source: _FakeFeed(const []));
      addTearDown(cubit.close);
      expect(cubit.state.unreadCount, 0);
    });

    test('reading one lowers the count', () async {
      final cubit = NotificationsCubit(source: _FakeFeed([_n('a'), _n('b')]));
      addTearDown(cubit.close);

      await cubit.markRead('a');
      await _settle();

      expect(cubit.state.unreadCount, 1);
    });

    test('mark all read clears the badge', () async {
      final cubit = NotificationsCubit(source: _FakeFeed([_n('a'), _n('b')]));
      addTearDown(cubit.close);

      await cubit.markAllRead();
      await _settle();

      expect(cubit.state.unreadCount, 0);
      expect(cubit.state.items, hasLength(2));
    });

    test('dismissing removes it from the feed', () async {
      final cubit = NotificationsCubit(source: _FakeFeed([_n('a'), _n('b')]));
      addTearDown(cubit.close);

      await cubit.dismiss('a');
      await _settle();

      expect(cubit.state.items.map((n) => n.id), ['b']);
    });

    test('shows a load and its failure', () async {
      final feed = _FakeFeed(const []);
      final cubit = NotificationsCubit(source: feed);
      addTearDown(cubit.close);

      feed
        ..loading = true
        ..poke();
      await _settle();
      expect(cubit.state.loading, isTrue);

      feed
        ..loading = false
        ..error = 'Could not load'
        ..poke();
      await _settle();
      expect(cubit.state.loading, isFalse);
      expect(cubit.state.error, 'Could not load');
    });

    test('a feed that says nothing new emits nothing, even with fresh copies of the same items', () async {
      final feed = _FakeFeed([_n('a'), _n('b')]);
      final cubit = NotificationsCubit(source: feed);
      addTearDown(cubit.close);
      final seen = <NotificationsState>[];
      final sub = cubit.stream.listen(seen.add);
      addTearDown(sub.cancel);

      feed.items = [_n('a'), _n('b')];
      feed.poke();
      await _settle();

      expect(seen, isEmpty);
    });

    test('refresh asks the feed to load again', () async {
      final feed = _FakeFeed(const []);
      final cubit = NotificationsCubit(source: feed);
      addTearDown(cubit.close);

      await cubit.refresh();

      expect(feed.refreshCalls, 1);
    });
  });
}
