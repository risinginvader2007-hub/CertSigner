#import "CSTLSUtil.h"
#include <OpenSSL/pem.h>
#include <OpenSSL/pkcs12.h>
#include <OpenSSL/x509.h>
#include <OpenSSL/evp.h>
#include <OpenSSL/err.h>

static NSError *CSTLSError(NSInteger code, NSString *message)
{
    return [NSError errorWithDomain:@"CSTLSUtil" code:code userInfo:@{NSLocalizedDescriptionKey: message}];
}

@implementation CSTLSUtil

+ (NSData *)pkcs12WithCertificatePEM:(NSString *)certificatePEM
                       privateKeyPEM:(NSString *)privateKeyPEM
                            password:(NSString *)password
                               error:(NSError **)error
{
    NSData *certData = [certificatePEM dataUsingEncoding:NSUTF8StringEncoding];
    NSData *keyData = [privateKeyPEM dataUsingEncoding:NSUTF8StringEncoding];
    if (certData.length == 0 || keyData.length == 0) {
        if (error) *error = CSTLSError(1, @"The server certificate or key is empty.");
        return nil;
    }

    NSData *result = nil;
    X509 *leaf = NULL;
    EVP_PKEY *key = NULL;
    STACK_OF(X509) *chain = sk_X509_new_null();
    PKCS12 *p12 = NULL;

    BIO *certBio = BIO_new_mem_buf(certData.bytes, (int)certData.length);
    BIO *keyBio = BIO_new_mem_buf(keyData.bytes, (int)keyData.length);

    do {
        leaf = PEM_read_bio_X509(certBio, NULL, NULL, NULL);
        if (leaf == NULL) {
            if (error) *error = CSTLSError(2, @"The server certificate isn't valid PEM.");
            break;
        }
        X509 *extra = NULL;
        while ((extra = PEM_read_bio_X509(certBio, NULL, NULL, NULL)) != NULL) {
            sk_X509_push(chain, extra);
        }
        ERR_clear_error(); // reading past the last certificate sets an error

        key = PEM_read_bio_PrivateKey(keyBio, NULL, NULL, NULL);
        if (key == NULL) {
            if (error) *error = CSTLSError(3, @"The server private key isn't valid PEM (or is encrypted).");
            break;
        }
        if (X509_check_private_key(leaf, key) != 1) {
            if (error) *error = CSTLSError(4, @"The private key doesn't match the server certificate.");
            break;
        }

        const char *pass = password.UTF8String;
        // mac_iter = -1: no MAC here; a SHA-1 MAC is added below for iOS compatibility.
        p12 = PKCS12_create(pass, "CertSigner Install Server", key, leaf, chain,
                            NID_pbe_WithSHA1And3_Key_TripleDES_CBC,
                            NID_pbe_WithSHA1And3_Key_TripleDES_CBC,
                            2048, -1, 0);
        if (p12 == NULL || PKCS12_set_mac(p12, pass, -1, NULL, 0, 2048, EVP_sha1()) != 1) {
            if (error) *error = CSTLSError(5, @"Couldn't package the server certificate.");
            break;
        }

        int length = i2d_PKCS12(p12, NULL);
        if (length <= 0) {
            if (error) *error = CSTLSError(6, @"Couldn't encode the server certificate.");
            break;
        }
        NSMutableData *der = [NSMutableData dataWithLength:(NSUInteger)length];
        unsigned char *cursor = (unsigned char *)der.mutableBytes;
        i2d_PKCS12(p12, &cursor);
        result = der;
    } while (0);

    if (p12) PKCS12_free(p12);
    if (key) EVP_PKEY_free(key);
    if (leaf) X509_free(leaf);
    sk_X509_pop_free(chain, X509_free);
    BIO_free(certBio);
    BIO_free(keyBio);
    return result;
}

@end
