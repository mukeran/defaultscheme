#import "DSHookModules.h"
#import "DSApplicationSupport.h"
#import "DSOpenActionHandler.h"
#import "DSObjectExtraction.h"
#import "DSOpenLogging.h"
#import "DSPrivateInterfaces.h"
#import "DSRouteSupport.h"
#import "DSTweakCommon.h"

static NSString *DSPendingLSDOpenSourceInfoKey = @"sourceInfo";
static NSString *DSPendingLSDOpenSourceTimeKey = @"createdAt";
static const NSTimeInterval kDSPendingLSDOpenSourceMaxAge = 5.0;

static NSMutableDictionary<NSString *, NSDictionary<NSString *, id> *> *DSPendingLSDOpenSources(void) {
    static NSMutableDictionary<NSString *, NSDictionary<NSString *, id> *> *sources;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sources = [NSMutableDictionary dictionary];
    });
    return sources;
}

static NSString *DSPendingLSDOpenSourceKey(NSURL *url, NSString *bundleID) {
    NSString *urlString = url.absoluteString;
    if (urlString.length == 0 || bundleID.length == 0) return nil;
    return [NSString stringWithFormat:@"%@\n%@", urlString, bundleID];
}

static void DSPurgeExpiredPendingLSDOpenSources(NSMutableDictionary<NSString *, NSDictionary<NSString *, id> *> *sources, NSTimeInterval now) {
    NSMutableArray<NSString *> *expiredKeys = [NSMutableArray array];
    [sources enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSDictionary<NSString *, id> *entry, BOOL *stop) {
        NSTimeInterval createdAt = [entry[DSPendingLSDOpenSourceTimeKey] respondsToSelector:@selector(doubleValue)] ? [entry[DSPendingLSDOpenSourceTimeKey] doubleValue] : 0;
        if (createdAt <= 0 || now - createdAt > kDSPendingLSDOpenSourceMaxAge) {
            [expiredKeys addObject:key];
        }
    }];
    [sources removeObjectsForKeys:expiredKeys];
}

static void DSStorePendingLSDOpenSource(NSURL *url, NSString *bundleID, NSDictionary<NSString *, NSString *> *sourceInfo) {
    NSString *key = DSPendingLSDOpenSourceKey(url, bundleID);
    if (key.length == 0 || sourceInfo.count == 0) return;

    @synchronized (DSPendingLSDOpenSources()) {
        NSTimeInterval now = NSDate.date.timeIntervalSinceReferenceDate;
        NSMutableDictionary<NSString *, NSDictionary<NSString *, id> *> *sources = DSPendingLSDOpenSources();
        DSPurgeExpiredPendingLSDOpenSources(sources, now);
        sources[key] = @{
            DSPendingLSDOpenSourceInfoKey: sourceInfo,
            DSPendingLSDOpenSourceTimeKey: @(now),
        };
    }
}

static NSDictionary<NSString *, NSString *> *DSConsumePendingLSDOpenSource(NSURL *url, NSString *bundleID) {
    NSString *key = DSPendingLSDOpenSourceKey(url, bundleID);
    if (key.length == 0) return nil;

    @synchronized (DSPendingLSDOpenSources()) {
        NSTimeInterval now = NSDate.date.timeIntervalSinceReferenceDate;
        NSMutableDictionary<NSString *, NSDictionary<NSString *, id> *> *sources = DSPendingLSDOpenSources();
        DSPurgeExpiredPendingLSDOpenSources(sources, now);
        NSDictionary<NSString *, id> *entry = sources[key];
        [sources removeObjectForKey:key];
        NSDictionary<NSString *, NSString *> *sourceInfo = entry[DSPendingLSDOpenSourceInfoKey];
        return [sourceInfo isKindOfClass:NSDictionary.class] ? sourceInfo : nil;
    }
}

static BOOL DSLSDOpenClientHandleBlockedDecision(DSOpenActionDecision *decision, id completion) {
    if (!decision.blocked) {
        return NO;
    }
    if (completion) {
        @try {
            void (^block)(BOOL, NSError *) = completion;
            block(NO, DSDefaultSchemeBlockedError());
        } @catch (__unused NSException *e) {}
    }
    return YES;
}

%group LSDOpenClientHooks

%hook _LSDOpenClient

