#import "DSRouteSupport.h"
#import "DSApplicationSupport.h"
#import "DSTweakCommon.h"
#import "DSPrivateInterfaces.h"
#import "../Shared/DSRoutingConfig.h"
#import <objc/message.h>
#import <objc/runtime.h>

@interface DSRouteSnapshot : NSObject
@property (nonatomic, copy) NSDictionary *config;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *schemeRules;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *hostRules;
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *linkRules;
@property (nonatomic, copy) NSDictionary<NSString *, NSArray<NSDictionary<NSString *, id> *> *> *exactLinkRulesByHost;
@property (nonatomic, copy) NSDictionary<NSString *, NSArray<NSDictionary<NSString *, id> *> *> *wildcardLinkRulesByHostSuffix;
@property (nonatomic, assign) NSUInteger generation;
@end

@implementation DSRouteSnapshot
@end

static DSRouteSnapshot *DSCachedRouteSnapshot;
static BOOL DSRouteSnapshotDirty = YES;

static NSString *DSNormalizedRouteHost(id value) {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *host = [[(NSString *)value lowercaseString] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return host.length > 0 ? host : nil;
}

static NSDictionary<NSString *, NSArray<NSDictionary<NSString *, id> *> *> *DSCopyRouteRuleBuckets(NSDictionary<NSString *, NSMutableArray<NSDictionary<NSString *, id> *> *> *buckets) {
    NSMutableDictionary<NSString *, NSArray<NSDictionary<NSString *, id> *> *> *result = [NSMutableDictionary dictionaryWithCapacity:buckets.count];
    [buckets enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSMutableArray<NSDictionary<NSString *, id> *> *rules, BOOL *stop) {
        result[key] = [rules copy];
    }];
    return [result copy];
}

static void DSAddRouteRuleToBucket(NSMutableDictionary<NSString *, NSMutableArray<NSDictionary<NSString *, id> *> *> *buckets,
                                   NSString *host,
                                   NSDictionary<NSString *, id> *rule) {
    if (host.length == 0 || ![rule isKindOfClass:NSDictionary.class]) return;
    NSMutableArray<NSDictionary<NSString *, id> *> *rules = buckets[host];
    if (!rules) {
        rules = [NSMutableArray array];
        buckets[host] = rules;
    }
    [rules addObject:rule];
}

static void DSRouteConfigChangedCallback(CFNotificationCenterRef center,
                                         void *observer,
                                         CFStringRef name,
                                         const void *object,
                                         CFDictionaryRef userInfo) {
    @synchronized (DSRoutingConfig.class) {
        DSRouteSnapshotDirty = YES;
    }
}

static void DSRegisterRouteConfigInvalidation(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        DSRouteConfigChangedCallback,
                                        (__bridge CFStringRef)kDSRoutingConfigChangedNotification,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    });
}

static DSRouteSnapshot *DSBuildRouteSnapshot(NSUInteger generation) {
    NSDictionary *config = [DSRoutingConfig loadConfig] ?: @{};
    NSDictionary<NSString *, NSString *> *schemeRules = [DSRoutingConfig schemeRulesFromConfig:config] ?: @{};
    NSDictionary<NSString *, NSString *> *hostRules = [DSRoutingConfig hostRulesFromConfig:config] ?: @{};
    NSArray<NSDictionary<NSString *, id> *> *linkRules = [DSRoutingConfig linkRulesFromConfig:config] ?: @[];

    NSMutableDictionary<NSString *, NSMutableArray<NSDictionary<NSString *, id> *> *> *exactBuckets = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSMutableArray<NSDictionary<NSString *, id> *> *> *wildcardBuckets = [NSMutableDictionary dictionary];
    for (NSDictionary<NSString *, id> *rule in linkRules) {
        NSString *host = DSNormalizedRouteHost(rule[kDSLinkRuleHostKey]);
        if (host.length == 0) continue;
        BOOL hostWildcard = [rule[kDSLinkRuleHostWildcardKey] respondsToSelector:@selector(boolValue)] ? [rule[kDSLinkRuleHostWildcardKey] boolValue] : NO;
        DSAddRouteRuleToBucket(hostWildcard ? wildcardBuckets : exactBuckets, host, rule);
    }

    DSRouteSnapshot *snapshot = [DSRouteSnapshot new];
    snapshot.config = config;
    snapshot.schemeRules = schemeRules;
    snapshot.hostRules = hostRules;
    snapshot.linkRules = linkRules;
    snapshot.exactLinkRulesByHost = DSCopyRouteRuleBuckets(exactBuckets);
    snapshot.wildcardLinkRulesByHostSuffix = DSCopyRouteRuleBuckets(wildcardBuckets);
    snapshot.generation = generation;
    return snapshot;
}

