#import "DSAppDelegate.h"
#import "DSRootViewController.h"
#import "DSIncomingLinkViewController.h"

@implementation DSAppDelegate

- (DSRootViewController *)rootViewController {
    return [self.window.rootViewController isKindOfClass:UINavigationController.class]
        ? ((UINavigationController *)self.window.rootViewController).viewControllers.firstObject
        : nil;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    DSRootViewController *root = [[DSRootViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:root];
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
    [self presentIncomingLinkFromLaunchOptions:launchOptions];
    return YES;
}

- (void)presentIncomingLinkFromLaunchOptions:(NSDictionary *)launchOptions {
    NSString *linkString = [self incomingLinkStringFromLaunchOptions:launchOptions];
    if (linkString.length == 0) {
        return;
    }
    [self presentIncomingLinkViewControllerWithLinkString:linkString];
}

- (NSString *)incomingLinkStringFromLaunchOptions:(NSDictionary *)launchOptions {
    NSURL *url = launchOptions[UIApplicationLaunchOptionsURLKey];
    if (![url isKindOfClass:NSURL.class]) {
        return nil;
    }
    return url.absoluteString;
}

- (void)presentIncomingLinkFromUserActivity:(id)userActivity {
    if (![userActivity isKindOfClass:NSUserActivity.class]) {
        return;
    }

    NSURL *url = ((NSUserActivity *)userActivity).webpageURL;
    if (![url isKindOfClass:NSURL.class] || url.absoluteString.length == 0) {
        return;
    }
    [self presentIncomingLinkViewControllerWithLinkString:url.absoluteString];
}

- (void)presentIncomingLinkViewControllerWithLinkString:(NSString *)linkString {
    DSIncomingLinkViewController *controller = [[DSIncomingLinkViewController alloc] init];
    controller.linkString = linkString;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:controller];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    [self.window.rootViewController presentViewController:nav animated:YES completion:nil];
}

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey,id> *)options {
    NSString *linkString = url.absoluteString;
    if (linkString.length == 0) {
        return NO;
    }
    if ([self isDefaultSchemePresentationURL:url]) {
        NSURL *presentedURL = [self incomingLinkFromPresentationURL:url];
        if (presentedURL.absoluteString.length > 0) {
            linkString = presentedURL.absoluteString;
        }
    }
    [self presentIncomingLinkViewControllerWithLinkString:linkString];
    return YES;
}

- (BOOL)application:(UIApplication *)application
        continueUserActivity:(NSUserActivity *)userActivity
          restorationHandler:(void (^)(NSArray<id<UIUserActivityRestoring>> *))restorationHandler {
    [self presentIncomingLinkFromUserActivity:userActivity];
    return YES;
}

- (BOOL)isDefaultSchemePresentationURL:(NSURL *)url {
    return [url.scheme.lowercaseString isEqualToString:@"defaultscheme"];
}

- (NSURL *)incomingLinkFromPresentationURL:(NSURL *)url {
    NSString *encodedLink = url.query ?: @"";
    if (encodedLink.length == 0) {
        return nil;
    }
    NSString *decodedLink = [encodedLink stringByRemovingPercentEncoding];
    return [NSURL URLWithString:decodedLink];
}

@end
