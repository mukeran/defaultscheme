#import "DSRoutingConfig.h"

#import <CommonCrypto/CommonDigest.h>
#import <sys/file.h>
#import <mach-o/dyld.h>

NSString *const kDSRoutingConfigPath = @"/private/var/mobile/Library/Preferences/codes.var.tweak.defaultscheme.plist";
NSString *const kDSRoutingConfigMirrorFilename = @"DefaultSchemeConfig.plist";
NSString *const kDSNoAppBundleSentinel = @"__NO_APP__";
NSString *const kDSRoutingLinksKey = @"links";
NSString *const kDSLinkRuleHostKey = @"host";
NSString *const kDSLinkRulePathKey = @"path";
NSString *const kDSLinkRuleMatchTypeKey = @"matchType";
NSString *const kDSLinkRuleBundleIDKey = @"bundleID";
NSString *const kDSLinkRuleSourceHintKey = @"sourceHint";
NSString *const kDSLinkRuleRuleIDKey = @"ruleID";
NSString *const kDSLinkRuleHostWildcardKey = @"hostWildcard";
NSString *const kDSLinkRulePathMatcherKey = @"pathMatcher";
NSString *const kDSLinkRuleQueryMatcherKey = @"queryMatcher";
NSString *const kDSLinkRuleIdentityVersionKey = @"identityVersion";
NSString *const kDSLinkRuleAssociatedBundleIDKey = @"associatedBundleID";
NSString *const kDSLinkRulePatternKindKey = @"patternKind";
NSString *const kDSLinkRuleRawOpcodeKey = @"rawOpcode";
NSString *const kDSLinkRuleRawPatternDataKey = @"rawPatternData";
NSString *const kDSSWCSnapshotPathKey = @"path";
NSString *const kDSSWCSnapshotRulesKey = @"rules";
NSString *const kDSSWCSnapshotGeneratedAtKey = @"generatedAt";
NSString *const kDSSWCSnapshotFileSizeKey = @"fileSize";
NSString *const kDSSWCSnapshotFileMTimeKey = @"fileMTime";
NSString *const kDSSWCSnapshotErrorKey = @"error";
NSString *const kDSOpenLogTimestampKey = @"timestamp";
NSString *const kDSOpenLogURLKey = @"url";
NSString *const kDSOpenLogTypeKey = @"openType";
NSString *const kDSOpenLogSourceBundleIDKey = @"sourceBundleID";
NSString *const kDSOpenLogSourceNameKey = @"sourceName";
NSString *const kDSOpenLogTargetBundleIDKey = @"targetBundleID";
NSString *const kDSOpenLogTargetNameKey = @"targetName";
NSString *const kDSOpenLogHookSourceKey = @"hookSource";
NSString *const kDSOpenLogRecordMatchedOnlyKey = @"openLogRecordsMatchedOnly";
NSString *const kDSRoutingConfigChangedNotification = @"codes.var.tweak.defaultscheme.config.changed";

static NSString *const kDSRoutingConfigDomain = @"codes.var.tweak.defaultscheme";
static NSString *const kDSRoutingSchemesKey = @"schemes";
static NSString *const kDSRoutingHostsKey = @"hosts";
static NSString *const kDSRoutingOpenLogsKey = @"openLogs";
static NSString *const kDSLinkRuleMatchTypeExact = @"exact";
static NSString *const kDSLinkRuleMatchTypePrefix = @"prefix";
static NSString *const kDSLinkRuleMatchTypeWildcard = @"wildcard";
static NSString *const kDSSWCSourceHint = @"swc";
static NSString *const kDSOpenLogTypeScheme = @"scheme";
static NSString *const kDSOpenLogTypeUniversalLink = @"universalLink";
static NSUInteger const kDSRoutingOpenLogsDefaultLimit = 200;
static NSTimeInterval const kDSRoutingOpenLogDeduplicationWindow = 2.0;
static NSString *const kDSLinkRuleIdentityVersion = @"1";
static NSString *const kDSLinkRulePatternKindAny = @"any";
static NSString *const kDSLinkRulePatternKindPath = @"path";
static NSString *const kDSLinkRulePatternKindQuery = @"query";
static NSString *const kDSLinkRulePatternKindPathQuery = @"pathQuery";
static NSString *const kDSLinkRulePatternKindUnsupported = @"unsupported";
static NSString *const kDSSWCInternalDaemonRoot = @"/private/var/mobile/Containers/Data/InternalDaemon";
static NSString *const kDSSWCRelativeDatabasePath = @"com.apple.SharedWebCredentials/swc.db";
static NSString *const kDSCompiledPathRegexKey = @"_compiledPathRegex";
static NSString *const kDSCompiledQueryRequirementsKey = @"_compiledQueryRequirements";
static NSString *const kDSRuleLiteralScoreKey = @"_literalScore";
static NSString *const kDSRuleSortIndexKey = @"_sortIndex";
static NSString *const kDSOpenLogLockPath = @"/private/var/mobile/Library/Preferences/codes.var.tweak.defaultscheme.openlogs.lock";

static NSDictionary<NSString *, id> *gDSSWCSnapshotCache = nil;
static NSString *gDSSWCSnapshotCachePath = nil;
static unsigned long long gDSSWCSnapshotCacheSize = 0;
static NSTimeInterval gDSSWCSnapshotCacheMTime = 0;

static void DSConfigLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"[DefaultScheme] %@", msg ?: @"");
}

static NSString *DSHexStringFromData(NSData *data) {
    if (![data isKindOfClass:[NSData class]] || data.length == 0) {
        return nil;
    }
    const unsigned char *bytes = data.bytes;
    NSMutableString *result = [NSMutableString stringWithCapacity:data.length * 2];
    for (NSUInteger index = 0; index < data.length; index++) {
        [result appendFormat:@"%02x", bytes[index]];
    }
    return result;
}

static NSString *DSSHA256String(NSString *value) {
    NSData *data = [[value ?: @"" dataUsingEncoding:NSUTF8StringEncoding] copy];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH] = {0};
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *result = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) {
        [result appendFormat:@"%02x", digest[index]];
    }
    return result;
}

static NSDictionary<NSString *, NSString *> *DSBuiltInVariablePatterns(void) {
    static NSDictionary<NSString *, NSString *> *patterns = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        patterns = @{
            @"alnum": @"[A-Za-z0-9]+",
            @"flag": @"(?:true|false)",
            @"path_variants": @"[^/?#]+",
            @"region": @"[A-Za-z]{2}(?:-[A-Za-z]{2})?",
        };
    });
    return patterns;
}

@implementation DSRoutingConfig

+ (NSString *)resolvedConfigPath {
    return kDSRoutingConfigPath;
}

+ (NSArray<NSString *> *)_uniquePathsFromPaths:(NSArray<NSString *> *)paths {
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSString *path in paths) {
        if (![path isKindOfClass:[NSString class]] || path.length == 0 || [seen containsObject:path]) {
            continue;
        }
        [seen addObject:path];
        [result addObject:path];
    }
    return [result copy];
}

+ (NSString *)routeConfigStateToken {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *paths = [NSMutableArray arrayWithArray:[self configPathCandidates]];
    [paths addObjectsFromArray:[self configMirrorPathCandidates]];
    for (NSString *path in [self _uniquePathsFromPaths:paths]) {
        NSDictionary<NSFileAttributeKey, id> *attributes = [fileManager attributesOfItemAtPath:path error:nil];
        if (attributes.count == 0) {
            continue;
        }
        NSDate *modifiedAt = attributes[NSFileModificationDate];
        unsigned long long fileSize = [attributes fileSize];
        [parts addObject:[NSString stringWithFormat:@"%@:%llu:%.6f", path, fileSize, modifiedAt.timeIntervalSince1970]];
    }
    return parts.count > 0 ? [parts componentsJoinedByString:@"|"] : @"empty";
}

+ (void)_postRouteConfigChangedNotification {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)kDSRoutingConfigChangedNotification,
                                         NULL,
                                         NULL,
                                         YES);
    [[NSNotificationCenter defaultCenter] postNotificationName:kDSRoutingConfigChangedNotification object:self];
}

+ (NSArray<NSString *> *)configPathCandidates {
    NSString *rootfsPath = [@"/rootfs" stringByAppendingString:kDSRoutingConfigPath];
    return @[rootfsPath, kDSRoutingConfigPath];
}

+ (NSArray<NSString *> *)configMirrorPathCandidates {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    uint32_t imageCount = _dyld_image_count();
    for (uint32_t index = 0; index < imageCount; index++) {
        const char *imageName = _dyld_get_image_name(index);
        if (!imageName) {
            continue;
        }
        NSString *imagePath = [NSString stringWithUTF8String:imageName];
        if (![imagePath.lastPathComponent isEqualToString:@"DefaultSchemeTweak.dylib"]) {
            continue;
        }
        NSString *directory = [imagePath stringByDeletingLastPathComponent];
        if (directory.length > 0) {
            [paths addObject:[directory stringByAppendingPathComponent:kDSRoutingConfigMirrorFilename]];
        }
    }
    return [self _uniquePathsFromPaths:paths];
}

+ (NSDictionary *)_fileConfigAtPath:(NSString *)path {
    if (path.length == 0) {
        return nil;
    }
    NSDictionary *rawConfig = [NSDictionary dictionaryWithContentsOfFile:path];
    if (![rawConfig isKindOfClass:[NSDictionary class]] || rawConfig.count == 0) {
        return nil;
    }

    NSMutableDictionary *config = [NSMutableDictionary dictionary];
    NSDictionary *schemes = [self schemeRulesFromConfig:rawConfig];
    NSDictionary *hosts = [self hostRulesFromConfig:rawConfig];
    NSArray *links = [self linkRulesFromConfig:rawConfig];
    BOOL openLogRecordsMatchedOnly = [self openLogRecordsMatchedOnlyFromConfig:rawConfig];
    if (schemes.count > 0) {
        config[kDSRoutingSchemesKey] = schemes;
    }
    if (hosts.count > 0) {
        config[kDSRoutingHostsKey] = hosts;
    }
    if (links.count > 0) {
        config[kDSRoutingLinksKey] = links;
    }
    if (openLogRecordsMatchedOnly) {
        config[kDSOpenLogRecordMatchedOnlyKey] = @YES;
    }
    return config.count > 0 ? config : nil;
}

+ (NSDictionary *)_fileConfigFromCandidates:(NSArray<NSString *> *)paths {
    for (NSString *path in [self _uniquePathsFromPaths:paths]) {
        NSDictionary *config = [self _fileConfigAtPath:path];
        if (config.count > 0) {
            DSConfigLog(@"config load source=file path=%@ count=%lu", path, (unsigned long)config.count);
            return config;
        }
    }
    return nil;
}

