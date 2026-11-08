#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^ZSignLogHandler)(NSString *line, BOOL isError);

FOUNDATION_EXPORT NSErrorDomain const ZSignErrorDomain;

/// Objective-C++ wrapper around the vendored zsign C++ signer.
@interface ZSignBridge : NSObject

/// Signs an extracted .app in place with a .p12 + provisioning profile.
/// Blocks until done; call it off the main thread.
+ (BOOL)signAppAtPath:(NSString *)appPath
              p12Path:(NSString *)p12Path
             password:(NSString *)password
        provisionPath:(NSString *)provisionPath
     entitlementsPath:(nullable NSString *)entitlementsPath
                  log:(nullable ZSignLogHandler)log
                error:(NSError **)error
    NS_SWIFT_NAME(sign(appPath:p12Path:password:provisionPath:entitlementsPath:log:));

@end

NS_ASSUME_NONNULL_END