- (void)getURLOverrideForURL:(NSURL *)url completionHandler:(id)completion {
    NSString *bundleID = DSConfiguredBundleIDForURL(url);
    if (bundleID.length > 0) {
        if (DSIsNoAppRule(bundleID)) {
            DSLog(@"_LSDOpenClient getURLOverride blocked %@", url.absoluteString ?: @"");
            if (completion) {
                @try {
                    void (^block)(id, NSError *) = completion;
                    block(nil, DSDefaultSchemeBlockedError());
                } @catch (__unused NSException *e) {}
            }
            return;
        }

        id preferredApplication = DSPreferredApplicationForConfiguredOpenURL(@"_LSDOpenClient getURLOverride", url, bundleID);
        if (preferredApplication) {
            if (completion) {
                @try {
                    void (^block)(id, NSError *) = completion;
                    block(preferredApplication, nil);
                } @catch (__unused NSException *e) {}
            }
            return;
        }

        if (completion) {
            @try {
                void (^block)(id, NSError *) = completion;
                block(nil, DSDefaultSchemeUnavailableError());
            } @catch (__unused NSException *e) {}
        }
        return;
    }
    %orig(url, completion);
}

- (void)canOpenURL:(NSURL *)url publicSchemes:(BOOL)publicSchemes privateSchemes:(BOOL)privateSchemes completionHandler:(id)completion {
    NSString *bundleID = DSConfiguredBundleIDForURL(url);
    if (bundleID.length > 0) {
        NSError *callbackError = nil;
        BOOL available = DSConfiguredOpenURLTargetIsAvailable(@"_LSDOpenClient canOpenURL", url, bundleID, &callbackError);
        DSLog(@"_LSDOpenClient canOpenURL public=%@ private=%@",
              publicSchemes ? @"YES" : @"NO",
              privateSchemes ? @"YES" : @"NO");
        if (completion) {
            @try {
                void (^block)(BOOL, NSError *) = completion;
                block(available, callbackError);
            } @catch (__unused NSException *e) {}
        }
        return;
    }
    %orig(url, publicSchemes, privateSchemes, completion);
}

- (void)openApplicationWithIdentifier:(NSString *)identifier options:(id)options useClientProcessHandle:(BOOL)useClientProcessHandle completionHandler:(id)completion {
    NSURL *url = DSExtractURLFromOpenApplicationRequest(options, nil, nil);
    NSString *configuredBundleID = DSConfiguredBundleIDForURL(url);
    if (configuredBundleID.length > 0) {
        if (DSIsNoAppRule(configuredBundleID)) {
            DSLog(@"_LSDOpenClient openApplicationWithIdentifier blocked %@ requested=%@", url.absoluteString ?: @"", identifier ?: @"");
            if (completion) {
                @try {
                    void (^block)(BOOL, NSError *) = completion;
                    block(NO, DSDefaultSchemeBlockedError());
                } @catch (__unused NSException *e) {}
            }
            return;
        }
        DSLog(@"_LSDOpenClient openApplicationWithIdentifier %@ requested=%@ -> %@", url.absoluteString ?: @"", identifier ?: @"", configuredBundleID);
        %orig(configuredBundleID, options, useClientProcessHandle, completion);
        return;
    }
    %orig(identifier, options, useClientProcessHandle, completion);
}

- (void)openURL:(NSURL *)url options:(id)options completionHandler:(id)completion {
    NSString *configuredBundleID = DSConfiguredBundleIDForURL(url);
    NSDictionary<NSString *, NSString *> *sourceInfo = DSSourceApplicationInfoFromObjects(options, self, nil, nil);
    DSOpenActionDecision *decision = DSHandleOpenURLActionWithConfiguredBundleID(@"_LSDOpenClient openURL",
                                                                                 url,
                                                                                 sourceInfo,
                                                                                 nil,
                                                                                 configuredBundleID);
    if (DSLSDOpenClientHandleBlockedDecision(decision, completion)) {
        DSLog(@"_LSDOpenClient openURL blocked %@", url.absoluteString ?: @"");
        return;
    }
    if (decision.matchedRule && decision.targetBundleID.length > 0) {
        DSStorePendingLSDOpenSource(url, decision.targetBundleID, sourceInfo);
        if (DSIsWebURL(url)) {
            DSLog(@"_LSDOpenClient openURL forcing performOpenOperation %@ -> %@", url.absoluteString ?: @"", decision.targetBundleID);
            [self performOpenOperationWithURL:url bundleIdentifier:decision.targetBundleID documentIdentifier:nil isContentManaged:NO sourceAuditToken:NULL userInfo:nil options:options delegate:nil completionHandler:completion];
            return;
        }
        DSLog(@"_LSDOpenClient openURL preserving original scheme path %@ -> %@", url.absoluteString ?: @"", decision.targetBundleID);
    }
    %orig(url, options, completion);
}