+ (NSArray<NSString *> *)sharedWebCredentialsRootCandidates {
    NSString *rootfsPath = [@"/rootfs" stringByAppendingString:kDSSWCInternalDaemonRoot];
    return @[kDSSWCInternalDaemonRoot, rootfsPath];
}

+ (NSDictionary *)_preferencesConfig {
    CFStringRef appID = (__bridge CFStringRef)kDSRoutingConfigDomain;
    DSConfigLog(@"config prefs lookup begin domain=%@ process=%@", kDSRoutingConfigDomain, NSProcessInfo.processInfo.processName ?: @"?");

    id schemes = CFBridgingRelease(CFPreferencesCopyValue((__bridge CFStringRef)kDSRoutingSchemesKey,
                                                          appID,
                                                          kCFPreferencesCurrentUser,
                                                          kCFPreferencesAnyHost));
    id hosts = CFBridgingRelease(CFPreferencesCopyValue((__bridge CFStringRef)kDSRoutingHostsKey,
                                                        appID,
                                                        kCFPreferencesCurrentUser,
                                                        kCFPreferencesAnyHost));
    id links = CFBridgingRelease(CFPreferencesCopyValue((__bridge CFStringRef)kDSRoutingLinksKey,
                                                        appID,
                                                        kCFPreferencesCurrentUser,
                                                        kCFPreferencesAnyHost));
    id openLogRecordsMatchedOnly = CFBridgingRelease(CFPreferencesCopyValue((__bridge CFStringRef)kDSOpenLogRecordMatchedOnlyKey,
                                                                            appID,
                                                                            kCFPreferencesCurrentUser,
                                                                            kCFPreferencesAnyHost));

    NSMutableDictionary *config = [NSMutableDictionary dictionary];
    if ([schemes isKindOfClass:[NSDictionary class]]) {
        config[kDSRoutingSchemesKey] = schemes;
    }
    if ([hosts isKindOfClass:[NSDictionary class]]) {
        config[kDSRoutingHostsKey] = hosts;
    }
    if ([links isKindOfClass:[NSArray class]]) {
        config[kDSRoutingLinksKey] = links;
    }
    if (openLogRecordsMatchedOnly) {
        config[kDSOpenLogRecordMatchedOnlyKey] = @([self _normalizedBoolFromValue:openLogRecordsMatchedOnly defaultValue:NO]);
    }
    if (config.count == 0) {
        DSConfigLog(@"config prefs lookup miss domain=%@ schemesClass=%@ hostsClass=%@ linksClass=%@",
                    kDSRoutingConfigDomain,
                    schemes ? NSStringFromClass([schemes class]) : @"nil",
                    hosts ? NSStringFromClass([hosts class]) : @"nil",
                    links ? NSStringFromClass([links class]) : @"nil");
        return nil;
    }

    DSConfigLog(@"config prefs lookup result schemes=%lu hosts=%lu links=%lu",
                (unsigned long)[config[kDSRoutingSchemesKey] count],
                (unsigned long)[config[kDSRoutingHostsKey] count],
                (unsigned long)[config[kDSRoutingLinksKey] count]);
    return config;
}

+ (BOOL)openLogRecordsMatchedOnlyFromConfig:(NSDictionary *)config {
    if (![config isKindOfClass:[NSDictionary class]]) {
        return NO;
    }
    return [self _normalizedBoolFromValue:config[kDSOpenLogRecordMatchedOnlyKey] defaultValue:NO];
}

+ (NSDictionary *)loadConfig {
    NSDictionary *config = [self _preferencesConfig];
    if ([config isKindOfClass:[NSDictionary class]] && config.count > 0) {
        DSConfigLog(@"config load source=preferences count=%lu", (unsigned long)config.count);
        return config;
    }

    config = [self _fileConfigFromCandidates:[self configMirrorPathCandidates]];
    if ([config isKindOfClass:[NSDictionary class]] && config.count > 0) {
        return config;
    }

    config = [self _fileConfigFromCandidates:[self configPathCandidates]];
    if ([config isKindOfClass:[NSDictionary class]] && config.count > 0) {
        return config;
    }

    DSConfigLog(@"config load empty");
    return @{};
}

+ (NSDictionary<NSString *, NSString *> *)_stringMapFromValue:(id)value {
    if (![value isKindOfClass:[NSDictionary class]]) {
        return @{};
    }
    NSMutableDictionary<NSString *, NSString *> *result = [NSMutableDictionary dictionary];
    [(NSDictionary *)value enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if (![key isKindOfClass:[NSString class]] || ![obj isKindOfClass:[NSString class]]) {
            return;
        }
        NSString *normalizedKey = [(NSString *)key lowercaseString];
        if (normalizedKey.length == 0 || [(NSString *)obj length] == 0) {
            return;
        }
        result[normalizedKey] = obj;
    }];
    return result;
}

