#import <UIKit/UIKit.h>
#import "DSRuleModels.h"

void DSKillProcesses(NSArray<NSString *> *processes);
BOOL DSSyncRouteConfigMirror(NSError **error);
NSString *DSDecodedDisplayString(NSString *value);
NSString *DSLinkDisplayTitle(DSRuleItem *item);
NSArray<NSDictionary<NSString *, id> *> *DSIndexedRuleSections(NSArray<DSRuleItem *> *items, NSString * (^titleProvider)(DSRuleItem *item));
NSString *DSNormalizedCopyableUniversalLinkPath(NSString *pathMatcher);
NSString *DSCopyableUniversalLinkForItem(DSRuleItem *item);
NSString *DSNormalizedRuleIdentityString(id value, BOOL lowercase);
BOOL DSNormalizedRuleIdentityBool(id value);
UIImage *DSIconForBundleID(NSString *bundleID);
UIImage *DSImageScaledToSize(UIImage *image, CGSize size);
NSString *DSDisplayNameForBundleIDInOptions(NSDictionary<NSString *, DSAppOption *> *installedOptionsByBundleID, NSString *bundleID);
NSString *DSAppSummaryForBundleIDInOptions(NSDictionary<NSString *, DSAppOption *> *installedOptionsByBundleID, NSString *bundleID, NSString *fallbackName);
NSString *DSOpenLogDisplayType(NSString *type);
NSString *DSOpenLogFormattedTimestamp(id timestampValue);
NSArray<NSDictionary<NSString *, id> *> *DSSortedOpenLogs(void);
UIImage *DSOpenLogAppIconForBundleID(NSString *bundleID, BOOL isSource);
UIImage *DSCombinedAppIconForBundleIDs(NSString *sourceBundleID, NSString *targetBundleID);
