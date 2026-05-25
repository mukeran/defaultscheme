#import <Foundation/Foundation.h>
#import "../Shared/DSRoutingConfig.h"

#ifdef __cplusplus
extern "C" {
#endif

extern NSString *const kDSApplicationInfoBundleIDKey;
extern NSString *const kDSApplicationInfoNameKey;

void DSLog(NSString *format, ...);
BOOL DSIsNoAppRule(NSString *bundleID);
NSString *DSTrimmedString(id value);

#ifdef __cplusplus
}
#endif