- (void)openAppLink:(id)appLink state:(id)state completionHandler:(id)completion {
    NSURL *url = DSExtractURLFromAppLink(appLink);
    NSString *configuredBundleID = DSConfiguredBundleIDForURL(url);
    NSDictionary<NSString *, NSString *> *sourceInfo = DSSourceApplicationInfoFromObjects(state, appLink, self, nil);
    DSOpenActionDecision *decision = DSHandleOpenURLActionWithConfiguredBundleID(@"_LSDOpenClient openAppLink",
                                                                                 url,
                                                                                 sourceInfo,
                                                                                 nil,
                                                                                 configuredBundleID);
    if (DSLSDOpenClientHandleBlockedDecision(decision, completion)) {
        DSLog(@"_LSDOpenClient openAppLink blocked %@", url.absoluteString ?: @"");
        return;
    }
    if (decision.matchedRule && decision.targetBundleID.length > 0) {
        DSStorePendingLSDOpenSource(url, decision.targetBundleID, sourceInfo);
        DSLog(@"_LSDOpenClient openAppLink forcing performOpenOperation %@ -> %@", url.absoluteString ?: @"", decision.targetBundleID);
        [self performOpenOperationWithURL:url bundleIdentifier:decision.targetBundleID documentIdentifier:nil isContentManaged:NO sourceAuditToken:NULL userInfo:state options:nil delegate:nil completionHandler:completion];
        return;
    }
    %orig(appLink, state, completion);
}

- (void)performOpenOperationWithURL:(NSURL *)url bundleIdentifier:(NSString *)bundleIdentifier documentIdentifier:(id)documentIdentifier isContentManaged:(BOOL)isContentManaged sourceAuditToken:(const void *)sourceAuditToken userInfo:(id)userInfo options:(id)options delegate:(id)delegate completionHandler:(id)completion {
    NSString *configuredBundleID = DSConfiguredBundleIDForURL(url);
    NSDictionary<NSString *, NSString *> *objectSourceInfo = DSSourceApplicationInfoFromObjects(userInfo, options, delegate, self);
    NSDictionary<NSString *, NSString *> *pendingSourceInfo = DSConsumePendingLSDOpenSource(url, configuredBundleID.length > 0 ? configuredBundleID : bundleIdentifier);
    NSDictionary<NSString *, NSString *> *sourceInfo = DSMergedApplicationInfo(DSApplicationInfoFromAuditToken(sourceAuditToken),
                                                                               DSMergedApplicationInfo(objectSourceInfo, pendingSourceInfo));
    DSOpenActionDecision *decision = DSHandleOpenURLActionWithConfiguredBundleID(@"_LSDOpenClient performOpenOperation",
                                                                                 url,
                                                                                 sourceInfo,
                                                                                 bundleIdentifier,
                                                                                 configuredBundleID);
    if (DSLSDOpenClientHandleBlockedDecision(decision, completion)) {
        DSLog(@"_LSDOpenClient performOpenOperation blocked %@ requested=%@", url.absoluteString ?: @"", bundleIdentifier ?: @"");
        return;
    }
    if (decision.matchedRule && decision.targetBundleID.length > 0) {
        DSLog(@"_LSDOpenClient performOpenOperation %@ requested=%@ -> %@", url.absoluteString ?: @"", bundleIdentifier ?: @"", configuredBundleID);
        %orig(url, decision.targetBundleID, documentIdentifier, isContentManaged, sourceAuditToken, userInfo, options, delegate, completion);
        return;
    }
    %orig(url, bundleIdentifier, documentIdentifier, isContentManaged, sourceAuditToken, userInfo, options, delegate, completion);
}

%end
%end


void DSInitLSDOpenClientHooks(Class lsdOpenClientClass) {
    %init(LSDOpenClientHooks, _LSDOpenClient=lsdOpenClientClass);
}
