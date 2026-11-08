#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// OpenSSL helpers for the local HTTPS install server.
@interface CSTLSUtil : NSObject

/// Builds a PKCS#12 (3DES + SHA-1 MAC, which iOS's SecPKCS12Import accepts) from a PEM
/// certificate chain (leaf first, then intermediates) and a PEM private key.
/// Fails if the key doesn't belong to the leaf certificate.
+ (nullable NSData *)pkcs12WithCertificatePEM:(NSString *)certificatePEM
                                privateKeyPEM:(NSString *)privateKeyPEM
                                     password:(NSString *)password
                                        error:(NSError **)error
    NS_SWIFT_NAME(pkcs12(certificatePEM:privateKeyPEM:password:));

@end

NS_ASSUME_NONNULL_END
