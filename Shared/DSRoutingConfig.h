#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const kDSRoutingConfigPath;
FOUNDATION_EXPORT NSString *const kDSRoutingConfigMirrorFilename;
FOUNDATION_EXPORT NSString *const kDSNoAppBundleSentinel;
FOUNDATION_EXPORT NSString *const kDSRoutingLinksKey;
FOUNDATION_EXPORT NSString *const kDSLinkRuleHostKey;
FOUNDATION_EXPORT NSString *const kDSLinkRulePathKey;
FOUNDATION_EXPORT NSString *const kDSLinkRuleMatchTypeKey;
FOUNDATION_EXPORT NSString *const kDSLinkRuleBundleIDKey;
FOUNDATION_EXPORT NSString *const kDSLinkRuleSourceHintKey;
FOUNDATION_EXPORT NSString *const kDSLinkRuleRuleIDKey;
FOUNDATION_EXPORT NSString *const kDSLinkRuleHostWildcardKey;
FOUNDATION_EXPORT NSString *const kDSLinkRulePathMatcherKey;
FOUNDATION_EXPORT NSString *const kDSLinkRuleQueryMatcherKey;
FOUNDATION_EXPORT NSString *const kDSLinkRuleIdentityVersionKey;
FOUNDATION_EXPORT NSString *const kDSLinkRuleAssociatedBundleIDKey;
FOUNDATION_EXPORT NSString *const kDSLinkRulePatternKindKey;
FOUNDATION_EXPORT NSString *const kDSLinkRuleRawOpcodeKey;
FOUNDATION_EXPORT NSString *const kDSLinkRuleRawPatternDataKey;
FOUNDATION_EXPORT NSString *const kDSSWCSnapshotPathKey;
FOUNDATION_EXPORT NSString *const kDSSWCSnapshotRulesKey;
FOUNDATION_EXPORT NSString *const kDSSWCSnapshotGeneratedAtKey;
FOUNDATION_EXPORT NSString *const kDSSWCSnapshotFileSizeKey;
FOUNDATION_EXPORT NSString *const kDSSWCSnapshotFileMTimeKey;
FOUNDATION_EXPORT NSString *const kDSSWCSnapshotErrorKey;
FOUNDATION_EXPORT NSString *const kDSOpenLogTimestampKey;
FOUNDATION_EXPORT NSString *const kDSOpenLogURLKey;
FOUNDATION_EXPORT NSString *const kDSOpenLogTypeKey;
FOUNDATION_EXPORT NSString *const kDSOpenLogSourceBundleIDKey;
FOUNDATION_EXPORT NSString *const kDSOpenLogSourceNameKey;
FOUNDATION_EXPORT NSString *const kDSOpenLogTargetBundleIDKey;
FOUNDATION_EXPORT NSString *const kDSOpenLogTargetNameKey;
FOUNDATION_EXPORT NSString *const kDSOpenLogHookSourceKey;
FOUNDATION_EXPORT NSString *const kDSOpenLogRecordMatchedOnlyKey;
FOUNDATION_EXPORT NSString *const kDSRoutingConfigChangedNotification;

@interface DSRoutingConfig : NSObject

+ (NSString *)resolvedConfigPath;
+ (NSString *)routeConfigStateToken;
+ (NSDictionary *)loadConfig;
+ (NSDictionary<NSString *, NSString *> *)schemeRulesFromConfig:(NSDictionary *)config;
+ (NSDictionary<NSString *, NSString *> *)hostRulesFromConfig:(NSDictionary *)config;
+ (NSArray<NSDictionary<NSString *, id> *> *)linkRulesFromConfig:(NSDictionary *)config;
+ (nullable NSDictionary<NSString *, id> *)normalizedLinkRuleFromValue:(id)value;
+ (nullable NSDictionary<NSString *, id> *)normalizedLinkRuleWithHost:(NSString *)host
                                                         pathMatcher:(NSString *)pathMatcher
                                                            bundleID:(NSString *)bundleID
                                                          sourceHint:(nullable NSString *)sourceHint;
+ (nullable NSDictionary<NSString *, id> *)normalizedLinkRuleWithRuleID:(nullable NSString *)ruleID
                                                                   host:(NSString *)host
                                                            pathMatcher:(nullable NSString *)pathMatcher
                                                           queryMatcher:(nullable NSString *)queryMatcher
                                                               bundleID:(NSString *)bundleID
                                                           hostWildcard:(BOOL)hostWildcard
                                                             sourceHint:(nullable NSString *)sourceHint;
+ (nullable NSString *)pathMatcherStringForLinkRule:(NSDictionary<NSString *, id> *)rule;
+ (nullable NSString *)resolvedSharedWebCredentialsDatabasePath;
+ (NSDictionary<NSString *, id> *)sharedWebCredentialsSnapshot;
+ (NSArray<NSDictionary<NSString *, id> *> *)systemLinkRules;
+ (NSArray<NSDictionary<NSString *, id> *> *)systemLinkRulesFromSnapshot:(NSDictionary<NSString *, id> *)snapshot;
+ (NSInteger)matchScoreForSystemLinkRule:(NSDictionary<NSString *, id> *)rule URL:(NSURL *)url;
+ (nullable NSDictionary<NSString *, id> *)bestSystemLinkRuleForURL:(NSURL *)url;
+ (nullable NSDictionary<NSString *, id> *)bestSystemLinkRuleForURL:(NSURL *)url fromRules:(NSArray<NSDictionary<NSString *, id> *> *)rules;
+ (nullable NSDictionary<NSString *, id> *)normalizedOpenLogEntryFromValue:(id)value;
+ (NSArray<NSDictionary<NSString *, id> *> *)openLogs;
+ (BOOL)appendOpenLogEntry:(NSDictionary<NSString *, id> *)entry limit:(NSUInteger)limit error:(NSError **)error;
+ (BOOL)clearOpenLogs:(NSError **)error;
+ (BOOL)openLogRecordsMatchedOnlyFromConfig:(NSDictionary *)config;
+ (BOOL)saveConfig:(NSDictionary *)config error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