+ (NSString *)_normalizedHostFromValue:(id)value {
    if (![value isKindOfClass:[NSString class]]) {
        return nil;
    }
    NSString *host = [[(NSString *)value lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return host.length > 0 ? host : nil;
}

+ (NSString *)_normalizedBundleIDFromValue:(id)value {
    if (![value isKindOfClass:[NSString class]]) {
        return nil;
    }
    NSString *bundleID = [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return bundleID.length > 0 ? bundleID : nil;
}

+ (NSString *)_normalizedSourceHintFromValue:(id)value {
    if (![value isKindOfClass:[NSString class]]) {
        return nil;
    }
    NSString *sourceHint = [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return sourceHint.length > 0 ? sourceHint : nil;
}

+ (NSString *)_normalizedRuleIDFromValue:(id)value {
    if (![value isKindOfClass:[NSString class]]) {
        return nil;
    }
    NSString *ruleID = [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return ruleID.length > 0 ? ruleID : nil;
}

+ (NSString *)_normalizedQueryFromValue:(id)value {
    if (![value isKindOfClass:[NSString class]]) {
        return nil;
    }
    NSString *queryMatcher = [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return queryMatcher.length > 0 ? queryMatcher : nil;
}

+ (NSString *)_normalizedIdentityVersionFromValue:(id)value {
    if ([value isKindOfClass:[NSNumber class]]) {
        return [(NSNumber *)value stringValue];
    }
    if (![value isKindOfClass:[NSString class]]) {
        return nil;
    }
    NSString *identityVersion = [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return identityVersion.length > 0 ? identityVersion : nil;
}

+ (NSString *)_normalizedOpenLogNameFromValue:(id)value {
    if (![value isKindOfClass:[NSString class]]) {
        return nil;
    }
    NSString *name = [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return name.length > 0 ? name : nil;
}

+ (NSTimeInterval)_normalizedTimestampFromValue:(id)value {
    if ([value isKindOfClass:[NSNumber class]]) {
        return [(NSNumber *)value doubleValue];
    }
    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value doubleValue];
    }
    return 0;
}

+ (NSString *)_normalizedOpenLogTypeFromValue:(id)value URLString:(NSString *)urlString {
    NSString *type = [self _normalizedSourceHintFromValue:value];
    if ([type isEqualToString:kDSOpenLogTypeScheme] || [type isEqualToString:kDSOpenLogTypeUniversalLink]) {
        return type;
    }
    NSURL *url = [NSURL URLWithString:urlString ?: @""];
    NSString *scheme = url.scheme.lowercaseString;
    if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) {
        return kDSOpenLogTypeUniversalLink;
    }
    return kDSOpenLogTypeScheme;
}

+ (NSString *)_deduplicationKeyForOpenLogEntry:(NSDictionary<NSString *, id> *)entry {
    NSString *type = [self _normalizedOpenLogTypeFromValue:entry[kDSOpenLogTypeKey] URLString:entry[kDSOpenLogURLKey]];
    NSString *urlString = [self _normalizedSourceHintFromValue:entry[kDSOpenLogURLKey]];
    NSString *targetBundleID = [self _normalizedBundleIDFromValue:entry[kDSOpenLogTargetBundleIDKey]];
    if (type.length == 0 || urlString.length == 0 || targetBundleID.length == 0) {
        return nil;
    }
    return [NSString stringWithFormat:@"%@\n%@\n%@", type, urlString, targetBundleID];
}

+ (NSUInteger)_metadataCompletenessScoreForOpenLogEntry:(NSDictionary<NSString *, id> *)entry {
    NSUInteger score = 0;
    if ([self _normalizedBundleIDFromValue:entry[kDSOpenLogSourceBundleIDKey]].length > 0) {
        score += 4;
    }
    if ([self _normalizedOpenLogNameFromValue:entry[kDSOpenLogSourceNameKey]].length > 0) {
        score += 2;
    }
    if ([self _normalizedOpenLogNameFromValue:entry[kDSOpenLogTargetNameKey]].length > 0) {
        score += 1;
    }
    return score;
}

+ (NSInteger)_recentDuplicateIndexForOpenLogEntry:(NSDictionary<NSString *, id> *)entry inLogs:(NSArray<NSDictionary<NSString *, id> *> *)logs {
    NSString *deduplicationKey = [self _deduplicationKeyForOpenLogEntry:entry];
    if (deduplicationKey.length == 0 || logs.count == 0) {
        return NSNotFound;
    }

    NSTimeInterval timestamp = [self _normalizedTimestampFromValue:entry[kDSOpenLogTimestampKey]];
    for (NSInteger index = (NSInteger)logs.count - 1; index >= 0; index--) {
        NSDictionary<NSString *, id> *existing = logs[(NSUInteger)index];
        NSTimeInterval existingTimestamp = [self _normalizedTimestampFromValue:existing[kDSOpenLogTimestampKey]];
        if (timestamp > 0 && existingTimestamp > 0 && (timestamp - existingTimestamp) > kDSRoutingOpenLogDeduplicationWindow) {
            break;
        }
        if ([[self _deduplicationKeyForOpenLogEntry:existing] isEqualToString:deduplicationKey]) {
            return index;
        }
    }
    return NSNotFound;
}

+ (NSDictionary<NSString *, id> *)_preferredOpenLogEntryBetweenExisting:(NSDictionary<NSString *, id> *)existing incoming:(NSDictionary<NSString *, id> *)incoming {
    if (!existing) {
        return incoming;
    }
    if (!incoming) {
        return existing;
    }

    NSUInteger existingScore = [self _metadataCompletenessScoreForOpenLogEntry:existing];
    NSUInteger incomingScore = [self _metadataCompletenessScoreForOpenLogEntry:incoming];
    if (incomingScore > existingScore) {
        return incoming;
    }
    if (incomingScore < existingScore) {
        return existing;
    }

    NSTimeInterval existingTimestamp = [self _normalizedTimestampFromValue:existing[kDSOpenLogTimestampKey]];
    NSTimeInterval incomingTimestamp = [self _normalizedTimestampFromValue:incoming[kDSOpenLogTimestampKey]];
    return incomingTimestamp >= existingTimestamp ? incoming : existing;
}

+ (BOOL)_normalizedBoolFromValue:(id)value defaultValue:(BOOL)defaultValue {
    if ([value isKindOfClass:[NSNumber class]]) {
        return [(NSNumber *)value boolValue];
    }
    if ([value isKindOfClass:[NSString class]]) {
        NSString *normalized = [[(NSString *)value lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([normalized isEqualToString:@"1"] || [normalized isEqualToString:@"true"] || [normalized isEqualToString:@"yes"]) {
            return YES;
        }
        if ([normalized isEqualToString:@"0"] || [normalized isEqualToString:@"false"] || [normalized isEqualToString:@"no"]) {
            return NO;
        }
    }
    return defaultValue;
}

+ (NSString *)_normalizedPathFromValue:(id)value allowWildcard:(BOOL)allowWildcard {
    if (![value isKindOfClass:[NSString class]]) {
        return nil;
    }
    NSString *path = [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (path.length == 0) {
        return nil;
    }
    if (![path hasPrefix:@"/"]) {
        path = [@"/" stringByAppendingString:path];
    }
    if (!allowWildcard && [path containsString:@"*"]) {
        return nil;
    }
    return path;
}

+ (NSString *)_normalizedMatchTypeFromValue:(id)value {
    if (![value isKindOfClass:[NSString class]]) {
        return nil;
    }
    NSString *matchType = [[(NSString *)value lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([matchType isEqualToString:kDSLinkRuleMatchTypeExact] ||
        [matchType isEqualToString:kDSLinkRuleMatchTypePrefix] ||
        [matchType isEqualToString:kDSLinkRuleMatchTypeWildcard]) {
        return matchType;
    }
    return nil;
}

+ (NSDictionary<NSString *, NSString *> *)_legacyComponentsForPathMatcher:(NSString *)pathMatcher {
    NSString *matcher = [self _normalizedPathFromValue:pathMatcher allowWildcard:YES];
    if (matcher.length == 0) {
        return nil;
    }

    NSString *matchType = nil;
    NSString *path = nil;
    NSRange firstWildcard = [matcher rangeOfString:@"*"];
    if (firstWildcard.location == NSNotFound) {
        matchType = kDSLinkRuleMatchTypeExact;
        path = matcher;
    } else if (firstWildcard.location == matcher.length - 1 && [matcher rangeOfString:@"*" options:NSBackwardsSearch].location == firstWildcard.location) {
        matchType = kDSLinkRuleMatchTypePrefix;
        path = [matcher substringToIndex:matcher.length - 1];
        if (path.length == 0) {
            path = @"/";
        }
    } else {
        matchType = kDSLinkRuleMatchTypeWildcard;
        path = matcher;
    }

    return @{
        kDSLinkRulePathMatcherKey: matcher,
        kDSLinkRulePathKey: path,
        kDSLinkRuleMatchTypeKey: matchType,
    };
}

+ (NSDictionary<NSString *, id> *)_normalizedLinkRuleWithHost:(NSString *)host
                                                         path:(NSString *)path
                                                    matchType:(NSString *)matchType
                                                     bundleID:(NSString *)bundleID
                                                   sourceHint:(NSString *)sourceHint {
    NSString *normalizedHost = [self _normalizedHostFromValue:host];
    NSString *normalizedBundleID = [self _normalizedBundleIDFromValue:bundleID];
    NSString *normalizedMatchType = [self _normalizedMatchTypeFromValue:matchType];
    if (normalizedHost.length == 0 || normalizedBundleID.length == 0 || normalizedMatchType.length == 0) {
        return nil;
    }

    BOOL allowWildcard = [normalizedMatchType isEqualToString:kDSLinkRuleMatchTypeWildcard];
    NSString *normalizedPath = [self _normalizedPathFromValue:path allowWildcard:allowWildcard];
    if (normalizedPath.length == 0) {
        return nil;
    }
    if ([normalizedMatchType isEqualToString:kDSLinkRuleMatchTypePrefix] && [normalizedPath containsString:@"*"]) {
        return nil;
    }
    if ([normalizedMatchType isEqualToString:kDSLinkRuleMatchTypeExact] && [normalizedPath containsString:@"*"]) {
        return nil;
    }
    if ([normalizedMatchType isEqualToString:kDSLinkRuleMatchTypeWildcard] && ![normalizedPath containsString:@"*"]) {
        return nil;
    }

    NSString *pathMatcher = normalizedPath;
    if ([normalizedMatchType isEqualToString:kDSLinkRuleMatchTypePrefix]) {
        pathMatcher = [normalizedPath stringByAppendingString:@"*"];
    }

    NSMutableDictionary<NSString *, id> *rule = [NSMutableDictionary dictionaryWithDictionary:@{
        kDSLinkRuleHostKey: normalizedHost,
        kDSLinkRulePathKey: normalizedPath,
        kDSLinkRuleMatchTypeKey: normalizedMatchType,
        kDSLinkRuleBundleIDKey: normalizedBundleID,
        kDSLinkRulePathMatcherKey: pathMatcher,
        kDSLinkRulePatternKindKey: kDSLinkRulePatternKindPath,
    }];
    NSString *normalizedSourceHint = [self _normalizedSourceHintFromValue:sourceHint];
    if (normalizedSourceHint.length > 0) {
        rule[kDSLinkRuleSourceHintKey] = normalizedSourceHint;
    }
    return rule;
}

+ (NSDictionary<NSString *, id> *)normalizedLinkRuleWithHost:(NSString *)host
                                                 pathMatcher:(NSString *)pathMatcher
                                                    bundleID:(NSString *)bundleID
                                                  sourceHint:(NSString *)sourceHint {
    return [self normalizedLinkRuleWithRuleID:nil
                                         host:host
                                  pathMatcher:pathMatcher
                                 queryMatcher:nil
                                     bundleID:bundleID
                                 hostWildcard:NO
                                   sourceHint:sourceHint];
}

+ (NSDictionary<NSString *, id> *)normalizedLinkRuleWithRuleID:(NSString *)ruleID
                                                           host:(NSString *)host
                                                    pathMatcher:(NSString *)pathMatcher
                                                   queryMatcher:(NSString *)queryMatcher
                                                       bundleID:(NSString *)bundleID
                                                   hostWildcard:(BOOL)hostWildcard
                                                     sourceHint:(NSString *)sourceHint {
    NSString *normalizedHost = [self _normalizedHostFromValue:host];
    NSString *normalizedBundleID = [self _normalizedBundleIDFromValue:bundleID];
    NSString *normalizedRuleID = [self _normalizedRuleIDFromValue:ruleID];
    NSString *normalizedQueryMatcher = [self _normalizedQueryFromValue:queryMatcher];
    NSString *normalizedSourceHint = [self _normalizedSourceHintFromValue:sourceHint];
    NSDictionary<NSString *, NSString *> *legacyComponents = [self _legacyComponentsForPathMatcher:pathMatcher];
    NSString *normalizedPathMatcher = legacyComponents[kDSLinkRulePathMatcherKey];

    if (normalizedHost.length == 0 || normalizedBundleID.length == 0) {
        return nil;
    }
    if (normalizedPathMatcher.length == 0 && normalizedQueryMatcher.length == 0 && normalizedRuleID.length == 0) {
        return nil;
    }

    NSMutableDictionary<NSString *, id> *rule = [NSMutableDictionary dictionaryWithDictionary:@{
        kDSLinkRuleHostKey: normalizedHost,
        kDSLinkRuleBundleIDKey: normalizedBundleID,
    }];
    if (legacyComponents.count > 0) {
        [rule addEntriesFromDictionary:legacyComponents];
    }
    if (normalizedQueryMatcher.length > 0) {
        rule[kDSLinkRuleQueryMatcherKey] = normalizedQueryMatcher;
    }
    if (normalizedSourceHint.length > 0) {
        rule[kDSLinkRuleSourceHintKey] = normalizedSourceHint;
    }
    if (normalizedRuleID.length > 0) {
        rule[kDSLinkRuleRuleIDKey] = normalizedRuleID;
        rule[kDSLinkRuleIdentityVersionKey] = kDSLinkRuleIdentityVersion;
    }
    if (hostWildcard) {
        rule[kDSLinkRuleHostWildcardKey] = @YES;
    }

    NSInteger pathLiteralCount = 0;
    BOOL pathSupported = YES;
    NSRegularExpression *pathRegex = nil;
    if (normalizedPathMatcher.length > 0) {
        pathRegex = [self _compiledRegexForTokenPattern:normalizedPathMatcher variables:nil literalCount:&pathLiteralCount supported:&pathSupported];
    }

    NSInteger queryLiteralCount = 0;
    BOOL querySupported = YES;
    NSArray<NSDictionary<NSString *, id> *> *queryRequirements = nil;
    if (normalizedQueryMatcher.length > 0) {
        queryRequirements = [self _compiledQueryRequirementsForMatcher:normalizedQueryMatcher variables:nil literalCount:&queryLiteralCount supported:&querySupported];
    }

    NSString *patternKind = nil;
    if (normalizedPathMatcher.length > 0 && normalizedQueryMatcher.length > 0) {
        patternKind = kDSLinkRulePatternKindPathQuery;
    } else if (normalizedQueryMatcher.length > 0) {
        patternKind = kDSLinkRulePatternKindQuery;
    } else if (normalizedPathMatcher.length > 0) {
        patternKind = kDSLinkRulePatternKindPath;
    } else {
        patternKind = kDSLinkRulePatternKindAny;
    }

    if ((normalizedPathMatcher.length > 0 && (!pathSupported || !pathRegex)) ||
        (normalizedQueryMatcher.length > 0 && (!querySupported || queryRequirements == nil))) {
        patternKind = kDSLinkRulePatternKindUnsupported;
    }

    rule[kDSLinkRulePatternKindKey] = patternKind;
    rule[kDSRuleLiteralScoreKey] = @(pathLiteralCount + queryLiteralCount);
    if (pathRegex) {
        rule[kDSCompiledPathRegexKey] = pathRegex;
    }
    if (queryRequirements.count > 0) {
        rule[kDSCompiledQueryRequirementsKey] = queryRequirements;
    }
    return rule;
}

+ (NSDictionary<NSString *, id> *)normalizedLinkRuleFromValue:(id)value {
    if (![value isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    NSDictionary *dictionary = (NSDictionary *)value;
    NSString *host = dictionary[kDSLinkRuleHostKey];
    NSString *bundleID = dictionary[kDSLinkRuleBundleIDKey] ?: dictionary[@"bundleId"];
    NSString *sourceHint = dictionary[kDSLinkRuleSourceHintKey];
    NSString *ruleID = dictionary[kDSLinkRuleRuleIDKey];
    NSString *pathMatcher = dictionary[kDSLinkRulePathMatcherKey] ?: dictionary[@"pathMatcher"];
    NSString *queryMatcher = dictionary[kDSLinkRuleQueryMatcherKey];
    BOOL hasHostWildcard = dictionary[kDSLinkRuleHostWildcardKey] != nil;
    BOOL hostWildcard = [self _normalizedBoolFromValue:dictionary[kDSLinkRuleHostWildcardKey] defaultValue:NO];

    NSDictionary<NSString *, id> *rule = nil;
    if (pathMatcher.length > 0 || queryMatcher.length > 0 || ruleID.length > 0 || hasHostWildcard) {
        rule = [self normalizedLinkRuleWithRuleID:ruleID
                                             host:host
                                      pathMatcher:pathMatcher
                                     queryMatcher:queryMatcher
                                         bundleID:bundleID
                                     hostWildcard:hostWildcard
                                       sourceHint:sourceHint];
    } else {
        NSString *path = dictionary[kDSLinkRulePathKey];
        NSString *matchType = dictionary[kDSLinkRuleMatchTypeKey];
        rule = [self _normalizedLinkRuleWithHost:host path:path matchType:matchType bundleID:bundleID sourceHint:sourceHint];
    }
    if (!rule) {
        return nil;
    }

    NSMutableDictionary<NSString *, id> *result = [rule mutableCopy];
    NSString *identityVersion = [self _normalizedIdentityVersionFromValue:dictionary[kDSLinkRuleIdentityVersionKey]];
    if (identityVersion.length > 0) {
        result[kDSLinkRuleIdentityVersionKey] = identityVersion;
    }
    NSString *associatedBundleID = [self _normalizedBundleIDFromValue:dictionary[kDSLinkRuleAssociatedBundleIDKey]];
    if (associatedBundleID.length > 0) {
        result[kDSLinkRuleAssociatedBundleIDKey] = associatedBundleID;
    }
    if ([dictionary[kDSLinkRuleRawOpcodeKey] isKindOfClass:[NSNumber class]]) {
        result[kDSLinkRuleRawOpcodeKey] = dictionary[kDSLinkRuleRawOpcodeKey];
    }
    NSString *rawPatternData = [self _normalizedRuleIDFromValue:dictionary[kDSLinkRuleRawPatternDataKey]];
    if (rawPatternData.length > 0) {
        result[kDSLinkRuleRawPatternDataKey] = rawPatternData;
    }
    return result;
}

+ (NSString *)pathMatcherStringForLinkRule:(NSDictionary<NSString *, id> *)rule {
    NSDictionary<NSString *, id> *normalizedRule = [self normalizedLinkRuleFromValue:rule];
    if (!normalizedRule) {
        return nil;
    }

    NSString *pathMatcher = normalizedRule[kDSLinkRulePathMatcherKey];
    if (pathMatcher.length > 0) {
        return pathMatcher;
    }

    NSString *matchType = normalizedRule[kDSLinkRuleMatchTypeKey];
    NSString *path = normalizedRule[kDSLinkRulePathKey];
    if ([matchType isEqualToString:kDSLinkRuleMatchTypePrefix]) {
        return [path stringByAppendingString:@"*"];
    }
    return path;
}

+ (NSArray<NSDictionary<NSString *, id> *> *)linkRulesFromConfig:(NSDictionary *)config {
    if (![config[kDSRoutingLinksKey] isKindOfClass:[NSArray class]]) {
        return @[];
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *result = [NSMutableArray array];
    for (id value in (NSArray *)config[kDSRoutingLinksKey]) {
        NSDictionary<NSString *, id> *rule = [self normalizedLinkRuleFromValue:value];
        if (rule) {
            [result addObject:rule];
        }
    }
    return result;
}

+ (NSDictionary<NSString *, id> *)_persistentLinkRuleFromValue:(id)value {
    NSDictionary<NSString *, id> *rule = [self normalizedLinkRuleFromValue:value];
    if (!rule) {
        return nil;
    }

    NSMutableDictionary<NSString *, id> *persistentRule = [NSMutableDictionary dictionary];
    NSArray<NSString *> *stringKeys = @[
        kDSLinkRuleHostKey,
        kDSLinkRulePathKey,
        kDSLinkRuleMatchTypeKey,
        kDSLinkRuleBundleIDKey,
        kDSLinkRuleSourceHintKey,
        kDSLinkRuleRuleIDKey,
        kDSLinkRulePathMatcherKey,
        kDSLinkRuleQueryMatcherKey,
        kDSLinkRuleIdentityVersionKey,
        kDSLinkRuleAssociatedBundleIDKey,
        kDSLinkRulePatternKindKey,
        kDSLinkRuleRawPatternDataKey,
    ];
    for (NSString *key in stringKeys) {
        NSString *stringValue = [rule[key] isKindOfClass:[NSString class]] ? rule[key] : nil;
        if (stringValue.length > 0) {
            persistentRule[key] = stringValue;
        }
    }

    if ([rule[kDSLinkRuleHostWildcardKey] respondsToSelector:@selector(boolValue)]) {
        persistentRule[kDSLinkRuleHostWildcardKey] = @([rule[kDSLinkRuleHostWildcardKey] boolValue]);
    }
    if ([rule[kDSLinkRuleRawOpcodeKey] isKindOfClass:[NSNumber class]]) {
        persistentRule[kDSLinkRuleRawOpcodeKey] = rule[kDSLinkRuleRawOpcodeKey];
    }
    return persistentRule.count > 0 ? persistentRule : nil;
}

+ (NSDictionary<NSString *, NSString *> *)schemeRulesFromConfig:(NSDictionary *)config {
    return [self _stringMapFromValue:config[kDSRoutingSchemesKey]];
}

+ (NSDictionary<NSString *, NSString *> *)hostRulesFromConfig:(NSDictionary *)config {
    return [self _stringMapFromValue:config[kDSRoutingHostsKey]];
}

+ (NSNumber *)_swcObjectIndexFromReference:(id)reference {
    if ([reference isKindOfClass:[NSDictionary class]]) {
        id uidValue = ((NSDictionary *)reference)[@"CF$UID"];
        if ([uidValue isKindOfClass:[NSNumber class]]) {
            return uidValue;
        }
    }

    NSString *className = NSStringFromClass([reference class]);
    NSString *description = [reference description];
    BOOL looksLikeUID = [className rangeOfString:@"UID"].location != NSNotFound || [description rangeOfString:@"CFKeyedArchiverUID"].location != NSNotFound;
    if (looksLikeUID) {
        if ([reference respondsToSelector:@selector(unsignedIntegerValue)]) {
            return @([(id)reference unsignedIntegerValue]);
        }

        NSRange markerRange = [description rangeOfString:@"value = "];
        if (markerRange.location != NSNotFound) {
            NSUInteger start = markerRange.location + markerRange.length;
            NSUInteger end = start;
            while (end < description.length) {
                unichar character = [description characterAtIndex:end];
                if (![[NSCharacterSet decimalDigitCharacterSet] characterIsMember:character]) {
                    break;
                }
                end += 1;
            }
            if (end > start) {
                return @([[description substringWithRange:NSMakeRange(start, end - start)] integerValue]);
            }
        }
    }
    return nil;
}

+ (id)_swcDerefObject:(id)value objects:(NSArray *)objects {
    NSNumber *uidNumber = [self _swcObjectIndexFromReference:value];
    if (!uidNumber) {
        return value;
    }

    NSUInteger index = uidNumber.unsignedIntegerValue;
    if (index >= objects.count) {
        return nil;
    }
    id resolved = objects[index];
    return resolved == [NSNull null] ? nil : resolved;
}

+ (NSArray *)_swcCollectionReferencesFromValue:(id)value {
    if ([value isKindOfClass:[NSArray class]]) {
        return value;
    }
    if (![value isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    NSDictionary *dictionary = (NSDictionary *)value;
    if ([dictionary[@"NS.objects"] isKindOfClass:[NSArray class]]) {
        return dictionary[@"NS.objects"];
    }

    NSArray<NSString *> *orderedKeys = [[dictionary.allKeys filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary<NSString *, id> *bindings) {
        return [evaluatedObject isKindOfClass:[NSString class]] && [(NSString *)evaluatedObject hasPrefix:@"NS.object."];
    }]] sortedArrayUsingComparator:^NSComparisonResult(NSString *lhs, NSString *rhs) {
        NSInteger lhsIndex = [[lhs componentsSeparatedByString:@"."] lastObject].integerValue;
        NSInteger rhsIndex = [[rhs componentsSeparatedByString:@"."] lastObject].integerValue;
        if (lhsIndex < rhsIndex) {
            return NSOrderedAscending;
        }
        if (lhsIndex > rhsIndex) {
            return NSOrderedDescending;
        }
        return NSOrderedSame;
    }];
    if (orderedKeys.count == 0) {
        return nil;
    }

    NSMutableArray *result = [NSMutableArray arrayWithCapacity:orderedKeys.count];
    for (NSString *key in orderedKeys) {
        id object = dictionary[key];
        if (object) {
            [result addObject:object];
        }
    }
    return [result copy];
}

+ (id)_nestedPropertyListFromData:(NSData *)data {
    if (![data isKindOfClass:[NSData class]] || data.length == 0) {
        return nil;
    }
    NSError *error = nil;
    id value = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainersAndLeaves format:nil error:&error];
    if (!value || error) {
        return nil;
    }
    return value;
}

+ (NSArray<NSString *> *)_nulSeparatedUTF8PartsFromData:(NSData *)data skipFirstByte:(BOOL)skipFirstByte {
    if (![data isKindOfClass:[NSData class]] || data.length == 0) {
        return @[];
    }

    const uint8_t *bytes = data.bytes;
    NSUInteger start = skipFirstByte && data.length > 0 ? 1 : 0;
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSMutableData *segment = [NSMutableData data];
    for (NSUInteger index = start; index < data.length; index++) {
        uint8_t byte = bytes[index];
        if (byte == 0) {
            if (segment.length > 0) {
                NSString *part = [[NSString alloc] initWithData:segment encoding:NSUTF8StringEncoding];
                if (part.length > 0) {
                    [parts addObject:part];
                }
                [segment setLength:0];
            }
            continue;
        }
        [segment appendBytes:&byte length:1];
    }
    if (segment.length > 0) {
        NSString *part = [[NSString alloc] initWithData:segment encoding:NSUTF8StringEncoding];
        if (part.length > 0) {
            [parts addObject:part];
        }
    }
    return parts;
}

+ (NSArray<NSData *> *)_decodedPatternBlobsFromData:(NSData *)data {
    id nested = [self _nestedPropertyListFromData:data];
    if ([nested isKindOfClass:[NSData class]]) {
        return @[nested];
    }
    if (![nested isKindOfClass:[NSArray class]]) {
        return @[];
    }

    NSMutableArray<NSData *> *result = [NSMutableArray array];
    for (id item in (NSArray *)nested) {
        if ([item isKindOfClass:[NSData class]]) {
            [result addObject:item];
        } else if ([item isKindOfClass:[NSString class]]) {
            NSData *stringData = [(NSString *)item dataUsingEncoding:NSUTF8StringEncoding];
            if (stringData.length > 0) {
                [result addObject:stringData];
            }
        }
    }
    return result;
}

+ (NSDictionary<NSString *, NSArray<NSString *> *> *)_decodedSubstitutionVariablesFromData:(NSData *)data {
    id nested = [self _nestedPropertyListFromData:data];
    if (![nested isKindOfClass:[NSArray class]]) {
        return @{};
    }

    NSMutableDictionary<NSString *, NSArray<NSString *> *> *result = [NSMutableDictionary dictionary];
    for (id item in (NSArray *)nested) {
        if (![item isKindOfClass:[NSData class]]) {
            continue;
        }
        NSArray<NSString *> *parts = [self _nulSeparatedUTF8PartsFromData:item skipFirstByte:YES];
        if (parts.count < 2) {
            continue;
        }
        NSString *name = [self _normalizedRuleIDFromValue:parts.firstObject];
        if (name.length == 0) {
            continue;
        }
        NSMutableArray<NSString *> *values = [NSMutableArray array];
        for (NSUInteger index = 1; index < parts.count; index++) {
            NSString *value = [self _normalizedRuleIDFromValue:parts[index]];
            if (value.length > 0) {
                [values addObject:value];
            }
        }
        if (values.count > 0) {
            result[name] = [values copy];
        }
    }
    return result;
}

+ (NSString *)_bundleIDFromAppIdentifierValue:(id)value {
    NSString *rawValue = [self _normalizedBundleIDFromValue:value];
    if (rawValue.length == 0) {
        return nil;
    }
    NSRange firstDot = [rawValue rangeOfString:@"."];
    if (firstDot.location == NSNotFound || firstDot.location == rawValue.length - 1) {
        return rawValue;
    }
    NSString *prefix = [rawValue substringToIndex:firstDot.location];
    NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"] invertedSet];
    if (prefix.length >= 8 && [prefix rangeOfCharacterFromSet:invalid].location == NSNotFound) {
        return [rawValue substringFromIndex:firstDot.location + 1];
    }
    return rawValue;
}

+ (NSString *)_regexFragmentForTokenPattern:(NSString *)pattern
                                  variables:(NSDictionary<NSString *, NSArray<NSString *> *> *)variables
                                  supported:(BOOL *)supported
                               literalCount:(NSInteger *)literalCount {
    if (![pattern isKindOfClass:[NSString class]]) {
        if (supported) {
            *supported = NO;
        }
        if (literalCount) {
            *literalCount = 0;
        }
        return nil;
    }

    NSMutableString *regex = [NSMutableString string];
    NSInteger literal = 0;
    BOOL ok = YES;
    for (NSUInteger index = 0; index < pattern.length; ) {
        unichar ch = [pattern characterAtIndex:index];
        if (ch == '$' && index + 1 < pattern.length && [pattern characterAtIndex:index + 1] == '(') {
            NSRange closing = [pattern rangeOfString:@")" options:0 range:NSMakeRange(index + 2, pattern.length - index - 2)];
            if (closing.location == NSNotFound) {
                ok = NO;
                break;
            }
            NSString *name = [pattern substringWithRange:NSMakeRange(index + 2, closing.location - index - 2)];
            NSArray<NSString *> *values = variables[name];
            if (values.count > 0) {
                NSMutableArray<NSString *> *alternatives = [NSMutableArray array];
                for (NSString *value in values) {
                    BOOL altSupported = YES;
                    NSInteger altLiteral = 0;
                    NSString *altRegex = [self _regexFragmentForTokenPattern:value variables:@{} supported:&altSupported literalCount:&altLiteral];
                    if (!altSupported || altRegex.length == 0) {
                        altRegex = [NSRegularExpression escapedPatternForString:value];
                    }
                    [alternatives addObject:altRegex];
                }
                [regex appendFormat:@"(?:%@)", [alternatives componentsJoinedByString:@"|"]];
            } else {
                NSString *builtIn = DSBuiltInVariablePatterns()[name];
                if (builtIn.length == 0) {
                    ok = NO;
                    break;
                }
                [regex appendString:builtIn];
            }
            index = closing.location + 1;
            continue;
        }
        if (ch == '*') {
            [regex appendString:@".*"];
            index += 1;
            continue;
        }
        if (ch == '?') {
            [regex appendString:@"."];
            index += 1;
            continue;
        }

        NSString *piece = [pattern substringWithRange:NSMakeRange(index, 1)];
        [regex appendString:[NSRegularExpression escapedPatternForString:piece]];
        literal += 1;
        index += 1;
    }

    if (supported) {
        *supported = ok;
    }
    if (literalCount) {
        *literalCount = literal;
    }
    return ok ? regex : nil;
}

+ (NSRegularExpression *)_compiledRegexForTokenPattern:(NSString *)pattern
                                             variables:(NSDictionary<NSString *, NSArray<NSString *> *> *)variables
                                          literalCount:(NSInteger *)literalCount
                                             supported:(BOOL *)supported {
    BOOL fragmentSupported = YES;
    NSInteger localLiteralCount = 0;
    NSString *fragment = [self _regexFragmentForTokenPattern:pattern variables:variables supported:&fragmentSupported literalCount:&localLiteralCount];
    if (!fragmentSupported || fragment.length == 0) {
        if (supported) {
            *supported = NO;
        }
        if (literalCount) {
            *literalCount = 0;
        }
        return nil;
    }

    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"^%@$", fragment] options:0 error:&error];
    if (!regex || error) {
        if (supported) {
            *supported = NO;
        }
        if (literalCount) {
            *literalCount = 0;
        }
        return nil;
    }

    if (supported) {
        *supported = YES;
    }
    if (literalCount) {
        *literalCount = localLiteralCount;
    }
    return regex;
}

+ (NSArray<NSDictionary<NSString *, id> *> *)_compiledQueryRequirementsForMatcher:(NSString *)queryMatcher
                                                                        variables:(NSDictionary<NSString *, NSArray<NSString *> *> *)variables
                                                                     literalCount:(NSInteger *)literalCount
                                                                        supported:(BOOL *)supported {
    NSString *normalizedQueryMatcher = [self _normalizedQueryFromValue:queryMatcher];
    if (normalizedQueryMatcher.length == 0) {
        if (supported) {
            *supported = YES;
        }
        if (literalCount) {
            *literalCount = 0;
        }
        return @[];
    }

    NSMutableArray<NSDictionary<NSString *, NSString *> *> *pairs = [NSMutableArray array];
    NSError *jsonError = nil;
    NSRegularExpression *jsonRegex = [NSRegularExpression regularExpressionWithPattern:@"\\\"([^\\\"]+)\\\"\\s*:\\s*\\\"([^\\\"]*)\\\"" options:0 error:&jsonError];
    NSArray<NSTextCheckingResult *> *jsonMatches = jsonError ? @[] : [jsonRegex matchesInString:normalizedQueryMatcher options:0 range:NSMakeRange(0, normalizedQueryMatcher.length)];
    if (jsonMatches.count > 0) {
        for (NSTextCheckingResult *match in jsonMatches) {
            if (match.numberOfRanges < 3) {
                continue;
            }
            NSString *key = [normalizedQueryMatcher substringWithRange:[match rangeAtIndex:1]];
            NSString *value = [normalizedQueryMatcher substringWithRange:[match rangeAtIndex:2]];
            [pairs addObject:@{ @"key": key, @"value": value }];
        }
    } else {
        NSArray<NSString *> *components = [normalizedQueryMatcher componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"&," ]];
        for (NSString *component in components) {
            NSString *trimmed = [component stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (trimmed.length == 0) {
                continue;
            }
            NSRange equalsRange = [trimmed rangeOfString:@"="];
            NSString *key = equalsRange.location == NSNotFound ? trimmed : [trimmed substringToIndex:equalsRange.location];
            NSString *value = equalsRange.location == NSNotFound ? @"" : [trimmed substringFromIndex:equalsRange.location + 1];
            key = [key stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            value = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (key.length == 0) {
                continue;
            }
            [pairs addObject:@{ @"key": key, @"value": value }];
        }
    }

    if (pairs.count == 0) {
        if (supported) {
            *supported = NO;
        }
        if (literalCount) {
            *literalCount = 0;
        }
        return nil;
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *requirements = [NSMutableArray array];
    NSInteger totalLiteralCount = 0;
    for (NSDictionary<NSString *, NSString *> *pair in pairs) {
        NSString *key = [self _normalizedRuleIDFromValue:pair[@"key"]];
        NSString *valuePattern = pair[@"value"] ?: @"";
        if (key.length == 0) {
            continue;
        }

        BOOL regexSupported = YES;
        NSInteger valueLiteralCount = 0;
        NSRegularExpression *regex = [self _compiledRegexForTokenPattern:valuePattern variables:variables literalCount:&valueLiteralCount supported:&regexSupported];
        if (!regexSupported || !regex) {
            if (supported) {
                *supported = NO;
            }
            if (literalCount) {
                *literalCount = 0;
            }
            return nil;
        }
        [requirements addObject:@{
            @"key": key,
            @"matcher": valuePattern,
            @"regex": regex,
        }];
        totalLiteralCount += key.length + valueLiteralCount;
    }

    if (supported) {
        *supported = requirements.count > 0;
    }
    if (literalCount) {
        *literalCount = totalLiteralCount;
    }
    return [requirements copy];
}

+ (NSDictionary<NSString *, id> *)_compiledSystemRuleForHost:(NSString *)host
                                                hostWildcard:(BOOL)hostWildcard
                                          associatedBundleID:(NSString *)associatedBundleID
                                                 patternBlob:(NSData *)patternBlob
                                                   sortIndex:(NSInteger)sortIndex
                                                   variables:(NSDictionary<NSString *, NSArray<NSString *> *> *)variables {
    NSString *normalizedHost = [self _normalizedHostFromValue:host];
    NSString *normalizedAssociatedBundleID = [self _normalizedBundleIDFromValue:associatedBundleID];
    if (normalizedHost.length == 0 || normalizedAssociatedBundleID.length == 0 || ![patternBlob isKindOfClass:[NSData class]] || patternBlob.length == 0) {
        return nil;
    }

    const uint8_t *bytes = patternBlob.bytes;
    NSNumber *opcode = @(bytes[0]);
    NSArray<NSString *> *parts = [self _nulSeparatedUTF8PartsFromData:patternBlob skipFirstByte:YES];
    NSString *pathMatcher = nil;
    NSString *queryMatcher = nil;
    if (parts.count >= 1) {
        pathMatcher = parts[0];
    }
    if (parts.count >= 2) {
        queryMatcher = parts[1];
    }

    if (opcode.unsignedIntegerValue == 0x10) {
        queryMatcher = pathMatcher;
        pathMatcher = nil;
    }

    NSString *patternKind = kDSLinkRulePatternKindAny;
    if (pathMatcher.length > 0 && queryMatcher.length > 0) {
        patternKind = kDSLinkRulePatternKindPathQuery;
    } else if (queryMatcher.length > 0) {
        patternKind = kDSLinkRulePatternKindQuery;
    } else if (pathMatcher.length > 0) {
        patternKind = kDSLinkRulePatternKindPath;
    }

    NSInteger pathLiteralCount = 0;
    BOOL pathSupported = YES;
    NSRegularExpression *pathRegex = nil;
    NSString *normalizedPathMatcher = nil;
    if (pathMatcher.length > 0) {
        normalizedPathMatcher = [pathMatcher stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        pathRegex = [self _compiledRegexForTokenPattern:normalizedPathMatcher variables:variables literalCount:&pathLiteralCount supported:&pathSupported];
    }

    NSInteger queryLiteralCount = 0;
    BOOL querySupported = YES;
    NSArray<NSDictionary<NSString *, id> *> *queryRequirements = nil;
    if (queryMatcher.length > 0) {
        queryRequirements = [self _compiledQueryRequirementsForMatcher:queryMatcher variables:variables literalCount:&queryLiteralCount supported:&querySupported];
    }

    if ((normalizedPathMatcher.length > 0 && !pathSupported) || (queryMatcher.length > 0 && !querySupported)) {
        patternKind = kDSLinkRulePatternKindUnsupported;
    }

    NSString *rawPatternData = DSHexStringFromData(patternBlob);
    NSString *identity = [NSString stringWithFormat:@"v1|host=%@|wild=%d|bundle=%@|opcode=%@|path=%@|query=%@|blob=%@",
                          normalizedHost,
                          hostWildcard,
                          normalizedAssociatedBundleID,
                          opcode,
                          normalizedPathMatcher ?: @"",
                          queryMatcher ?: @"",
                          rawPatternData ?: @""];
    NSString *ruleID = DSSHA256String(identity);

    NSMutableDictionary<NSString *, id> *rule = [NSMutableDictionary dictionaryWithDictionary:@{
        kDSLinkRuleRuleIDKey: ruleID,
        kDSLinkRuleIdentityVersionKey: kDSLinkRuleIdentityVersion,
        kDSLinkRuleHostKey: normalizedHost,
        kDSLinkRuleHostWildcardKey: @(hostWildcard),
        kDSLinkRuleAssociatedBundleIDKey: normalizedAssociatedBundleID,
        kDSLinkRuleSourceHintKey: kDSSWCSourceHint,
        kDSLinkRulePatternKindKey: patternKind,
        kDSLinkRuleRawOpcodeKey: opcode,
        kDSLinkRuleRawPatternDataKey: rawPatternData ?: @"",
        kDSRuleLiteralScoreKey: @(pathLiteralCount + queryLiteralCount),
        kDSRuleSortIndexKey: @(sortIndex),
    }];
    if (normalizedPathMatcher.length > 0) {
        rule[kDSLinkRulePathMatcherKey] = normalizedPathMatcher;
    }
    if (queryMatcher.length > 0) {
        rule[kDSLinkRuleQueryMatcherKey] = queryMatcher;
    }
    if (pathRegex) {
        rule[kDSCompiledPathRegexKey] = pathRegex;
    }
    if (queryRequirements.count > 0) {
        rule[kDSCompiledQueryRequirementsKey] = queryRequirements;
    }
    return rule;
}

+ (NSDictionary<NSString *, id> *)_parsedSharedWebCredentialsSnapshotForData:(NSData *)data
                                                                        path:(NSString *)path
                                                                    fileSize:(unsigned long long)fileSize
                                                                    fileMTime:(NSDate *)fileMTime {
    NSMutableDictionary<NSString *, id> *snapshot = [NSMutableDictionary dictionaryWithDictionary:@{
        kDSSWCSnapshotGeneratedAtKey: [NSDate date],
    }];
    if (path.length > 0) {
        snapshot[kDSSWCSnapshotPathKey] = path;
    }
    snapshot[kDSSWCSnapshotFileSizeKey] = @(fileSize);
    if (fileMTime) {
        snapshot[kDSSWCSnapshotFileMTimeKey] = fileMTime;
    }

    if (![data isKindOfClass:[NSData class]] || data.length == 0) {
        snapshot[kDSSWCSnapshotRulesKey] = @[];
        snapshot[kDSSWCSnapshotErrorKey] = @"swc.db is empty";
        return snapshot;
    }

    NSError *plistError = nil;
    id plist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainersAndLeaves format:nil error:&plistError];
    if (![plist isKindOfClass:[NSDictionary class]]) {
        snapshot[kDSSWCSnapshotRulesKey] = @[];
        snapshot[kDSSWCSnapshotErrorKey] = plistError.localizedDescription ?: @"failed to decode swc archive";
        return snapshot;
    }

    NSDictionary *archive = (NSDictionary *)plist;
    NSArray *objects = [archive[@"$objects"] isKindOfClass:[NSArray class]] ? archive[@"$objects"] : nil;
    NSDictionary *top = [archive[@"$top"] isKindOfClass:[NSDictionary class]] ? archive[@"$top"] : nil;
    if (objects.count == 0 || top.count == 0) {
        snapshot[kDSSWCSnapshotRulesKey] = @[];
        snapshot[kDSSWCSnapshotErrorKey] = @"swc archive missing $objects/$top";
        return snapshot;
    }

    id root = [self _swcDerefObject:top[@"root"] objects:objects];
    if (![root isKindOfClass:[NSDictionary class]]) {
        snapshot[kDSSWCSnapshotRulesKey] = @[];
        snapshot[kDSSWCSnapshotErrorKey] = @"swc archive root is invalid";
        return snapshot;
    }

    id entriesValue = [self _swcDerefObject:((NSDictionary *)root)[@"entries"] objects:objects];
    NSArray *entryReferences = [self _swcCollectionReferencesFromValue:entriesValue];
    if (entryReferences.count == 0) {
        snapshot[kDSSWCSnapshotRulesKey] = @[];
        snapshot[kDSSWCSnapshotErrorKey] = @"swc archive entries are missing";
        return snapshot;
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *rules = [NSMutableArray array];
    NSInteger sortIndex = 0;
    for (id entryRef in entryReferences) {
        NSDictionary *entry = [self _swcDerefObject:entryRef objects:objects];
        if (![entry isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSString *service = [self _normalizedRuleIDFromValue:[self _swcDerefObject:entry[@"service"] objects:objects]];
        if (![service isEqualToString:@"applinks"]) {
            continue;
        }

        NSDictionary *domain = [self _swcDerefObject:entry[@"domain"] objects:objects];
        if (![domain isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSString *host = [self _normalizedHostFromValue:[self _swcDerefObject:domain[@"host"] objects:objects]];
        BOOL hostWildcard = [self _normalizedBoolFromValue:[self _swcDerefObject:domain[@"wildcard"] objects:objects] defaultValue:NO];
        NSDictionary *appID = [self _swcDerefObject:entry[@"appID"] objects:objects];
        if (![appID isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSString *associatedBundleID = [self _bundleIDFromAppIdentifierValue:[self _swcDerefObject:appID[@"rawValue"] objects:objects]];
        if (host.length == 0 || associatedBundleID.length == 0) {
            continue;
        }

        NSDictionary *patternList = [self _swcDerefObject:entry[@"patternList"] objects:objects];
        if (![patternList isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSData *patternData = [self _swcDerefObject:patternList[@"patternData"] objects:objects];
        NSArray<NSData *> *patternBlobs = [self _decodedPatternBlobsFromData:patternData];
        if (patternBlobs.count == 0) {
            continue;
        }

        NSDictionary *substitutionList = [self _swcDerefObject:entry[@"substitutionVariableList"] objects:objects];
        NSData *substitutionData = [substitutionList isKindOfClass:[NSDictionary class]] ? [self _swcDerefObject:substitutionList[@"substitutionVariableData"] objects:objects] : nil;
        NSDictionary<NSString *, NSArray<NSString *> *> *variables = [self _decodedSubstitutionVariablesFromData:substitutionData];

        for (NSData *patternBlob in patternBlobs) {
            NSDictionary<NSString *, id> *rule = [self _compiledSystemRuleForHost:host
                                                                     hostWildcard:hostWildcard
                                                               associatedBundleID:associatedBundleID
                                                                      patternBlob:patternBlob
                                                                        sortIndex:sortIndex
                                                                        variables:variables];
            sortIndex += 1;
            if (rule) {
                [rules addObject:rule];
            }
        }
    }

    snapshot[kDSSWCSnapshotRulesKey] = [rules copy];
    return snapshot;
}

+ (NSString *)resolvedSharedWebCredentialsDatabasePath {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *bestPath = nil;
    NSDate *bestDate = nil;

    for (NSString *root in [self sharedWebCredentialsRootCandidates]) {
        BOOL isDirectory = NO;
        if (![fileManager fileExistsAtPath:root isDirectory:&isDirectory] || !isDirectory) {
            continue;
        }

        NSError *listError = nil;
        NSArray<NSString *> *children = [fileManager contentsOfDirectoryAtPath:root error:&listError];
        if (children.count == 0 || listError) {
            continue;
        }

        for (NSString *child in children) {
            NSString *candidate = [[root stringByAppendingPathComponent:child] stringByAppendingPathComponent:kDSSWCRelativeDatabasePath];
            NSDictionary<NSFileAttributeKey, id> *attributes = [fileManager attributesOfItemAtPath:candidate error:nil];
            if (![attributes[NSFileType] isEqual:NSFileTypeRegular]) {
                continue;
            }
            NSDate *modifiedAt = attributes[NSFileModificationDate];
            if (!bestPath || !bestDate || [modifiedAt compare:bestDate] == NSOrderedDescending) {
                bestPath = candidate;
                bestDate = modifiedAt;
            }
        }
    }

    return bestPath;
}

+ (NSDictionary<NSString *, id> *)sharedWebCredentialsSnapshot {
    NSString *path = [self resolvedSharedWebCredentialsDatabasePath];
    if (path.length == 0) {
        return @{ kDSSWCSnapshotRulesKey: @[], kDSSWCSnapshotErrorKey: @"unable to locate swc.db" };
    }

    NSError *attributesError = nil;
    NSDictionary<NSFileAttributeKey, id> *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:&attributesError];
    unsigned long long fileSize = [attributes fileSize];
    NSDate *fileMTime = attributes[NSFileModificationDate];
    NSTimeInterval mtimeValue = fileMTime.timeIntervalSince1970;

    @synchronized (self) {
        if (gDSSWCSnapshotCache &&
            [gDSSWCSnapshotCachePath isEqualToString:path] &&
            gDSSWCSnapshotCacheSize == fileSize &&
            fabs(gDSSWCSnapshotCacheMTime - mtimeValue) < DBL_EPSILON) {
            return gDSSWCSnapshotCache;
        }
    }

    NSError *readError = nil;
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:&readError];
    NSDictionary<NSString *, id> *snapshot = nil;
    if (data.length > 0 && !readError) {
        snapshot = [self _parsedSharedWebCredentialsSnapshotForData:data path:path fileSize:fileSize fileMTime:fileMTime];
    } else {
        snapshot = @{
            kDSSWCSnapshotPathKey: path,
            kDSSWCSnapshotRulesKey: @[],
            kDSSWCSnapshotFileSizeKey: @(fileSize),
            kDSSWCSnapshotGeneratedAtKey: [NSDate date],
            kDSSWCSnapshotErrorKey: readError.localizedDescription ?: @"failed to read swc.db",
        };
        if (fileMTime) {
            NSMutableDictionary *mutableSnapshot = [snapshot mutableCopy];
            mutableSnapshot[kDSSWCSnapshotFileMTimeKey] = fileMTime;
            snapshot = [mutableSnapshot copy];
        }
    }

    @synchronized (self) {
        gDSSWCSnapshotCache = snapshot;
        gDSSWCSnapshotCachePath = [path copy];
        gDSSWCSnapshotCacheSize = fileSize;
        gDSSWCSnapshotCacheMTime = mtimeValue;
    }
    return snapshot;
}

+ (NSArray<NSDictionary<NSString *, id> *> *)systemLinkRules {
    return [self systemLinkRulesFromSnapshot:[self sharedWebCredentialsSnapshot]];
}

+ (NSArray<NSDictionary<NSString *, id> *> *)systemLinkRulesFromSnapshot:(NSDictionary<NSString *, id> *)snapshot {
    if (![snapshot[kDSSWCSnapshotRulesKey] isKindOfClass:[NSArray class]]) {
        return @[];
    }
    return snapshot[kDSSWCSnapshotRulesKey];
}

+ (NSString *)_normalizedURLPath:(NSURL *)url {
    if (![url isKindOfClass:[NSURL class]]) {
        return @"/";
    }
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSString *path = components.path;
    if (path.length == 0) {
        path = url.path ?: @"";
    }
    if (path.length == 0) {
        return @"/";
    }
    return path;
}

+ (BOOL)_host:(NSString *)urlHost matchesRuleHost:(NSString *)ruleHost wildcard:(BOOL)wildcard {
    if (ruleHost.length == 0 || urlHost.length == 0) {
        return NO;
    }
    if ([ruleHost isEqualToString:urlHost]) {
        return YES;
    }
    if (!wildcard) {
        return NO;
    }
    NSString *suffix = [@"." stringByAppendingString:ruleHost];
    return [urlHost hasSuffix:suffix];
}

+ (NSDictionary<NSString *, NSArray<NSString *> *> *)_queryItemsMapForURL:(NSURL *)url {
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *result = [NSMutableDictionary dictionary];
    for (NSURLQueryItem *item in components.queryItems) {
        if (![item.name isKindOfClass:[NSString class]] || item.name.length == 0) {
            continue;
        }
        NSMutableArray<NSString *> *values = result[item.name];
        if (!values) {
            values = [NSMutableArray array];
            result[item.name] = values;
        }
        [values addObject:item.value ?: @""];
    }
    return result;
}

+ (NSInteger)matchScoreForSystemLinkRule:(NSDictionary<NSString *, id> *)rule URL:(NSURL *)url {
    if (![rule isKindOfClass:[NSDictionary class]] || ![url isKindOfClass:[NSURL class]]) {
        return NSNotFound;
    }

    NSString *ruleHost = [self _normalizedHostFromValue:rule[kDSLinkRuleHostKey]];
    NSString *urlHost = [self _normalizedHostFromValue:url.host];
    BOOL hostWildcard = [self _normalizedBoolFromValue:rule[kDSLinkRuleHostWildcardKey] defaultValue:NO];
    if (![self _host:urlHost matchesRuleHost:ruleHost wildcard:hostWildcard]) {
        return NSNotFound;
    }

    NSString *patternKind = rule[kDSLinkRulePatternKindKey];
    if ([patternKind isEqualToString:kDSLinkRulePatternKindUnsupported]) {
        return NSNotFound;
    }

    NSString *pathMatcher = rule[kDSLinkRulePathMatcherKey];
    if (pathMatcher.length > 0) {
        NSRegularExpression *pathRegex = rule[kDSCompiledPathRegexKey];
        if (![pathRegex isKindOfClass:[NSRegularExpression class]]) {
            return NSNotFound;
        }
        NSString *path = [self _normalizedURLPath:url];
        if ([pathRegex firstMatchInString:path options:0 range:NSMakeRange(0, path.length)] == nil) {
            return NSNotFound;
        }
    }

    NSArray<NSDictionary<NSString *, id> *> *queryRequirements = rule[kDSCompiledQueryRequirementsKey];
    if ([queryRequirements isKindOfClass:[NSArray class]] && queryRequirements.count > 0) {
        NSDictionary<NSString *, NSArray<NSString *> *> *queryItems = [self _queryItemsMapForURL:url];
        for (NSDictionary<NSString *, id> *requirement in queryRequirements) {
            NSString *key = requirement[@"key"];
            NSRegularExpression *regex = requirement[@"regex"];
            NSArray<NSString *> *values = queryItems[key];
            if (key.length == 0 || ![regex isKindOfClass:[NSRegularExpression class]] || values.count == 0) {
                return NSNotFound;
            }
            BOOL matched = NO;
            for (NSString *value in values) {
                NSString *candidate = value ?: @"";
                if ([regex firstMatchInString:candidate options:0 range:NSMakeRange(0, candidate.length)] != nil) {
                    matched = YES;
                    break;
                }
            }
            if (!matched) {
                return NSNotFound;
            }
        }
    }

    NSInteger literalScore = [rule[kDSRuleLiteralScoreKey] respondsToSelector:@selector(integerValue)] ? [rule[kDSRuleLiteralScoreKey] integerValue] : 0;
    NSInteger score = hostWildcard ? 300000000 : 400000000;
    if (queryRequirements.count > 0) {
        score += 10000000;
    }
    if (pathMatcher.length > 0) {
        score += 1000000;
    }
    score += literalScore * 100;
    score += queryRequirements.count * 10;
    return score;
}

+ (NSDictionary<NSString *, id> *)bestSystemLinkRuleForURL:(NSURL *)url {
    return [self bestSystemLinkRuleForURL:url fromRules:[self systemLinkRules]];
}

+ (NSDictionary<NSString *, id> *)bestSystemLinkRuleForURL:(NSURL *)url fromRules:(NSArray<NSDictionary<NSString *, id> *> *)rules {
    NSDictionary<NSString *, id> *bestRule = nil;
    NSInteger bestScore = NSNotFound;
    NSInteger bestSortIndex = NSIntegerMax;

    for (NSDictionary<NSString *, id> *rule in rules) {
        NSInteger score = [self matchScoreForSystemLinkRule:rule URL:url];
        if (score == NSNotFound) {
            continue;
        }
        NSInteger sortIndex = [rule[kDSRuleSortIndexKey] respondsToSelector:@selector(integerValue)] ? [rule[kDSRuleSortIndexKey] integerValue] : NSIntegerMax;
        if (!bestRule || score > bestScore || (score == bestScore && sortIndex < bestSortIndex)) {
            bestRule = rule;
            bestScore = score;
            bestSortIndex = sortIndex;
        }
    }
    return bestRule;
}

+ (NSDictionary<NSString *, id> *)normalizedOpenLogEntryFromValue:(id)value {
    if (![value isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    NSString *urlString = [self _normalizedSourceHintFromValue:value[kDSOpenLogURLKey]];
    NSString *targetBundleID = [self _normalizedBundleIDFromValue:value[kDSOpenLogTargetBundleIDKey]];
    if (urlString.length == 0 || targetBundleID.length == 0) {
        return nil;
    }

    NSTimeInterval timestamp = [self _normalizedTimestampFromValue:value[kDSOpenLogTimestampKey]];
    if (timestamp <= 0) {
        timestamp = NSDate.date.timeIntervalSince1970;
    }

    NSMutableDictionary<NSString *, id> *result = [NSMutableDictionary dictionaryWithDictionary:@{
        kDSOpenLogTimestampKey: @(timestamp),
        kDSOpenLogURLKey: urlString,
        kDSOpenLogTypeKey: [self _normalizedOpenLogTypeFromValue:value[kDSOpenLogTypeKey] URLString:urlString],
        kDSOpenLogTargetBundleIDKey: targetBundleID,
    }];

    NSString *sourceBundleID = [self _normalizedBundleIDFromValue:value[kDSOpenLogSourceBundleIDKey]];
    if (sourceBundleID.length > 0) {
        result[kDSOpenLogSourceBundleIDKey] = sourceBundleID;
    }

    NSString *sourceName = [self _normalizedOpenLogNameFromValue:value[kDSOpenLogSourceNameKey]];
    if (sourceName.length > 0) {
        result[kDSOpenLogSourceNameKey] = sourceName;
    }

    NSString *targetName = [self _normalizedOpenLogNameFromValue:value[kDSOpenLogTargetNameKey]];
    if (targetName.length > 0) {
        result[kDSOpenLogTargetNameKey] = targetName;
    }

    NSString *hookSource = [self _normalizedSourceHintFromValue:value[kDSOpenLogHookSourceKey]];
    if (hookSource.length > 0) {
        result[kDSOpenLogHookSourceKey] = hookSource;
    }

    return result;
}

+ (NSArray<NSDictionary<NSString *, id> *> *)openLogs {
    CFStringRef appID = (__bridge CFStringRef)kDSRoutingConfigDomain;
    id value = CFBridgingRelease(CFPreferencesCopyValue((__bridge CFStringRef)kDSRoutingOpenLogsKey,
                                                        appID,
                                                        kCFPreferencesCurrentUser,
                                                        kCFPreferencesAnyHost));
    if (![value isKindOfClass:[NSArray class]]) {
        return @[];
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *result = [NSMutableArray array];
    for (id item in (NSArray *)value) {
        NSDictionary<NSString *, id> *entry = [self normalizedOpenLogEntryFromValue:item];
        if (entry) {
            [result addObject:entry];
        }
    }
    return [result copy];
}

+ (BOOL)_saveOpenLogsToPreferences:(NSArray<NSDictionary<NSString *, id> *> *)logs {
    CFStringRef appID = (__bridge CFStringRef)kDSRoutingConfigDomain;
    CFPreferencesSetValue((__bridge CFStringRef)kDSRoutingOpenLogsKey,
                          logs.count > 0 ? (__bridge CFArrayRef)logs : NULL,
                          appID,
                          kCFPreferencesCurrentUser,
                          kCFPreferencesAnyHost);
    return CFPreferencesSynchronize(appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}

+ (int)_acquireOpenLogLockWithError:(NSError **)error {
    NSString *lockPath = kDSOpenLogLockPath;
    NSString *directory = [lockPath stringByDeletingLastPathComponent];
    NSFileManager *fileManager = NSFileManager.defaultManager;
    if (directory.length > 0 && ![fileManager fileExistsAtPath:directory]) {
        NSError *mkdirError = nil;
        if (![fileManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&mkdirError]) {
            if (error) {
                *error = mkdirError;
            }
            return -1;
        }
    }

    int fd = open(lockPath.fileSystemRepresentation, O_CREAT | O_RDWR, 0644);
    if (fd < 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"DefaultScheme"
                                         code:8
                                     userInfo:@{ NSLocalizedDescriptionKey: @"Failed to open open-log lock file." }];
        }
        return -1;
    }

    if (flock(fd, LOCK_EX) != 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"DefaultScheme"
                                         code:9
                                     userInfo:@{ NSLocalizedDescriptionKey: @"Failed to lock open-log storage." }];
        }
        close(fd);
        return -1;
    }
    return fd;
}

+ (void)_releaseOpenLogLock:(int)fd {
    if (fd < 0) {
        return;
    }
    flock(fd, LOCK_UN);
    close(fd);
}

+ (BOOL)clearOpenLogs:(NSError **)error {
    int lockFD = [self _acquireOpenLogLockWithError:error];
    if (lockFD < 0) {
        return NO;
    }
    BOOL success = [self _saveOpenLogsToPreferences:@[]];
    [self _releaseOpenLogLock:lockFD];
    if (success) {
        return YES;
    }

    if (error) {
        *error = [NSError errorWithDomain:@"DefaultScheme" code:5 userInfo:@{
            NSLocalizedDescriptionKey: @"Failed to clear open logs."
        }];
    }
    return NO;
}

+ (BOOL)appendOpenLogEntry:(NSDictionary<NSString *, id> *)entry limit:(NSUInteger)limit error:(NSError **)error {
    NSDictionary<NSString *, id> *normalizedEntry = [self normalizedOpenLogEntryFromValue:entry];
    if (!normalizedEntry) {
        if (error) {
            *error = [NSError errorWithDomain:@"DefaultScheme" code:3 userInfo:@{
                NSLocalizedDescriptionKey: @"Invalid open log entry."
            }];
        }
        return NO;
    }

    int lockFD = [self _acquireOpenLogLockWithError:error];
    if (lockFD < 0) {
        return NO;
    }

    NSUInteger effectiveLimit = limit > 0 ? limit : kDSRoutingOpenLogsDefaultLimit;
    NSMutableArray<NSDictionary<NSString *, id> *> *logs = [[self openLogs] mutableCopy] ?: [NSMutableArray array];
    NSInteger duplicateIndex = [self _recentDuplicateIndexForOpenLogEntry:normalizedEntry inLogs:logs];
    if (duplicateIndex != NSNotFound) {
        NSDictionary<NSString *, id> *preferredEntry = [self _preferredOpenLogEntryBetweenExisting:logs[(NSUInteger)duplicateIndex] incoming:normalizedEntry];
        logs[(NSUInteger)duplicateIndex] = preferredEntry;
    } else {
        [logs addObject:normalizedEntry];
    }
    if (logs.count > effectiveLimit) {
        [logs removeObjectsInRange:NSMakeRange(0, logs.count - effectiveLimit)];
    }

    if ([self _saveOpenLogsToPreferences:[logs copy]]) {
        [self _releaseOpenLogLock:lockFD];
        return YES;
    }

    [self _releaseOpenLogLock:lockFD];

    if (error) {
        *error = [NSError errorWithDomain:@"DefaultScheme" code:4 userInfo:@{
            NSLocalizedDescriptionKey: @"Failed to save open logs."
        }];
    }
    return NO;
}

+ (BOOL)_saveConfigToPreferences:(NSDictionary *)config {
    CFStringRef appID = (__bridge CFStringRef)kDSRoutingConfigDomain;
    NSDictionary *schemes = [config[kDSRoutingSchemesKey] isKindOfClass:[NSDictionary class]] ? config[kDSRoutingSchemesKey] : nil;
    NSDictionary *hosts = [config[kDSRoutingHostsKey] isKindOfClass:[NSDictionary class]] ? config[kDSRoutingHostsKey] : nil;
    NSArray *links = [config[kDSRoutingLinksKey] isKindOfClass:[NSArray class]] ? config[kDSRoutingLinksKey] : nil;
    BOOL openLogRecordsMatchedOnly = [self openLogRecordsMatchedOnlyFromConfig:config];

    CFPreferencesSetValue((__bridge CFStringRef)kDSRoutingSchemesKey,
                          schemes ? (__bridge CFDictionaryRef)schemes : NULL,
                          appID,
                          kCFPreferencesCurrentUser,
                          kCFPreferencesAnyHost);
    CFPreferencesSetValue((__bridge CFStringRef)kDSRoutingHostsKey,
                          hosts ? (__bridge CFDictionaryRef)hosts : NULL,
                          appID,
                          kCFPreferencesCurrentUser,
                          kCFPreferencesAnyHost);
    CFPreferencesSetValue((__bridge CFStringRef)kDSRoutingLinksKey,
                          links ? (__bridge CFArrayRef)links : NULL,
                          appID,
                          kCFPreferencesCurrentUser,
                          kCFPreferencesAnyHost);
    CFPreferencesSetValue((__bridge CFStringRef)kDSOpenLogRecordMatchedOnlyKey,
                          openLogRecordsMatchedOnly ? kCFBooleanTrue : NULL,
                          appID,
                          kCFPreferencesCurrentUser,
                          kCFPreferencesAnyHost);
    return CFPreferencesSynchronize(appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}

+ (BOOL)saveConfig:(NSDictionary *)config error:(NSError **)error {
    NSMutableDictionary *safeConfig = [config isKindOfClass:[NSDictionary class]] ? [config mutableCopy] : [NSMutableDictionary dictionary];

    NSDictionary *schemes = [self schemeRulesFromConfig:safeConfig];
    if (schemes.count > 0) {
        safeConfig[kDSRoutingSchemesKey] = schemes;
    } else {
        [safeConfig removeObjectForKey:kDSRoutingSchemesKey];
    }

    NSDictionary *hosts = [self hostRulesFromConfig:safeConfig];
    if (hosts.count > 0) {
        safeConfig[kDSRoutingHostsKey] = hosts;
    } else {
        [safeConfig removeObjectForKey:kDSRoutingHostsKey];
    }

    NSArray *normalizedLinks = [self linkRulesFromConfig:safeConfig];
    NSMutableArray<NSDictionary<NSString *, id> *> *persistentLinks = [NSMutableArray arrayWithCapacity:normalizedLinks.count];
    for (NSDictionary<NSString *, id> *rule in normalizedLinks) {
        NSDictionary<NSString *, id> *persistentRule = [self _persistentLinkRuleFromValue:rule];
        if (persistentRule) {
            [persistentLinks addObject:persistentRule];
        }
    }
    if (persistentLinks.count > 0) {
        safeConfig[kDSRoutingLinksKey] = persistentLinks;
    } else {
        [safeConfig removeObjectForKey:kDSRoutingLinksKey];
    }

    if ([self openLogRecordsMatchedOnlyFromConfig:safeConfig]) {
        safeConfig[kDSOpenLogRecordMatchedOnlyKey] = @YES;
    } else {
        [safeConfig removeObjectForKey:kDSOpenLogRecordMatchedOnlyKey];
    }

    if ([self _saveConfigToPreferences:safeConfig]) {
        [self _postRouteConfigChangedNotification];
        return YES;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *serializationError = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:safeConfig
                                                              format:NSPropertyListXMLFormat_v1_0
                                                             options:0
                                                               error:&serializationError];
    if (!data) {
        if (error) {
            *error = serializationError ?: [NSError errorWithDomain:@"DefaultScheme" code:2 userInfo:@{
                NSLocalizedDescriptionKey: @"Failed to serialize config file."
            }];
        }
        return NO;
    }

    NSError *lastError = nil;
    BOOL wroteAny = NO;
    for (NSString *path in [self configPathCandidates]) {
        NSString *dir = [path stringByDeletingLastPathComponent];
        if (![fm fileExistsAtPath:dir]) {
            NSError *mkdirError = nil;
            if (![fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&mkdirError]) {
                lastError = mkdirError;
                continue;
            }
        }
        NSError *writeError = nil;
        if ([data writeToFile:path options:0 error:&writeError]) {
            wroteAny = YES;
            continue;
        }
        lastError = writeError;
    }

    if (wroteAny) {
        [self _postRouteConfigChangedNotification];
        return YES;
    }

    if (error) {
        *error = lastError ?: [NSError errorWithDomain:@"DefaultScheme" code:1 userInfo:@{
            NSLocalizedDescriptionKey: @"Failed to write config file."
        }];
    }
    return NO;
}

@end
