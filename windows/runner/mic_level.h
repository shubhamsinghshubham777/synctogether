#ifndef RUNNER_MIC_LEVEL_H_
#define RUNNER_MIC_LEVEL_H_

#include <flutter/binary_messenger.h>

// Live input level for the "Test your mic" meter, read straight from WASAPI.
// WebRTC's capture only runs once a track rides a peer connection, so a bare
// local track in the settings dialog never delivers a frame on Windows.
void RegisterMicLevelChannel(flutter::BinaryMessenger* messenger);

#endif  // RUNNER_MIC_LEVEL_H_
