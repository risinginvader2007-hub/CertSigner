// WebAssembly entry points for the "Get CertSigner" web installer.
// Same vendored zsign the app uses (Vendor/zsign), driven on Emscripten's in-memory filesystem.
// Nothing here touches the network: files are written to MEMFS by the page's Web Worker.
#include <emscripten.h>
#include <string>
#include <vector>
#include <time.h>
#include <openssl/pkcs12.h>
#include <openssl/x509.h>
#include <openssl/err.h>
#include <openssl/evp.h>
#include <openssl/provider.h>
#include "common.h"
#include "openssl.h"
#include "bundle.h"

EM_JS(void, zsign_js_log, (int color, const char *message), {
    if (Module["onZsignLog"]) Module["onZsignLog"](color, UTF8ToString(message));
});

static void log_callback(void *, int color, const char *message)
{
    zsign_js_log(color, message);
}

static std::string json_escape(const std::string &text)
{
    std::string out;
    for (unsigned char c : text) {
        if (c == '"' || c == '\\') { out += '\\'; out += (char)c; }
        else if (c < 0x20) { char buf[8]; snprintf(buf, sizeof(buf), "\\u%04x", c); out += buf; }
        else out += (char)c;
    }
    return out;
}

static std::string hex(const unsigned char *bytes, unsigned int length)
{
    static const char *digits = "0123456789abcdef";
    std::string out;
    for (unsigned int i = 0; i < length; i++) { out += digits[bytes[i] >> 4]; out += digits[bytes[i] & 15]; }
    return out;
}

extern "C" {

/// Signs the .app folder in place with the p12 + profile. `bundle_id` may be "" to keep the
/// app's bundle ID. Uses the profile's entitlements. Returns 0 on success, -1 when the
/// certificate / key / profile can't be loaded, -2 when signing fails.
EMSCRIPTEN_KEEPALIVE
int zsign_web_sign(const char *app_folder, const char *p12_path, const char *password,
                   const char *provision_path, const char *bundle_id)
{
    ZLog::SetLogLever(ZLog::E_INFO);
    ZLog::SetLogCallback(log_callback, NULL);
    int result = -1;
    {
        ZSignAsset asset;
        const string strPassword = password ? password : "";
        if (asset.Init("", p12_path, provision_path, "", strPassword, false, true, false)) {
            ZBundle bundle;
            vector<string> injectDylibs;
            vector<string> removeDylibs;
            const string strBundleId = bundle_id ? bundle_id : "";
            const bool ok = bundle.SignFolder(&asset, app_folder, strBundleId, "", "", injectDylibs, removeDylibs,
                                              true, false, false, false);
            result = ok ? 0 : -2;
        }
    }
    ZLog::SetLogCallback(NULL, NULL);
    return result;
}

/// Opens the p12 and describes its signing certificate as JSON:
/// {"ok":true,"name":"…","notAfter":<unix seconds>,"sha1":"…"} or {"ok":false,"error":"password"|"format"|"empty"}.
EMSCRIPTEN_KEEPALIVE
const char *zsign_web_inspect(const char *p12_path, const char *password)
{
    static std::string output;
    static bool providers = false;
    if (!providers) {
        // Older exports use RC2 / 3DES, which live in the legacy provider.
        OSSL_PROVIDER_load(NULL, "legacy");
        OSSL_PROVIDER_load(NULL, "default");
        providers = true;
    }
    output = "{\"ok\":false,\"error\":\"format\"}";
    BIO *bio = BIO_new_file(p12_path, "rb");
    if (!bio) return output.c_str();
    PKCS12 *p12 = d2i_PKCS12_bio(bio, NULL);
    BIO_free(bio);
    if (!p12) return output.c_str();

    const char *pass = password ? password : "";
    if (!PKCS12_verify_mac(p12, pass, -1) && !(pass[0] == 0 && PKCS12_verify_mac(p12, NULL, 0))) {
        PKCS12_free(p12);
        output = "{\"ok\":false,\"error\":\"password\"}";
        return output.c_str();
    }
    EVP_PKEY *key = NULL;
    X509 *cert = NULL;
    STACK_OF(X509) *chain = NULL;
    const int parsed = PKCS12_parse(p12, pass, &key, &cert, &chain);
    PKCS12_free(p12);
    if (!parsed || !cert || !key) {
        if (key) EVP_PKEY_free(key);
        if (cert) X509_free(cert);
        if (chain) sk_X509_pop_free(chain, X509_free);
        output = parsed ? "{\"ok\":false,\"error\":\"empty\"}" : "{\"ok\":false,\"error\":\"password\"}";
        ERR_clear_error();
        return output.c_str();
    }

    char name[512] = {0};
    X509_NAME_get_text_by_NID(X509_get_subject_name(cert), NID_commonName, name, sizeof(name) - 1);
    struct tm when = {};
    long long notAfter = 0;
    if (ASN1_TIME_to_tm(X509_get0_notAfter(cert), &when)) notAfter = (long long)timegm(&when);
    unsigned char digest[EVP_MAX_MD_SIZE];
    unsigned int digestLength = 0;
    X509_digest(cert, EVP_sha1(), digest, &digestLength);

    output = "{\"ok\":true,\"name\":\"" + json_escape(name) + "\",\"notAfter\":" + std::to_string(notAfter) +
             ",\"sha1\":\"" + hex(digest, digestLength) + "\"}";
    EVP_PKEY_free(key);
    X509_free(cert);
    if (chain) sk_X509_pop_free(chain, X509_free);
    return output.c_str();
}

}
