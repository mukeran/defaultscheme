#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

NSString *DSOpenLogTypeForURL(NSURL *url);
void DSStartOpenLogRelayServerIfNeeded(void);
BOOL DSShouldRecordMatchedOpensOnly(void);
void DSAppendOpenLogEntry(NSString *source, NSURL *url, NSString *bundleID, NSDictionary<NSString *, NSString *> *sourceInfo);
void DSAppendObservedOpenLogEntry(NSString *source, NSURL *url, NSString *bundleID, NSDictionary<NSString *, NSString *> *sourceInfo, BOOL matchedRule);
void DSLogDeferredURLPreservingOpenWithSourceInfo(NSString *source, NSURL *url, NSString *bundleID, NSDictionary<NSString *, NSString *> *sourceInfo);
void DSLogDeferredURLPreservingOpen(NSString *source, NSURL *url, NSString *bundleID);

#ifdef __cplusplus
}
#endif
