#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

void DSForwardingSupportCallWorkspaceBegin(NSString *bundleID);
void DSForwardingSupportCallWorkspaceEnd(NSString *bundleID);
BOOL DSForwardingSupportIsAvailable(void);
void DSForwardingSupportSetTargetBundleID(NSString *bundleID);

#ifdef __cplusplus
}
#endif
