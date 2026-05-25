#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

NSString *DSBundleIdentifierForProxy(id proxy);
NSString *DSLocalizedNameForProxy(id proxy);
NSURL *DSBundleURLForProxy(id proxy);
NSArray *DSInstalledApplicationProxies(void);
NSDictionary<NSString *, NSString *> *DSApplicationInfoForProxy(id proxy);
NSDictionary<NSString *, NSString *> *DSApplicationInfoForBundleID(NSString *bundleID);
NSDictionary<NSString *, NSString *> *DSApplicationInfoForBundlePath(NSString *bundlePath);
NSDictionary<NSString *, NSString *> *DSApplicationInfoFromAuditToken(const void *sourceAuditToken);
NSDictionary<NSString *, NSString *> *DSApplicationInfoWithBundleIDAndName(NSString *bundleID, NSString *name);
NSDictionary<NSString *, NSString *> *DSMergedApplicationInfo(NSDictionary<NSString *, NSString *> *preferred, NSDictionary<NSString *, NSString *> *fallback);
NSDictionary<NSString *, NSString *> *DSCurrentProcessApplicationInfo(void);
NSDictionary<NSString *, NSString *> *DSApplicationInfoFromObject(id object);
NSDictionary<NSString *, NSString *> *DSMergedApplicationInfoFromObjects(id first, id second, id third, id fourth);
NSDictionary<NSString *, NSString *> *DSSourceApplicationInfoFromObject(id object);
NSDictionary<NSString *, NSString *> *DSSourceApplicationInfoFromObjects(id first, id second, id third, id fourth);

#ifdef __cplusplus
}
#endif