static DSRouteSnapshot *DSRouteSnapshotForCurrentConfig(void) {
    DSRegisterRouteConfigInvalidation();
    @synchronized (DSRoutingConfig.class) {
        if (DSCachedRouteSnapshot && !DSRouteSnapshotDirty) {
            return DSCachedRouteSnapshot;
        }

        NSUInteger generation = DSCachedRouteSnapshot.generation + 1;
        DSCachedRouteSnapshot = DSBuildRouteSnapshot(generation);
        DSRouteSnapshotDirty = NO;
        DSLog(@"route snapshot rebuilt generation=%lu schemes=%lu hosts=%lu links=%lu exactHosts=%lu wildcardHosts=%lu",
              (unsigned long)DSCachedRouteSnapshot.generation,
              (unsigned long)DSCachedRouteSnapshot.schemeRules.count,
              (unsigned long)DSCachedRouteSnapshot.hostRules.count,
              (unsigned long)DSCachedRouteSnapshot.linkRules.count,
              (unsigned long)DSCachedRouteSnapshot.exactLinkRulesByHost.count,
              (unsigned long)DSCachedRouteSnapshot.wildcardLinkRulesByHostSuffix.count);
        return DSCachedRouteSnapshot;
    }
}

static void DSAddRouteCandidates(NSMutableArray<NSDictionary<NSString *, id> *> *candidates,
                                 NSMutableSet<NSValue *> *seenRules,
                                 NSArray<NSDictionary<NSString *, id> *> *rules) {
    for (NSDictionary<NSString *, id> *rule in rules) {
        NSValue *identity = [NSValue valueWithNonretainedObject:rule];
        if ([seenRules containsObject:identity]) continue;
        [seenRules addObject:identity];
        [candidates addObject:rule];
    }
}

static NSArray<NSDictionary<NSString *, id> *> *DSIndexedLinkRuleCandidatesForURL(NSURL *url, DSRouteSnapshot *snapshot) {
    NSString *host = DSNormalizedRouteHost(url.host);
    if (host.length == 0 || !snapshot) return @[];

    NSMutableArray<NSDictionary<NSString *, id> *> *candidates = [NSMutableArray array];
    NSMutableSet<NSValue *> *seenRules = [NSMutableSet set];
    DSAddRouteCandidates(candidates, seenRules, snapshot.exactLinkRulesByHost[host]);

    NSString *suffix = host;
    while (suffix.length > 0) {
        DSAddRouteCandidates(candidates, seenRules, snapshot.wildcardLinkRulesByHostSuffix[suffix]);
        NSRange dotRange = [suffix rangeOfString:@"."];
        if (dotRange.location == NSNotFound || dotRange.location + 1 >= suffix.length) {
            break;
        }
        suffix = [suffix substringFromIndex:dotRange.location + 1];
    }
    return [candidates copy];
}

NSDictionary<NSString *, id> *DSBestConfiguredLinkRuleForURL(NSURL *url, NSDictionary *config) {
    if (![url isKindOfClass:NSURL.class] || ![config isKindOfClass:NSDictionary.class]) {
        return nil;
    }
    return [DSRoutingConfig bestSystemLinkRuleForURL:url fromRules:[DSRoutingConfig linkRulesFromConfig:config]];
}

NSString *DSConfiguredBundleIDForURL(NSURL *url) {
    if (![url isKindOfClass:NSURL.class]) return nil;

    DSRouteSnapshot *snapshot = DSRouteSnapshotForCurrentConfig();
    NSString *scheme = url.scheme.lowercaseString;
    NSString *schemeBundleID = scheme.length > 0 ? snapshot.schemeRules[scheme] : nil;
    if (schemeBundleID.length > 0) {
        DSLog(@"config lookup matched scheme=%@ -> %@", scheme, schemeBundleID);
        return schemeBundleID;
    }

    NSArray<NSDictionary<NSString *, id> *> *linkCandidates = DSIndexedLinkRuleCandidatesForURL(url, snapshot);
    NSDictionary<NSString *, id> *bestLinkRule = [DSRoutingConfig bestSystemLinkRuleForURL:url fromRules:linkCandidates];
    NSString *linkBundleID = bestLinkRule[kDSLinkRuleBundleIDKey];
    if (linkBundleID.length > 0) {
        NSString *ruleHost = bestLinkRule[kDSLinkRuleHostKey] ?: @"";
        NSString *pathMatcher = bestLinkRule[kDSLinkRulePathMatcherKey] ?: [DSRoutingConfig pathMatcherStringForLinkRule:bestLinkRule] ?: @"";
        NSString *queryMatcher = bestLinkRule[kDSLinkRuleQueryMatcherKey] ?: @"";
        NSString *ruleID = bestLinkRule[kDSLinkRuleRuleIDKey] ?: @"";
        NSString *patternKind = bestLinkRule[kDSLinkRulePatternKindKey] ?: @"";
        BOOL hostWildcard = [bestLinkRule[kDSLinkRuleHostWildcardKey] respondsToSelector:@selector(boolValue)] ? [bestLinkRule[kDSLinkRuleHostWildcardKey] boolValue] : NO;
        DSLog(@"config lookup matched link ruleID=%@ host=%@%@ path=%@ query=%@ kind=%@ candidates=%lu -> %@",
              ruleID,
              hostWildcard ? @"*." : @"",
              ruleHost,
              pathMatcher.length > 0 ? pathMatcher : @"<any>",
              queryMatcher.length > 0 ? queryMatcher : @"<any>",
              patternKind.length > 0 ? patternKind : @"unknown",
              (unsigned long)linkCandidates.count,
              linkBundleID);
        return linkBundleID;
    }

    NSString *host = DSNormalizedRouteHost(url.host);
    NSString *hostBundleID = host.length > 0 ? snapshot.hostRules[host] : nil;
    if (hostBundleID.length > 0) {
        DSLog(@"config lookup matched host=%@ -> %@", host, hostBundleID);
        return hostBundleID;
    }

    return nil;
}


