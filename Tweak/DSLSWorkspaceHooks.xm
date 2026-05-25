#import "DSHookModules.h"
#import "DSApplicationSupport.h"
#import "DSOpenActionHandler.h"
#import "DSObjectExtraction.h"
#import "DSOpenLogging.h"
#import "DSPrivateInterfaces.h"
#import "DSRouteSupport.h"
#import "DSTweakCommon.h"

static BOOL DSLSWorkspaceIsSourceAppProcess(void) {
    NSString *processName = NSProcessInfo.processInfo.processName ?: @"";
    if ([processName isEqualToString:@"lsd"] || [processName isEqualToString:@"SpringBoard"]) {
        return NO;
    }
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier ?: @"";
    return bundleID.length > 0 && ![bundleID isEqualToString:@"codes.var.tweak.defaultscheme"];
}

static BOOL DSURLUsesHTTPFamily(NSURL *url) {
    NSString *scheme = url.scheme.lowercaseString;
    return [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"];
}

static NSString *DSLSWorkspaceConfiguredBundleIDForURL(NSURL *url) {
    if (![url isKindOfClass:NSURL.class]) return nil;
    if (DSLSWorkspaceIsSourceAppProcess() && !DSURLUsesHTTPFamily(url)) {
        return nil;
    }
    return DSConfiguredBundleIDForURL(url);
}

static NSString *DSLSWorkspaceObservedBundleIDForURL(id workspace, NSURL *url) {
    if (![url isKindOfClass:NSURL.class] || url.absoluteString.length == 0) {
        return nil;
    }

    NSString *bundleID = nil;
    if (workspace && [workspace respondsToSelector:@selector(URLOverrideForURL:)]) {
        @try {
            bundleID = DSBundleIdentifierForProxy([workspace URLOverrideForURL:url]);
        } @catch (__unused NSException *exception) {}
    }
    if (bundleID.length > 0) {
        return bundleID;
    }

    if (workspace && [workspace respondsToSelector:@selector(applicationForOpeningResource:)]) {
        @try {
            bundleID = DSBundleIdentifierForProxy([workspace applicationForOpeningResource:url]);
        } @catch (__unused NSException *exception) {}
    }
    return bundleID;
}

static BOOL DSLSWorkspaceHandleBlockedDecision(DSOpenActionDecision *decision,
                                               NSError **error,
                                               id completion) {
    if (!decision.blocked) {
        return NO;
    }
    if (error) {
        *error = DSDefaultSchemeBlockedError();
    }
    if (completion) {
        @try {
            void (^block)(BOOL, NSError *) = completion;
            block(NO, DSDefaultSchemeBlockedError());
        } @catch (__unused NSException *e) {}
    }
    return YES;
}

%group SourceUIApplicationHooks

%hook UIApplication

- (BOOL)_shouldAttemptOpenURL:(NSURL *)url {
    NSString *bundleID = DSLSWorkspaceConfiguredBundleIDForURL(url);
    if (bundleID.length > 0) {
        if (DSIsNoAppRule(bundleID)) {
            DSLog(@"Source UIApplication _shouldAttemptOpenURL: blocked %@", url.absoluteString ?: @"");
            return NO;
        }
        DSLog(@"Source UIApplication _shouldAttemptOpenURL: allow %@ -> %@", url.absoluteString ?: @"", bundleID);
        return YES;
    }
    return %orig(url);
}

%end
%end

%group LSWorkspaceHooks

%hook LSApplicationWorkspace

- (BOOL)isApplicationAvailableToOpenURL:(NSURL *)url error:(NSError **)error {
    NSString *bundleID = DSLSWorkspaceConfiguredBundleIDForURL(url);
    if (bundleID.length > 0) {
        return DSConfiguredOpenURLTargetIsAvailable(@"LSWorkspace isApplicationAvailableToOpenURL:error:", url, bundleID, error);
    }
    return %orig(url, error);
}

- (BOOL)isApplicationAvailableToOpenURL:(NSURL *)url includePrivateURLSchemes:(BOOL)includePrivateURLSchemes error:(NSError **)error {
    NSString *bundleID = DSLSWorkspaceConfiguredBundleIDForURL(url);
    if (bundleID.length > 0) {
        BOOL available = DSConfiguredOpenURLTargetIsAvailable(@"LSWorkspace isApplicationAvailableToOpenURL:includePrivateURLSchemes:error:", url, bundleID, error);
        DSLog(@"LSWorkspace isApplicationAvailableToOpenURL:includePrivateURLSchemes:error: private=%@", includePrivateURLSchemes ? @"YES" : @"NO");
        return available;
    }
    return %orig(url, includePrivateURLSchemes, error);
}

- (BOOL)isApplicationAvailableToOpenURLCommon:(NSURL *)url includePrivateURLSchemes:(BOOL)includePrivateURLSchemes error:(NSError **)error {
    NSString *bundleID = DSLSWorkspaceConfiguredBundleIDForURL(url);
    if (bundleID.length > 0) {
        BOOL available = DSConfiguredOpenURLTargetIsAvailable(@"LSWorkspace isApplicationAvailableToOpenURLCommon:includePrivateURLSchemes:error:", url, bundleID, error);
        DSLog(@"LSWorkspace isApplicationAvailableToOpenURLCommon:includePrivateURLSchemes:error: private=%@", includePrivateURLSchemes ? @"YES" : @"NO");
        return available;
    }
    return %orig(url, includePrivateURLSchemes, error);
}

- (id)URLOverrideForURL:(NSURL *)url {
    NSString *bundleID = DSLSWorkspaceConfiguredBundleIDForURL(url);
    if (bundleID.length > 0) {
        id preferredApplication = DSPreferredApplicationForConfiguredOpenURL(@"LSWorkspace URLOverrideForURL:", url, bundleID);
        if (preferredApplication) {
            return preferredApplication;
        }
        return nil;
    }
    return %orig(url);
}

- (id)applicationForOpeningResource:(id)resource {
    NSURL *url = DSURLFromContext(resource);
    if (!url) {
        url = DSURLFromDictionaryLikeObject(resource);
    }
    NSString *bundleID = DSLSWorkspaceConfiguredBundleIDForURL(url);
    if (bundleID.length > 0) {
        id preferredApplication = DSPreferredApplicationForConfiguredOpenURL(@"LSWorkspace applicationForOpeningResource:", url, bundleID);
        if (preferredApplication) {
            return preferredApplication;
        }
        return nil;
    }
    return %orig(resource);
}

- (void)openApplicationWithBundleIdentifier:(NSString *)bundleIdentifier configuration:(id)config completionHandler:(id)completion {
    NSURL *url = DSExtractURLFromOpenApplicationRequest(config, bundleIdentifier, nil);
    NSString *configuredBundleID = DSLSWorkspaceConfiguredBundleIDForURL(url);
    if (configuredBundleID.length > 0) {
        if (DSIsNoAppRule(configuredBundleID)) {
            DSLog(@"LSWorkspace openApplicationWithBundleIdentifier:configuration: blocked %@ requested=%@", url.absoluteString ?: @"", bundleIdentifier ?: @"");
            if (completion) {
                @try {
                    void (^block)(BOOL, NSError *) = completion;
                    block(NO, DSDefaultSchemeBlockedError());
                } @catch (__unused NSException *e) {}
            }
            return;
        }
        DSLog(@"LSWorkspace openApplicationWithBundleIdentifier:configuration: %@ requested=%@ -> %@", url.absoluteString ?: @"", bundleIdentifier ?: @"", configuredBundleID);
        %orig(configuredBundleID, config, completion);
        return;
    }
    %orig(bundleIdentifier, config, completion);
}

- (void)openApplicationWithBundleIdentifier:(NSString *)bundleIdentifier usingConfiguration:(id)config completionHandler:(id)completion {
    NSURL *url = DSExtractURLFromOpenApplicationRequest(config, bundleIdentifier, nil);
    NSString *configuredBundleID = DSLSWorkspaceConfiguredBundleIDForURL(url);
    if (configuredBundleID.length > 0) {
        if (DSIsNoAppRule(configuredBundleID)) {
            DSLog(@"LSWorkspace openApplicationWithBundleIdentifier:usingConfiguration: blocked %@ requested=%@", url.absoluteString ?: @"", bundleIdentifier ?: @"");
            if (completion) {
                @try {
                    void (^block)(BOOL, NSError *) = completion;
                    block(NO, DSDefaultSchemeBlockedError());
                } @catch (__unused NSException *e) {}
            }
            return;
        }
        DSLog(@"LSWorkspace openApplicationWithBundleIdentifier:usingConfiguration: %@ requested=%@ -> %@", url.absoluteString ?: @"", bundleIdentifier ?: @"", configuredBundleID);
        %orig(configuredBundleID, config, completion);
        return;
    }
    %orig(bundleIdentifier, config, completion);
}

- (id)operationToOpenResource:(id)resource usingApplication:(id)application uniqueDocumentIdentifier:(id)uniqueDocumentIdentifier userInfo:(id)userInfo delegate:(id)delegate {
    NSURL *url = DSExtractURLFromOpenApplicationRequest(resource, userInfo, application);
    NSString *bundleID = DSLSWorkspaceConfiguredBundleIDForURL(url);
    if (bundleID.length > 0) {
        id preferredApplication = DSPreferredApplicationForConfiguredOpenURL(@"LSWorkspace operationToOpenResource:uniqueDocumentIdentifier:", url, bundleID);
        if (preferredApplication) {
            return %orig(resource, preferredApplication, uniqueDocumentIdentifier, userInfo, delegate);
        }
        return nil;
    }
    return %orig(resource, application, uniqueDocumentIdentifier, userInfo, delegate);
}

- (id)operationToOpenResource:(id)resource usingApplication:(id)application userInfo:(id)userInfo delegate:(id)delegate {
    NSURL *url = DSExtractURLFromOpenApplicationRequest(resource, userInfo, application);
    NSString *bundleID = DSLSWorkspaceConfiguredBundleIDForURL(url);
    if (bundleID.length > 0) {
        id preferredApplication = DSPreferredApplicationForConfiguredOpenURL(@"LSWorkspace operationToOpenResource:userInfo:", url, bundleID);
        if (preferredApplication) {
            return %orig(resource, preferredApplication, userInfo, delegate);
        }
        return nil;
    }
    return %orig(resource, application, userInfo, delegate);
}

// The main URL opening entry point
- (void)openURL:(NSURL *)url configuration:(id)config completionHandler:(id)completion {
    NSDictionary<NSString *, NSString *> *sourceInfo = DSSourceApplicationInfoFromObject(config);
    DSOpenActionDecision *decision = DSHandleOpenURLActionWithConfiguredBundleID(@"LSWorkspace openURL:config:",
                                                                                 url,
                                                                                 sourceInfo,
                                                                                 DSLSWorkspaceObservedBundleIDForURL(self, url),
                                                                                 DSLSWorkspaceConfiguredBundleIDForURL(url));
    if (DSLSWorkspaceHandleBlockedDecision(decision, nil, completion)) {
        DSLog(@"LSWorkspace openURL:config: blocked %@", url.absoluteString ?: @"");
        return;
    }
    %orig(url, config, completion);
}

- (BOOL)openURL:(NSURL *)url {
    DSOpenActionDecision *decision = DSHandleOpenURLActionWithConfiguredBundleID(@"LSWorkspace openURL:",
                                                                                 url,
                                                                                 nil,
                                                                                 DSLSWorkspaceObservedBundleIDForURL(self, url),
                                                                                 DSLSWorkspaceConfiguredBundleIDForURL(url));
    if (decision.blocked) {
        DSLog(@"LSWorkspace openURL: blocked %@", url.absoluteString ?: @"");
        return NO;
    }
    return %orig(url);
}

- (BOOL)openURL:(NSURL *)url withOptions:(id)options {
    NSDictionary<NSString *, NSString *> *sourceInfo = DSSourceApplicationInfoFromObject(options);
    DSOpenActionDecision *decision = DSHandleOpenURLActionWithConfiguredBundleID(@"LSWorkspace openURL:withOptions:",
                                                                                 url,
                                                                                 sourceInfo,
                                                                                 DSLSWorkspaceObservedBundleIDForURL(self, url),
                                                                                 DSLSWorkspaceConfiguredBundleIDForURL(url));
    if (decision.blocked) {
        DSLog(@"LSWorkspace openURL:withOptions: blocked %@", url.absoluteString ?: @"");
        return NO;
    }
    return %orig(url, options);
}

- (BOOL)openURL:(NSURL *)url withOptions:(id)options error:(NSError **)error {
    NSDictionary<NSString *, NSString *> *sourceInfo = DSSourceApplicationInfoFromObject(options);
    DSOpenActionDecision *decision = DSHandleOpenURLActionWithConfiguredBundleID(@"LSWorkspace openURL:withOptions:error:",
                                                                                 url,
                                                                                 sourceInfo,
                                                                                 DSLSWorkspaceObservedBundleIDForURL(self, url),
                                                                                 DSLSWorkspaceConfiguredBundleIDForURL(url));
    if (DSLSWorkspaceHandleBlockedDecision(decision, error, nil)) {
        DSLog(@"LSWorkspace openURL:withOptions:error: blocked %@", url.absoluteString ?: @"");
        return NO;
    }
    return %orig(url, options, error);
}

- (BOOL)openSensitiveURL:(NSURL *)url withOptions:(id)options {
    NSDictionary<NSString *, NSString *> *sourceInfo = DSSourceApplicationInfoFromObject(options);
    DSOpenActionDecision *decision = DSHandleOpenURLActionWithConfiguredBundleID(@"LSWorkspace openSensitiveURL:",
                                                                                 url,
                                                                                 sourceInfo,
                                                                                 DSLSWorkspaceObservedBundleIDForURL(self, url),
                                                                                 DSLSWorkspaceConfiguredBundleIDForURL(url));
    if (decision.blocked) {
        DSLog(@"LSWorkspace openSensitiveURL: blocked %@", url.absoluteString ?: @"");
        return NO;
    }
    return %orig(url, options);
}

- (BOOL)openSensitiveURL:(NSURL *)url withOptions:(id)options error:(NSError **)error {
    NSDictionary<NSString *, NSString *> *sourceInfo = DSSourceApplicationInfoFromObject(options);
    DSOpenActionDecision *decision = DSHandleOpenURLActionWithConfiguredBundleID(@"LSWorkspace openSensitiveURL:error:",
                                                                                 url,
                                                                                 sourceInfo,
                                                                                 DSLSWorkspaceObservedBundleIDForURL(self, url),
                                                                                 DSLSWorkspaceConfiguredBundleIDForURL(url));
    if (DSLSWorkspaceHandleBlockedDecision(decision, error, nil)) {
        DSLog(@"LSWorkspace openSensitiveURL:error: blocked %@", url.absoluteString ?: @"");
        return NO;
    }
    return %orig(url, options, error);
}

- (void)_sf_openURL:(NSURL *)url withOptions:(id)options completionHandler:(id)completion {
    NSDictionary<NSString *, NSString *> *sourceInfo = DSSourceApplicationInfoFromObject(options);
    DSOpenActionDecision *decision = DSHandleOpenURLActionWithConfiguredBundleID(@"LSWorkspace _sf_openURL:",
                                                                                 url,
                                                                                 sourceInfo,
                                                                                 DSLSWorkspaceObservedBundleIDForURL(self, url),
                                                                                 DSLSWorkspaceConfiguredBundleIDForURL(url));
    if (DSLSWorkspaceHandleBlockedDecision(decision, nil, completion)) {
        DSLog(@"LSWorkspace _sf_openURL: blocked %@", url.absoluteString ?: @"");
        return;
    }
    %orig(url, options, completion);
}

- (void)_sf_openURL:(NSURL *)url inApplication:(id)application withOptions:(id)options completionHandler:(id)completion {
    NSString *bundleID = DSLSWorkspaceConfiguredBundleIDForURL(url);
    if (bundleID.length > 0) {
        if (DSIsNoAppRule(bundleID)) {
            DSLog(@"LSWorkspace _sf_openURL:inApplication: blocked %@", url.absoluteString ?: @"");
            if (completion) {
                @try {
                    void (^block)(BOOL, NSError *) = completion;
                    block(NO, DSDefaultSchemeBlockedError());
                } @catch (__unused NSException *e) {}
            }
            return;
        }
        id preferredApplication = DSPreferredApplicationForConfiguredOpenURL(@"LSWorkspace _sf_openURL:inApplication:", url, bundleID);
        if (preferredApplication) {
            %orig(url, preferredApplication, options, completion);
            return;
        }
        if (completion) {
            @try {
                void (^block)(BOOL, NSError *) = completion;
                block(NO, DSDefaultSchemeUnavailableError());
            } @catch (__unused NSException *e) {}
        }
        return;
    }
    %orig(url, application, options, completion);
}

- (void)_sf_tryOpeningURLInDefaultApp:(NSURL *)url isContentManaged:(BOOL)isContentManaged completionHandler:(id)completion {
    DSOpenActionDecision *decision = DSHandleOpenURLActionWithConfiguredBundleID(@"LSWorkspace _sf_tryOpeningURLInDefaultApp:",
                                                                                 url,
                                                                                 nil,
                                                                                 DSLSWorkspaceObservedBundleIDForURL(self, url),
                                                                                 DSLSWorkspaceConfiguredBundleIDForURL(url));
    if (DSLSWorkspaceHandleBlockedDecision(decision, nil, completion)) {
        DSLog(@"LSWorkspace _sf_tryOpeningURLInDefaultApp: blocked %@", url.absoluteString ?: @"");
        return;
    }
    %orig(url, isContentManaged, completion);
}

%end
%end


void DSInitSourceUIApplicationHooks(Class applicationClass) {
    %init(SourceUIApplicationHooks, UIApplication=applicationClass);
}

void DSInitLSWorkspaceHooks(Class lsWorkspaceClass) {
    %init(LSWorkspaceHooks, LSApplicationWorkspace=lsWorkspaceClass);
}
