#import "DSHookModules.h"
#import "DSApplicationSupport.h"
#import "DSOpenActionHandler.h"
#import "DSObjectExtraction.h"
#import "DSOpenLogging.h"
#import "DSPrivateInterfaces.h"
#import "DSRouteSupport.h"
#import "DSTweakCommon.h"
#import <objc/message.h>
#import <objc/runtime.h>

static id DSApplicationRecordForBundleID(NSString *bundleID) {
    if (bundleID.length == 0 || DSIsNoAppRule(bundleID)) return nil;
    Class recordClass = objc_getClass("LSApplicationRecord");
    SEL initSel = @selector(initWithBundleIdentifier:allowPlaceholder:error:);
    if (!recordClass || ![recordClass instancesRespondToSelector:initSel]) return nil;

    NSError *error = nil;
    id record = nil;
    @try {
        record = ((id (*)(id, SEL, NSString *, BOOL, NSError **))objc_msgSend)([recordClass alloc], initSel, bundleID, YES, &error);
    } @catch (__unused NSException *exception) {
        record = nil;
    }
    if (!record) {
        DSLog(@"LSAppLink failed to create LSApplicationRecord %@ error=%@", bundleID, error.localizedDescription ?: @"unknown");
    }
    return record;
}

static NSString *DSConfiguredBundleIDForAppLinkObject(id appLink) {
    NSURL *url = DSExtractURLFromAppLink(appLink);
    return DSConfiguredBundleIDForURL(url);
}

static NSString *DSConfiguredBundleIDForAppLinkState(id state) {
    NSURL *url = DSLaunchServicesURLFromObject(state);
    return DSConfiguredBundleIDForURL(url);
}

static NSString *DSObservedBundleIDForAppLinkObject(id appLink) {
    if (!appLink) {
        return nil;
    }
    if ([appLink respondsToSelector:@selector(targetApplicationProxy)]) {
        @try {
            id proxy = ((id (*)(id, SEL))objc_msgSend)(appLink, @selector(targetApplicationProxy));
            NSString *bundleID = DSBundleIdentifierForProxy(proxy);
            if (bundleID.length > 0) {
                return bundleID;
            }
        } @catch (__unused NSException *exception) {}
    }
    if ([appLink respondsToSelector:@selector(targetApplicationRecord)]) {
        @try {
            id record = ((id (*)(id, SEL))objc_msgSend)(appLink, @selector(targetApplicationRecord));
            NSString *bundleID = DSBundleIdentifierForProxy(record);
            if (bundleID.length > 0) {
                return bundleID;
            }
        } @catch (__unused NSException *exception) {}
    }
    return nil;
}

static id DSWorkspaceApplicationForURL(NSURL *url) {
    if (!url) {
        return nil;
    }
    id workspaceClass = objc_getClass("LSApplicationWorkspace");
    id workspace = [workspaceClass respondsToSelector:@selector(defaultWorkspace)] ? [workspaceClass defaultWorkspace] : nil;
    if (workspace && [workspace respondsToSelector:@selector(applicationForOpeningResource:)]) {
        @try {
            return [workspace applicationForOpeningResource:url];
        } @catch (__unused NSException *exception) {}
    }
    return nil;
}

static BOOL DSCompleteBlockedOpenWithCompletion(id completion) {
    if (!completion) {
        return YES;
    }
    @try {
        void (^block)(BOOL, NSError *) = completion;
        block(NO, DSDefaultSchemeBlockedError());
        return YES;
    } @catch (__unused NSException *e) {}
    return YES;
}

static DSOpenActionDecision *DSAppLinkDecision(NSString *source,
                                               NSURL *url,
                                               NSDictionary<NSString *, NSString *> *sourceInfo,
                                               NSString *observedBundleID) {
    return DSHandleOpenURLAction(source, url, sourceInfo, observedBundleID);
}

%group LSAppLinkHooks

%hook LSAppLink

- (void)openWithCompletionHandler:(id)completion {
    NSURL *url = DSExtractURLFromAppLink(self);
    if (!url) {
        DSLog(@"LSAppLink -openWithCompletionHandler: NO URL extracted, falling through");
    }
    NSDictionary<NSString *, NSString *> *sourceInfo = DSSourceApplicationInfoFromObjects(self, nil, nil, nil);
    DSOpenActionDecision *decision = DSHandleOpenURLAction(@"LSAppLink -openWithCompletionHandler",
                                                           url,
                                                           sourceInfo,
                                                           DSObservedBundleIDForAppLinkObject(self));
    if (decision.blocked) {
        DSLog(@"LSAppLink -openWithCompletionHandler: blocked %@", url.absoluteString ?: @"");
        if (completion) {
            @try {
                void (^block)(BOOL, NSError *) = completion;
                block(NO, DSDefaultSchemeBlockedError());
            } @catch (__unused NSException *e) {}
        }
        return;
    }
    %orig(completion);
}

- (id)targetApplicationProxy {
    NSString *bundleID = DSConfiguredBundleIDForAppLinkObject(self);
    if (bundleID.length > 0 && !DSIsNoAppRule(bundleID)) {
        id proxy = DSInstalledApplicationProxyForBundleID(bundleID);
        if (proxy) {
            DSLog(@"LSAppLink targetApplicationProxy -> %@", bundleID);
            return proxy;
        }
    }
    return %orig;
}

