#import "DSHookModules.h"
#import "DSApplicationSupport.h"
#import "DSOpenActionHandler.h"
#import "DSObjectExtraction.h"
#import "DSOpenLogging.h"
#import "DSPrivateInterfaces.h"
#import "DSRouteSupport.h"
#import "DSTweakCommon.h"

static DSOpenActionDecision *DSSpringBoardDecision(NSString *source,
                                                   NSURL *url,
                                                   NSDictionary<NSString *, NSString *> *sourceInfo,
                                                   id application) {
    return DSHandleOpenURLAction(source, url, sourceInfo, DSBundleIdentifierForProxy(application));
}

static BOOL DSSpringBoardTransitionRequestShouldBlock(SBWorkspaceApplicationTransitionRequest *request) {
    if (!request) return NO;

    NSString *eventLabel = nil;
    @try { eventLabel = request.eventLabel; }
    @catch (__unused NSException *exception) { eventLabel = nil; }

    if (eventLabel.length > 0 && [eventLabel rangeOfString:@"OpenURL" options:NSCaseInsensitiveSearch].location == NSNotFound) {
        return NO;
    }

    id context = nil;
    @try { context = request.applicationContext; }
    @catch (__unused NSException *exception) { context = nil; }

    NSURL *url = DSExtractURLFromOpenApplicationRequest(request, context, nil);
    if (!url) {
        if (eventLabel.length > 0) {
            DSLog(@"SBMainWorkspace transition request without URL event=%@ context=%@", eventLabel, NSStringFromClass([context class]));
        }
        return NO;
    }

    NSDictionary<NSString *, NSString *> *sourceInfo = DSSourceApplicationInfoFromObjects(request, context, nil, nil);
    DSOpenActionDecision *decision = DSHandleOpenURLAction(@"SBMainWorkspace transition request",
                                                           url,
                                                           sourceInfo,
                                                           nil);
    if (decision.blocked) {
        DSLog(@"SBMainWorkspace blocked URL: %@", decision.url.absoluteString ?: @"");
        return YES;
    }
    return NO;
}

static BOOL DSHandleRequestWithRule(SBWorkspaceApplicationTransitionRequest *request) {
    return DSSpringBoardTransitionRequestShouldBlock(request);
}

static BOOL DSSpringBoardHandleBlockedDecision(DSOpenActionDecision *decision, id completion) {
    if (!decision.blocked) {
        return NO;
    }
    if (completion) {
        @try {
            void (^block)(BOOL) = completion;
            block(NO);
        } @catch (__unused NSException *e) {}
    }
    return YES;
}

%group SpringBoardHooks

%hook SBMainWorkspace

- (void)executeTransitionRequest:(SBWorkspaceApplicationTransitionRequest *)request {
    if (DSHandleRequestWithRule(request)) return;
    %orig(request);
}

- (void)executeTransitionRequest:(SBWorkspaceApplicationTransitionRequest *)request completion:(id)completion {
    if (DSHandleRequestWithRule(request)) {
        if (completion) {
            @try {
                void (^block)(void) = completion;
                block();
            } @catch (__unused NSException *exception) {}
        }
        return;
    }
    %orig(request, completion);
}

- (void)_handleOpenApplicationRequest:(id)request options:(id)options activationSettings:(id)activationSettings origin:(id)origin withResult:(id)result {
    NSURL *url = DSExtractURLFromOpenApplicationRequest(request, options, origin);
    NSDictionary<NSString *, NSString *> *sourceInfo = DSSourceApplicationInfoFromObjects(origin, request, options, nil);
    DSOpenActionDecision *decision = DSSpringBoardDecision(@"SBMainWorkspace _handleOpenApplicationRequest",
                                                           url,
                                                           sourceInfo,
                                                           request);
    if (decision.blocked) {
        DSLog(@"SBMainWorkspace _handleOpenApplicationRequest blocked %@", url.absoluteString ?: @"");
        return;
    }
    %orig(request, options, activationSettings, origin, result);
}

- (void)_handleTrustedOpenRequestForApplication:(id)application options:(id)options activationSettings:(id)activationSettings origin:(id)origin withResult:(id)result {
    NSURL *url = DSExtractURLFromOpenApplicationRequest(application, options, origin);
    NSDictionary<NSString *, NSString *> *sourceInfo = DSSourceApplicationInfoFromObjects(origin, application, options, nil);
    DSOpenActionDecision *decision = DSSpringBoardDecision(@"SBMainWorkspace _handleTrustedOpenRequestForApplication",
                                                           url,
                                                           sourceInfo,
                                                           application);
    if (decision.blocked) {
        DSLog(@"SBMainWorkspace _handleTrustedOpenRequestForApplication blocked %@", url.absoluteString ?: @"");
        return;
    }
    if (decision.matchedRule) {
        application = DSResolvedApplicationForOpenActionDecision(decision,
                                                                 application,
                                                                 @"SBMainWorkspace _handleTrustedOpenRequestForApplication");
    }
    %orig(application, options, activationSettings, origin, result);
}

