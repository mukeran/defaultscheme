#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <unistd.h>
#import "DSHookModules.h"
#import "DSOpenLogging.h"
#import "DSTweakCommon.h"
#import "../Shared/DSRoutingConfig.h"

static BOOL DSCurrentProcessShouldInitializeAsSourceApp(NSString *processName, NSString *bundleID) {
    if (bundleID.length == 0) {
        return NO;
    }
    if ([processName isEqualToString:@"lsd"] || [processName isEqualToString:@"SpringBoard"]) {
        return NO;
    }
    return YES;
}

%ctor {
    NSString *proc = NSProcessInfo.processInfo.processName ?: @"?";
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier ?: @"";
    BOOL isLaunchServicesDaemon = [proc isEqualToString:@"lsd"];
    BOOL isSpringBoard = [proc isEqualToString:@"SpringBoard"];
    BOOL isWhitelistedSourceApp = DSCurrentProcessShouldInitializeAsSourceApp(proc, bundleID);
    DSLog(@"ctor reached in %@ pid=%d bundle=%@ sourceWhitelisted=%@", proc, getpid(), bundleID, isWhitelistedSourceApp ? @"YES" : @"NO");
    if (!isLaunchServicesDaemon && !isSpringBoard && !isWhitelistedSourceApp) {
        return;
    }

    DSLog(@"========================================");
    DSLog(@"loaded in %@ pid=%d bundle=%@ sourceWhitelisted=%@", proc, getpid(), bundleID, isWhitelistedSourceApp ? @"YES" : @"NO");
    if (isLaunchServicesDaemon) {
        DSStartOpenLogRelayServerIfNeeded();
    }

    Class lsWorkspaceClass = objc_getClass("LSApplicationWorkspace");
    if (lsWorkspaceClass) {
        DSLog(@"LSApplicationWorkspace exists=YES class=%p", lsWorkspaceClass);
        DSInitLSWorkspaceHooks(lsWorkspaceClass);
    } else {
        DSLog(@"LSApplicationWorkspace exists=NO");
    }

    if (isWhitelistedSourceApp) {
        Class applicationClass = objc_getClass("UIApplication");
        DSLog(@"UIApplication exists=%@", applicationClass ? @"YES" : @"NO");
        if (applicationClass) {
            DSInitSourceUIApplicationHooks(applicationClass);
        }
    }

    if (isLaunchServicesDaemon) {
        Class lsdOpenClientClass = objc_getClass("_LSDOpenClient");
        if (lsdOpenClientClass) {
            DSLog(@"_LSDOpenClient exists=YES class=%p", lsdOpenClientClass);
            DSInitLSDOpenClientHooks(lsdOpenClientClass);
        } else {
            DSLog(@"_LSDOpenClient exists=NO");
        }
    }

    if (!isWhitelistedSourceApp) {
        Class lsAppLinkClass = objc_getClass("LSAppLink");
        if (lsAppLinkClass) {
            DSLog(@"LSAppLink exists=YES class=%p", lsAppLinkClass);
            DSInitLSAppLinkHooks(lsAppLinkClass);
        } else {
            DSLog(@"LSAppLink exists=NO");
        }
    }

    if (isSpringBoard) {
        Class mw = objc_getClass("SBMainWorkspace");
        DSLog(@"SBMainWorkspace exists=%@", mw ? @"YES" : @"NO");
        Class springBoardClass = objc_getClass("SpringBoard");
        if (mw && springBoardClass) {
            DSInitSpringBoardHooks(mw, springBoardClass);
        }
    }
}