- (id)targetApplicationRecord {
    NSString *bundleID = DSConfiguredBundleIDForAppLinkObject(self);
    if (bundleID.length > 0 && !DSIsNoAppRule(bundleID)) {
        id record = DSApplicationRecordForBundleID(bundleID);
        if (record) {
            DSLog(@"LSAppLink targetApplicationRecord -> %@", bundleID);
            return record;
        }
    }
    return %orig;
}

+ (void)openWithURL:(NSURL *)url completionHandler:(id)completion {
    DSOpenActionDecision *decision = DSHandleOpenURLAction(@"LSAppLink +openWithURL:",
                                                           url,
                                                           nil,
                                                           DSBundleIdentifierForProxy(DSWorkspaceApplicationForURL(url)));
    if (decision.blocked) {
        DSLog(@"LSAppLink +openWithURL: blocked %@", url.absoluteString ?: @"");
        DSCompleteBlockedOpenWithCompletion(completion);
        return;
    }
    %orig(url, completion);
}

+ (void)openWithURL:(NSURL *)url configuration:(id)config completionHandler:(id)completion {
    NSDictionary<NSString *, NSString *> *sourceInfo = DSSourceApplicationInfoFromObjects(config, nil, nil, nil);
    DSOpenActionDecision *decision = DSAppLinkDecision(@"LSAppLink +openWithURL:config:",
                                                       url,
                                                       sourceInfo,
                                                       DSBundleIdentifierForProxy(DSWorkspaceApplicationForURL(url)));
    if (decision.blocked) {
        DSLog(@"LSAppLink +openWithURL:config: blocked %@", url.absoluteString ?: @"");
        DSCompleteBlockedOpenWithCompletion(completion);
        return;
    }
    %orig(url, config, completion);
}

- (void)openWithConfiguration:(id)config completionHandler:(id)completion {
    NSURL *url = DSExtractURLFromAppLink(self);
    if (!url) {
        DSLog(@"LSAppLink -openWithConfiguration: NO URL extracted, falling through");
    }
    NSDictionary<NSString *, NSString *> *sourceInfo = DSSourceApplicationInfoFromObjects(config, self, nil, nil);
    DSOpenActionDecision *decision = DSAppLinkDecision(@"LSAppLink -openWithConfiguration:",
                                                       url,
                                                       sourceInfo,
                                                       DSObservedBundleIDForAppLinkObject(self));
    if (decision.blocked) {
        DSLog(@"LSAppLink -openWithConfiguration: blocked %@", url.absoluteString ?: @"");
        DSCompleteBlockedOpenWithCompletion(completion);
        return;
    }
    %orig(config, completion);
}

+ (void)_openWithAppLink:(LSAppLink *)appLink state:(id)state completionHandler:(id)completion {
    NSURL *url = DSExtractURLFromAppLink(appLink);
    if (!url) {
        DSLog(@"LSAppLink +_openWithAppLink: NO URL extracted, falling through");
    }
    NSDictionary<NSString *, NSString *> *sourceInfo = DSSourceApplicationInfoFromObjects(state, appLink, nil, nil);
    DSOpenActionDecision *decision = DSAppLinkDecision(@"LSAppLink +_openWithAppLink:",
                                                       url,
                                                       sourceInfo,
                                                       DSObservedBundleIDForAppLinkObject(appLink));
    if (decision.blocked) {
        DSLog(@"LSAppLink +_openWithAppLink: blocked %@", url.absoluteString ?: @"");
        DSCompleteBlockedOpenWithCompletion(completion);
        return;
    }
    %orig(appLink, state, completion);
}

+ (void)_openAppLink:(LSAppLink *)appLink state:(id)state completionHandler:(id)completion {
    NSURL *url = DSExtractURLFromAppLink(appLink);
    if (!url) {
        DSLog(@"LSAppLink +_openAppLink: NO URL extracted, falling through");
    }
    NSDictionary<NSString *, NSString *> *sourceInfo = DSSourceApplicationInfoFromObjects(state, appLink, nil, nil);
    DSOpenActionDecision *decision = DSAppLinkDecision(@"LSAppLink +_openAppLink:",
                                                       url,
                                                       sourceInfo,
                                                       DSObservedBundleIDForAppLinkObject(appLink));
    if (decision.blocked) {
        DSLog(@"LSAppLink +_openAppLink: blocked %@", url.absoluteString ?: @"");
        DSCompleteBlockedOpenWithCompletion(completion);
        return;
    }
    %orig(appLink, state, completion);
}

%end
%end

%group LSAppLinkOpenStateHooks

%hook _LSAppLinkOpenState

- (NSString *)bundleIdentifier {
    NSString *bundleID = DSConfiguredBundleIDForAppLinkState(self);
    if (bundleID.length > 0 && !DSIsNoAppRule(bundleID)) {
        DSLog(@"_LSAppLinkOpenState bundleIdentifier -> %@", bundleID);
        return bundleID;
    }
    return %orig;
}

%end
%end

void DSInitLSAppLinkHooks(Class lsAppLinkClass) {
    %init(LSAppLinkHooks, LSAppLink=lsAppLinkClass);
    Class stateClass = objc_getClass("_LSAppLinkOpenState");
    if (stateClass) {
        %init(LSAppLinkOpenStateHooks, _LSAppLinkOpenState=stateClass);
    }
}