- (void)_handleUntrustedOpenRequestForApplication:(id)application options:(id)options activationSettings:(id)activationSettings origin:(id)origin withResult:(id)result {
    NSURL *url = DSExtractURLFromOpenApplicationRequest(application, options, origin);
    NSDictionary<NSString *, NSString *> *sourceInfo = DSSourceApplicationInfoFromObjects(origin, application, options, nil);
    DSOpenActionDecision *decision = DSSpringBoardDecision(@"SBMainWorkspace _handleUntrustedOpenRequestForApplication",
                                                           url,
                                                           sourceInfo,
                                                           application);
    if (decision.blocked) {
        DSLog(@"SBMainWorkspace _handleUntrustedOpenRequestForApplication blocked %@", url.absoluteString ?: @"");
        return;
    }
    if (decision.matchedRule) {
        application = DSResolvedApplicationForOpenActionDecision(decision,
                                                                 application,
                                                                 @"SBMainWorkspace _handleUntrustedOpenRequestForApplication");
    }
    %orig(application, options, activationSettings, origin, result);
}

- (void)systemService:(id)systemService handleOpenApplicationRequest:(id)request withCompletion:(id)completion {
    NSURL *url = DSExtractURLFromOpenApplicationRequest(request, nil, systemService);
    NSDictionary<NSString *, NSString *> *sourceInfo = DSSourceApplicationInfoFromObjects(request, systemService, nil, nil);
    DSOpenActionDecision *decision = DSSpringBoardDecision(@"SBMainWorkspace systemService:handleOpenApplicationRequest:",
                                                           url,
                                                           sourceInfo,
                                                           request);
    if (decision.blocked) {
        DSLog(@"SBMainWorkspace systemService:handleOpenApplicationRequest: blocked %@", url.absoluteString ?: @"");
        return;
    }
    %orig(systemService, request, completion);
}

%end

%hook SpringBoard

- (BOOL)openURL:(NSURL *)url {
    DSOpenActionDecision *decision = DSSpringBoardDecision(@"SpringBoard openURL:", url, nil, nil);
    if (decision.blocked) {
        DSLog(@"SpringBoard openURL: blocked %@", url.absoluteString ?: @"");
        return NO;
    }
    return %orig(url);
}

- (void)openURL:(NSURL *)url withCompletionHandler:(id)completion {
    DSOpenActionDecision *decision = DSSpringBoardDecision(@"SpringBoard openURL:withCompletionHandler:", url, nil, nil);
    if (decision.blocked) {
        DSLog(@"SpringBoard openURL:withCompletionHandler: blocked %@", url.absoluteString ?: @"");
        if (completion) {
            @try {
                void (^block)(BOOL) = completion;
                block(NO);
            } @catch (__unused NSException *e) {}
        }
        return;
    }
    %orig(url, completion);
}

- (void)openURL:(NSURL *)url options:(id)options completionHandler:(id)completion {
    NSDictionary<NSString *, NSString *> *sourceInfo = DSSourceApplicationInfoFromObject(options);
    DSOpenActionDecision *decision = DSSpringBoardDecision(@"SpringBoard openURL:options:", url, sourceInfo, nil);
    if (DSSpringBoardHandleBlockedDecision(decision, completion)) {
        DSLog(@"SpringBoard openURL:options: blocked %@", url.absoluteString ?: @"");
        return;
    }
    %orig(url, options, completion);
}

- (void)_openURL:(NSURL *)url {
    DSOpenActionDecision *decision = DSSpringBoardDecision(@"SpringBoard _openURL:", url, nil, nil);
    if (decision.blocked) {
        DSLog(@"SpringBoard _openURL: blocked %@", url.absoluteString ?: @"");
        return;
    }
    %orig(url);
}

- (void)_openURL:(NSURL *)url options:(id)options completionHandler:(id)completion {
    NSDictionary<NSString *, NSString *> *sourceInfo = DSSourceApplicationInfoFromObject(options);
    DSOpenActionDecision *decision = DSSpringBoardDecision(@"SpringBoard _openURL:options:", url, sourceInfo, nil);
    if (DSSpringBoardHandleBlockedDecision(decision, completion)) {
        DSLog(@"SpringBoard _openURL:options: blocked %@", url.absoluteString ?: @"");
        return;
    }
    %orig(url, options, completion);
}

