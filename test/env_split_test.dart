import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/env.dart';

void main() {
  tearDown(Env.resetOverridesForTesting);

  test('flutter test runs in debug, which is what this file is about', () {
    expect(kDebugMode, isTrue);
  });

  test('a debug build prefers the local stack when one is configured', () {
    Env.overrideSupabaseUrl = 'https://prod.supabase.co';
    Env.overrideSupabasePublishableKey = 'sb_publishable_prod';
    Env.overrideSupabaseUrlLocal = 'http://127.0.0.1:54321';
    Env.overrideSupabasePublishableKeyLocal = 'sb_publishable_local';

    expect(Env.supabaseUrl, 'http://127.0.0.1:54321');
    expect(Env.supabasePublishableKey, 'sb_publishable_local');
    expect(Env.usingLocalStack, isTrue);
  });

  test('a debug build with no local stack falls back to production', () {
    Env.overrideSupabaseUrl = 'https://prod.supabase.co';
    Env.overrideSupabasePublishableKey = 'sb_publishable_prod';

    expect(Env.supabaseUrl, 'https://prod.supabase.co');
    expect(Env.supabasePublishableKey, 'sb_publishable_prod');
    expect(Env.usingLocalStack, isFalse);
  });

  test('an empty local value is treated as absent, not as an empty url', () {
    Env.overrideSupabaseUrl = 'https://prod.supabase.co';
    Env.overrideSupabasePublishableKey = 'sb_publishable_prod';
    Env.overrideSupabaseUrlLocal = '';
    Env.overrideSupabasePublishableKeyLocal = '';

    expect(Env.supabaseUrl, 'https://prod.supabase.co');
    expect(Env.usingLocalStack, isFalse);
  });

  test('the local key is only honoured alongside a local url', () {
    Env.overrideSupabaseUrl = 'https://prod.supabase.co';
    Env.overrideSupabasePublishableKey = 'sb_publishable_prod';
    Env.overrideSupabaseUrlLocal = '';
    Env.overrideSupabasePublishableKeyLocal = 'sb_publishable_local';

    expect(Env.supabaseUrl, 'https://prod.supabase.co');
    expect(
      Env.usingLocalStack,
      isFalse,
      reason: 'a key without a url must not read as a local session',
    );
  });

  test('a debug build with no configuration defaults to local dev stack', () {
    expect(Env.supabaseUrl, Env.defaultLocalSupabaseUrl);
    expect(Env.supabasePublishableKey, Env.defaultLocalSupabasePublishableKey);
    expect(Env.usingLocalStack, isTrue);
    expect(Env.turnstileSiteKey, Env.defaultLocalTurnstileSiteKey);
  });

  test('a release build with no defines returns empty Supabase URL and key', () {
    Env.overrideReleaseMode = true;
    expect(Env.supabaseUrl, isEmpty);
    expect(Env.supabasePublishableKey, isEmpty);
    expect(Env.usingLocalStack, isFalse);
  });

  test('a release build with production defines returns production values', () {
    Env.overrideReleaseMode = true;
    Env.overrideSupabaseUrl = 'https://custom.supabase.co';
    Env.overrideSupabasePublishableKey = 'sb_publishable_custom';

    expect(Env.supabaseUrl, 'https://custom.supabase.co');
    expect(Env.supabasePublishableKey, 'sb_publishable_custom');
    expect(Env.usingLocalStack, isFalse);
  });

  group('web portal origin', () {
    test('a release build with no SITE_URL has no web portal at all', () {
      Env.overrideReleaseMode = true;
      expect(Env.siteUrl, isNull);
      expect(Env.siteHost, isNull);
      expect(Env.sitePage('terms'), isNull);
      expect(Env.supportEmail, isNull);
    });

    test('a debug build on the local stack links to the local website', () {
      Env.overrideSiteUrl = 'https://watch.example.com';
      expect(Env.siteUrl, 'http://localhost:3000');
      expect(Env.sitePage('terms').toString(), 'http://localhost:3000/terms');
    });

    test('SITE_URL wins and loses its trailing slash', () {
      Env.overrideReleaseMode = true;
      Env.overrideSiteUrl = 'https://watch.example.com/';
      Env.overrideSupportEmail = 'help@example.com';
      expect(Env.siteUrl, 'https://watch.example.com');
      expect(Env.siteHost, 'watch.example.com');
      expect(
        Env.sitePage('auth/desktop-callback').toString(),
        'https://watch.example.com/auth/desktop-callback',
      );
      expect(Env.supportEmail, 'help@example.com');
    });
  });
}
