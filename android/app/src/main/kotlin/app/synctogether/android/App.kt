package app.synctogether.android

import android.app.Application

/**
 * Brings Firebase up before anything else runs, from the options Dart handed
 * over the first time it configured push. A message can start this process with
 * no Flutter engine at all, and Firebase has to exist by then or the message is
 * dropped. There is no google-services file in this app on purpose: the project
 * is the operator's, supplied at build time, never ours.
 */
class App : Application() {
  override fun onCreate() {
    super.onCreate()
    Push.initFirebaseFromStoredOptions(this)
    Push.ensureChannels(this)
  }
}
