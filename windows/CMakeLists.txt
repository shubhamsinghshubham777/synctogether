# Project-level configuration.
cmake_minimum_required(VERSION 3.14)

# When building on a Windows ARM64 host for x64 (the default Flutter Windows
# target), CMake inherits CMAKE_SYSTEM_PROCESSOR from the host environment
# (ARM64) unless explicitly set before project(). This causes dependencies such
# as Sentry Native's Crashpad to select ARM64 assembly with MARMASM into an x64
# project, breaking MSBuild.
if(CMAKE_GENERATOR_PLATFORM STREQUAL "x64")
  set(CMAKE_SYSTEM_PROCESSOR "x86_64" CACHE STRING "Target system processor" FORCE)
  set(CMAKE_SYSTEM_PROCESSOR "x86_64")
endif()

# Sentry Native defaults to Crashpad, which invokes Google Crashpad. On Windows
# ARM64 hosts compiling for x64, Crashpad attempts to assemble ARM64 assembly
# with MARMASM into an x64 project, failing MSBuild with MSB8076. Breakpad
# compiles cleanly across all architectures.
if(NOT DEFINED ENV{SENTRY_NATIVE_BACKEND} OR "$ENV{SENTRY_NATIVE_BACKEND}" STREQUAL "")
  if("$ENV{PROCESSOR_ARCHITECTURE}" STREQUAL "ARM64" OR CMAKE_SYSTEM_PROCESSOR MATCHES "ARM64|arm64")
    set(ENV{SENTRY_NATIVE_BACKEND} "breakpad")
  endif()
endif()

# JNI package (pulled by sentry_flutter) requires a JDK during CMake FindJNI.
# If JAVA_HOME is not set in the current process environment, scan standard JDK locations.
if(NOT DEFINED ENV{JAVA_HOME} OR "$ENV{JAVA_HOME}" STREQUAL "")
  file(GLOB _JDK_CANDIDATES
    "C:/tools/jdk"
    "C:/Program Files/Microsoft/jdk-*"
    "C:/Program Files/Eclipse Adoptium/jdk-*"
    "C:/Program Files/Java/jdk-*"
    "C:/Program Files/Android/Android Studio/jbr"
    "$ENV{LOCALAPPDATA}/Programs/Common/Oracle/Java/javapath"
  )
  foreach(_JDK_PATH IN LISTS _JDK_CANDIDATES)
    if(EXISTS "${_JDK_PATH}/include/jni.h")
      set(ENV{JAVA_HOME} "${_JDK_PATH}")
      break()
    endif()
  endforeach()
endif()

project(synctogether LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "synctogether")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# flutter_inappwebview_windows includes <winrt/base.h>, and C++/WinRT falls back
# to <experimental/coroutine> when built as C++17 (which the plugin pins). As of
# MSVC 14.51 that header is a hard error (STL1011) rather than a warning, so the
# plugin no longer compiles. Take the escape hatch the compiler itself suggests;
# it must be set here, before the plugin subdirectories are added below, since
# the plugin's own CMakeLists lives in the read-only pub cache.
add_compile_definitions(_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)

# Compile each project's translation units in parallel. Flutter runs
# `cmake --build` without `--parallel`, and the Visual Studio generator neither
# passes MSBuild `/m` nor sets MultiProcessorCompilation, so out of the box every
# .cpp in the build compiles one at a time on one core. /MP lets cl.exe fan its
# batched source list out across the machine's logical processors. It has to be
# set here for the same reason the definition above does: the expensive targets
# are plugins whose CMakeLists live in the read-only pub cache.
add_compile_options(/MP)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")


# flutter_webrtc extracts libwebrtc.zip inside its own directory. On Windows,
# CMake rejects extracting through the .plugin_symlinks junction. If the zip was
# downloaded but libwebrtc/ has not been extracted yet, extract it here to the
# real path before generated_plugins.cmake runs.
set(WEBRTC_PLUGIN_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter/ephemeral/.plugin_symlinks/flutter_webrtc")
if(EXISTS "${WEBRTC_PLUGIN_DIR}/third_party/downloads/libwebrtc.zip" AND NOT EXISTS "${WEBRTC_PLUGIN_DIR}/third_party/libwebrtc")
  message(STATUS "Pre-extracting libwebrtc.zip to avoid symlink extraction error...")
  execute_process(
    COMMAND tar -xf "${WEBRTC_PLUGIN_DIR}/third_party/downloads/libwebrtc.zip" -C "${WEBRTC_PLUGIN_DIR}/third_party"
  )
endif()

# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)
