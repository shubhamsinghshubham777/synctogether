#ifndef RUNNER_SYSTEM_FONTS_H_
#define RUNNER_SYSTEM_FONTS_H_

#include <flutter/binary_messenger.h>

// Installed font families for the subtitle font picker, from DirectWrite's
// system collection. Face names are DirectWrite full names, which libass's
// DirectWrite provider matches directly.
void RegisterSystemFontsChannel(flutter::BinaryMessenger* messenger);

#endif  // RUNNER_SYSTEM_FONTS_H_