- (void)_openURL:(NSURL *)url options:(id)options openApplicationEndpoint:(id)endpoint completionHandler:(id)completion {
    NSDictionary<NSString *, NSString *> *sourceInfo = DSSourceApplicationInfoFromObjects(endpoint, options, nil, nil);
    DSOpenActionDecision *decision = DSSpringBoardDecision(@"SpringBoard _openURL:endpoint:", url, sourceInfo, endpoint);
    if (DSSpringBoardHandleBlockedDecision(decision, completion)) {
        DSLog(@"SpringBoard _openURL:endpoint: blocked %@", url.absoluteString ?: @"");
        return;
    }
    %orig(url, options, endpoint, completion);
}

- (void)_openURL:(NSURL *)url options:(id)options openApplicationEndpoint:(id)endpoint asyncCompletion:(id)asyncCompletion completionHandler:(id)completion {
    NSDictionary<NSString *, NSString *> *sourceInfo = DSSourceApplicationInfoFromObjects(endpoint, options, asyncCompletion, nil);
    DSOpenActionDecision *decision = DSSpringBoardDecision(@"SpringBoard _openURL:endpoint:asyncCompletion:", url, sourceInfo, endpoint);
    if (DSSpringBoardHandleBlockedDecision(decision, completion)) {
        DSLog(@"SpringBoard _openURL:endpoint:asyncCompletion: blocked %@", url.absoluteString ?: @"");
        return;
    }
    %orig(url, options, endpoint, asyncCompletion, completion);
}

- (void)_openURLCore:(NSURL *)url display:(id)display animating:(BOOL)animating activationSettings:(id)activationSettings origin:(id)origin withResult:(id)result {
    NSDictionary<NSString *, NSString *> *sourceInfo = DSSourceApplicationInfoFromObjects(origin, activationSettings, display, nil);
    DSOpenActionDecision *decision = DSSpringBoardDecision(@"SpringBoard _openURLCore", url, sourceInfo, display);
    if (decision.blocked) {
        DSLog(@"SpringBoard _openURLCore blocked %@", url.absoluteString ?: @"");
        return;
    }
    %orig(url, display, animating, activationSettings, origin, result);
}

- (void)applicationOpenURL:(NSURL *)url withApplication:(id)application animating:(BOOL)animating activationSettings:(id)activationSettings origin:(id)origin withResult:(id)result {
    NSDictionary<NSString *, NSString *> *sourceInfo = DSSourceApplicationInfoFromObjects(origin, application, activationSettings, nil);
    DSOpenActionDecision *decision = DSSpringBoardDecision(@"SpringBoard fallback route", url, sourceInfo, application);
    if (decision.blocked) {
        DSLog(@"SpringBoard fallback block %@", url.absoluteString ?: @"");
        return;
    }
    application = DSResolvedApplicationForOpenActionDecision(decision, application, @"SpringBoard fallback route");
    %orig(url, application, animating, activationSettings, origin, result);
}

- (void)applicationOpenURL:(NSURL *)url withApplication:(id)application animating:(BOOL)animating activationSettings:(id)activationSettings origin:(id)origin notifyLSOnFailure:(BOOL)notifyLSOnFailure withResult:(id)result {
    NSDictionary<NSString *, NSString *> *sourceInfo = DSSourceApplicationInfoFromObjects(origin, application, activationSettings, nil);
    DSOpenActionDecision *decision = DSSpringBoardDecision(@"SpringBoard fallback notifyLS route", url, sourceInfo, application);
    if (decision.blocked) {
        DSLog(@"SpringBoard fallback block notifyLS %@", url.absoluteString ?: @"");
        return;
    }
    application = DSResolvedApplicationForOpenActionDecision(decision, application, @"SpringBoard fallback notifyLS route");
    %orig(url, application, animating, activationSettings, origin, notifyLSOnFailure, result);
}

- (void)_applicationOpenURL:(NSURL *)url withApplication:(id)application animating:(BOOL)animating activationSettings:(id)activationSettings origin:(id)origin withResult:(id)result {
    NSDictionary<NSString *, NSString *> *sourceInfo = DSSourceApplicationInfoFromObjects(origin, application, activationSettings, nil);
    DSOpenActionDecision *decision = DSSpringBoardDecision(@"SpringBoard _applicationOpenURL route", url, sourceInfo, application);
    if (decision.blocked) {
        DSLog(@"SpringBoard _applicationOpenURL block %@", url.absoluteString ?: @"");
        return;
    }
    application = DSResolvedApplicationForOpenActionDecision(decision, application, @"SpringBoard _applicationOpenURL route");
    %orig(url, application, animating, activationSettings, origin, result);
}

%end
%end


void DSInitSpringBoardHooks(Class mainWorkspaceClass, Class springBoardClass) {
    %init(SpringBoardHooks, SBMainWorkspace=mainWorkspaceClass, SpringBoard=springBoardClass);
}