NSString *DSConfiguredBundleIDForScheme(NSString *scheme) {
    if (![scheme isKindOfClass:NSString.class] || scheme.length == 0) return nil;
    DSRouteSnapshot *snapshot = DSRouteSnapshotForCurrentConfig();
    return snapshot.schemeRules[scheme.lowercaseString];
}

BOOL DSIsWebURL(NSURL *url);
id DSInstalledApplicationProxyForBundleID(NSString *bundleID);

BOOL DSIsWebURL(NSURL *url) {
    if (![url isKindOfClass:NSURL.class]) return NO;
    NSString *scheme = url.scheme.lowercaseString;
    return [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"];
}

id DSInstalledApplicationProxyForBundleID(NSString *bundleID) {
    if (bundleID.length == 0 || DSIsNoAppRule(bundleID)) return nil;

    Class proxyClass = objc_getClass("LSApplicationProxy");
    SEL proxySel = @selector(applicationProxyForIdentifier:);
    if (proxyClass && [proxyClass respondsToSelector:proxySel]) {
        id proxy = nil;
        @try {
            proxy = ((id (*)(id, SEL, NSString *))objc_msgSend)(proxyClass, proxySel, bundleID);
        } @catch (__unused NSException *exception) {
            proxy = nil;
        }
        if ([DSBundleIdentifierForProxy(proxy) isEqualToString:bundleID]) {
            return proxy;
        }
    }

    Class wsClass = objc_getClass("LSApplicationWorkspace");
    if (!wsClass) return nil;
    SEL sharedSel = @selector(defaultWorkspace);
    if (![wsClass respondsToSelector:sharedSel]) return nil;
    id ws = ((id (*)(id, SEL))objc_msgSend)(wsClass, sharedSel);
    SEL allAppsSel = @selector(allInstalledApplications);
    if (!ws || ![ws respondsToSelector:allAppsSel]) return nil;

    NSArray *applications = nil;
    @try {
        applications = ((id (*)(id, SEL))objc_msgSend)(ws, allAppsSel);
    } @catch (__unused NSException *exception) {
        applications = nil;
    }

    for (id application in applications) {
        NSString *candidateBundleID = DSBundleIdentifierForProxy(application);
        if ([candidateBundleID isEqualToString:bundleID]) {
            return application;
        }
    }
    return nil;
}

id DSApplicationProxyForURL(NSURL *url, NSString *bundleID) {
    if (![url isKindOfClass:NSURL.class] || bundleID.length == 0 || DSIsNoAppRule(bundleID)) return nil;

    Class wsClass = objc_getClass("LSApplicationWorkspace");
    if (!wsClass) return nil;
    SEL sharedSel = @selector(defaultWorkspace);
    if (![wsClass respondsToSelector:sharedSel]) return nil;
    id ws = ((id (*)(id, SEL))objc_msgSend)(wsClass, sharedSel);
    SEL candidatesSel = @selector(applicationsAvailableForOpeningURL:);
    if (!ws || ![ws respondsToSelector:candidatesSel]) return nil;

    NSArray *candidates = nil;
    @try {
        candidates = ((id (*)(id, SEL, NSURL *))objc_msgSend)(ws, candidatesSel, url);
    } @catch (__unused NSException *exception) {
        candidates = nil;
    }

    for (id candidate in candidates) {
        NSString *candidateBundleID = DSBundleIdentifierForProxy(candidate);
        if ([candidateBundleID isEqualToString:bundleID]) return candidate;
    }

    if (DSIsWebURL(url)) {
        id installedApplication = DSInstalledApplicationProxyForBundleID(bundleID);
        if (installedApplication) {
            DSLog(@"installed-app fallback %@ for %@", bundleID, url.absoluteString ?: @"");
            return installedApplication;
        }
    }

    return nil;
}

BOOL DSConfiguredBundleIsAvailableForURL(NSURL *url) {
    NSString *bundleID = DSConfiguredBundleIDForURL(url);
    if (bundleID.length == 0 || DSIsNoAppRule(bundleID)) return NO;
    return DSApplicationProxyForURL(url, bundleID) != nil;
}
