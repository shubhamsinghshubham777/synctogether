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
}
