#import "DSOpenActionHandler.h"

#import "DSApplicationSupport.h"
#import "DSOpenLogging.h"
#import "DSRouteSupport.h"
#import "DSTweakCommon.h"

@implementation DSOpenActionDecision
@end

DSOpenActionDecision *DSHandleOpenURLAction(NSString *hookSource,
                                            NSURL *url,
                                            NSDictionary<NSString *, NSString *> *sourceInfo,
                                            NSString *observedBundleID) {
    return DSHandleOpenURLActionWithConfiguredBundleID(hookSource,
                                                       url,
                                                       sourceInfo,
                                                       observedBundleID,
                                                       DSConfiguredBundleIDForURL(url));
}

DSOpenActionDecision *DSHandleOpenURLActionWithConfiguredBundleID(NSString *hookSource,
                                                                  NSURL *url,
                                                                  NSDictionary<NSString *, NSString *> *sourceInfo,
                                                                  NSString *observedBundleID,
                                                                  NSString *configuredBundleID) {
    if (![url isKindOfClass:NSURL.class] || url.absoluteString.length == 0) {
        return nil;
    }

    if (configuredBundleID.length > 0) {
        DSOpenActionDecision *decision = [DSOpenActionDecision new];
        decision.hookSource = hookSource ?: @"open";
        decision.url = url;
        decision.targetBundleID = configuredBundleID;
        decision.sourceInfo = sourceInfo;
        decision.matchedRule = YES;
        decision.blocked = DSIsNoAppRule(configuredBundleID);
        if (decision.blocked) {
            DSAppendObservedOpenLogEntry(decision.hookSource, url, configuredBundleID, sourceInfo, YES);
        } else {
            DSLogDeferredURLPreservingOpenWithSourceInfo(decision.hookSource, url, configuredBundleID, sourceInfo);
        }
        return decision;
    }

    if (!DSShouldRecordMatchedOpensOnly() && observedBundleID.length > 0 && !DSIsNoAppRule(observedBundleID)) {
        DSOpenActionDecision *decision = [DSOpenActionDecision new];
        decision.hookSource = hookSource ?: @"open";
        decision.url = url;
        decision.targetBundleID = observedBundleID;
        decision.sourceInfo = sourceInfo;
        decision.matchedRule = NO;
        decision.blocked = NO;
        DSAppendObservedOpenLogEntry(decision.hookSource, url, observedBundleID, sourceInfo, NO);
        return decision;
    }

    return nil;
}

NSError *DSDefaultSchemeBlockedError(void) {
    return [NSError errorWithDomain:@"DefaultScheme"
                               code:-1
                           userInfo:@{ NSLocalizedDescriptionKey: @"URL blocked by DefaultScheme" }];
}

NSError *DSDefaultSchemeUnavailableError(void) {
    return [NSError errorWithDomain:@"DefaultScheme"
                               code:-2
                           userInfo:@{ NSLocalizedDescriptionKey: @"Configured app unavailable for URL" }];
}

BOOL DSConfiguredOpenURLTargetIsAvailable(NSString *source,
                                          NSURL *url,
                                          NSString *configuredBundleID,
                                          NSError **error) {
    if (configuredBundleID.length == 0) {
        return NO;
    }
    if (DSIsNoAppRule(configuredBundleID)) {
        if (error) {
            *error = DSDefaultSchemeBlockedError();
        }
        DSLog(@"%@ blocked %@", source ?: @"open", url.absoluteString ?: @"");
        return NO;
    }

    BOOL available = DSConfiguredBundleIsAvailableForURL(url);
    if (!available && error) {
        *error = DSDefaultSchemeUnavailableError();
    }
    DSLog(@"%@ %@ -> %@ available=%@",
          source ?: @"open",
          url.absoluteString ?: @"",
          configuredBundleID,
          available ? @"YES" : @"NO");
    return available;
}

id DSPreferredApplicationForConfiguredOpenURL(NSString *source,
                                              NSURL *url,
                                              NSString *configuredBundleID) {
    if (configuredBundleID.length == 0) {
        return nil;
    }
    if (DSIsNoAppRule(configuredBundleID)) {
        DSLog(@"%@ blocked %@", source ?: @"open", url.absoluteString ?: @"");
        return nil;
    }

    id preferredApplication = DSApplicationProxyForURL(url, configuredBundleID);
    if (preferredApplication) {
        DSLog(@"%@ %@ -> %@", source ?: @"open", url.absoluteString ?: @"", configuredBundleID);
        return preferredApplication;
    }

    DSLog(@"%@ target %@ missing for %@", source ?: @"open", configuredBundleID, url.absoluteString ?: @"");
    return nil;
}

id DSResolvedApplicationForOpenActionDecision(DSOpenActionDecision *decision,
                                              id fallbackApplication,
                                              NSString *source) {
    if (!decision || decision.blocked || decision.targetBundleID.length == 0 || DSIsNoAppRule(decision.targetBundleID)) {
        return fallbackApplication;
    }

    NSString *currentBundleID = DSBundleIdentifierForProxy(fallbackApplication);
    if ([currentBundleID isEqualToString:decision.targetBundleID]) {
        return fallbackApplication;
    }

    id configuredApplication = DSApplicationProxyForURL(decision.url, decision.targetBundleID);
    if (configuredApplication) {
        DSLog(@"%@ replacing application %@ -> %@ for %@",
              source ?: decision.hookSource ?: @"open",
              currentBundleID.length > 0 ? currentBundleID : @"<nil>",
              decision.targetBundleID,
              decision.url.absoluteString ?: @"");
        return configuredApplication;
    }

    DSLog(@"%@ target %@ unavailable; keeping application %@ for %@",
          source ?: decision.hookSource ?: @"open",
          decision.targetBundleID,
          currentBundleID.length > 0 ? currentBundleID : @"<nil>",
          decision.url.absoluteString ?: @"");
    return fallbackApplication;
}
