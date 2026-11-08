#include "zsign_api.h"
#include "common.h"
#include "openssl.h"
#include "bundle.h"
#include <mutex>

static std::mutex g_zsignMutex;

int zsign_sign_folder(const char *app_folder,
                      const char *p12_path,
                      const char *password,
                      const char *provision_path,
                      const char *entitlements_path,
                      zsign_log_fn log,
                      void *log_context)
{
    std::lock_guard<std::mutex> lock(g_zsignMutex);

    ZLog::SetLogLever(ZLog::E_INFO);
    ZLog::SetLogCallback(log, log_context);

    int result = ZSIGN_ERR_ASSET;
    {
        ZSignAsset asset;
        const string strEntitlements = entitlements_path ? entitlements_path : "";
        const string strPassword = password ? password : "";
        // cert file empty: the certificate comes from the p12 (or is matched from the profile).
        if (asset.Init("", p12_path, provision_path, strEntitlements, strPassword, false, true, false)) {
            ZBundle bundle;
            vector<string> injectDylibs;
            vector<string> removeDylibs;
            // Name / bundle ID / version are patched in Swift beforehand, so pass empty strings.
            // bForce = true (re-sign everything), bEnableCache = false (cwd is read-only on iOS).
            const bool ok = bundle.SignFolder(&asset, app_folder, "", "", "", injectDylibs, removeDylibs,
                                              true, false, false, false);
            result = ok ? ZSIGN_OK : ZSIGN_ERR_SIGN;
        }
    }

    ZLog::SetLogCallback(NULL, NULL);
    return result;
}
