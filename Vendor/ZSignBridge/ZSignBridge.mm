#import "ZSignBridge.h"
#include "zsign_api.h"

NSErrorDomain const ZSignErrorDomain = @"ZSignErrorDomain";

static void ZSignBridgeLog(void *context, int color, const char *message)
{
    if (context == NULL || message == NULL) {
        return;
    }
    ZSignLogHandler handler = (__bridge ZSignLogHandler)context;
    NSString *line = [NSString stringWithUTF8String:message];
    if (line == nil) {
        line = [[NSString alloc] initWithBytes:message length:strlen(message) encoding:NSISOLatin1StringEncoding];
    }
    if (line != nil) {
        handler(line, color == 12);
    }
}

@implementation ZSignBridge

+ (BOOL)signAppAtPath:(NSString *)appPath
              p12Path:(NSString *)p12Path
             password:(NSString *)password
        provisionPath:(NSString *)provisionPath
     entitlementsPath:(NSString *)entitlementsPath
                  log:(ZSignLogHandler)log
                error:(NSError **)error
{
    ZSignLogHandler handler = [(log ?: ^(NSString *line, BOOL isError) {}) copy];

    int rc = zsign_sign_folder(appPath.fileSystemRepresentation,
                               p12Path.fileSystemRepresentation,
                               password.UTF8String,
                               provisionPath.fileSystemRepresentation,
                               entitlementsPath.length > 0 ? entitlementsPath.fileSystemRepresentation : NULL,
                               ZSignBridgeLog,
                               (__bridge void *)handler);

    if (rc == ZSIGN_OK) {
        return YES;
    }

    if (error != NULL) {
        NSString *message = rc == ZSIGN_ERR_ASSET
            ? @"Couldn't load the certificate. Check the .p12 password and that it matches the profile."
            : @"zsign couldn't sign the app. See the log for details.";
        *error = [NSError errorWithDomain:ZSignErrorDomain
                                     code:rc
                                 userInfo:@{NSLocalizedDescriptionKey: message}];
    }
    return NO;
}

@end
