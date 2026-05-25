#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

NSDictionary<NSString *, id> *DSBestConfiguredLinkRuleForURL(NSURL *url, NSDictionary *config);
NSString *DSConfiguredBundleIDForURL(NSURL *url);
NSString *DSConfiguredBundleIDForScheme(NSString *scheme);
BOOL DSIsWebURL(NSURL *url);
id DSInstalledApplicationProxyForBundleID(NSString *bundleID);
id DSApplicationProxyForURL(NSURL *url, NSString *bundleID);
BOOL DSConfiguredBundleIsAvailableForURL(NSURL *url);

#ifdef __cplusplus
}
#endif
