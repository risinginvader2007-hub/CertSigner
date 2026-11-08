// Plain C entry point into zsign, so the Objective-C++ wrapper never has to
// include zsign's C++ headers (which use `using namespace std`).
#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/// nColor: 12 = error, 6 = warning, 10 = success, 0 = info.
typedef void (*zsign_log_fn)(void *context, int color, const char *message);

enum {
    ZSIGN_OK = 0,
    ZSIGN_ERR_ASSET = -1,   // certificate / key / profile couldn't be loaded
    ZSIGN_ERR_SIGN = -2     // signing the bundle failed
};

/// Signs the .app folder (or a folder that contains one) in place.
/// Nested frameworks, dylibs and app extensions are signed before the main binary.
/// `entitlements_path` may be NULL to use the entitlements from the profile.
/// Calls are serialised internally; safe to call from a background thread.
int zsign_sign_folder(const char *app_folder,
                      const char *p12_path,
                      const char *password,
                      const char *provision_path,
                      const char *entitlements_path,
                      zsign_log_fn log,
                      void *log_context);

#ifdef __cplusplus
}
#endif
