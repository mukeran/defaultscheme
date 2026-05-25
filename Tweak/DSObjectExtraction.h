#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

id DSSafeValueForKey(id object, NSString *key);
NSArray *DSCollectionObjects(id object);
NSString *DSTrimmedDescription(id object);
NSURL *DSURLFromContext(id context);
NSURL *DSURLFromDictionaryLikeObject(id object);
NSURL *DSLaunchServicesURLFromObject(id object);
NSString *DSLaunchServicesSchemeFromObject(id object);
NSString *DSConfiguredBundleIDForLaunchServicesObject(id object);
NSURL *DSExtractURLFromOpenApplicationRequest(id request, id options, id origin);
NSURL *DSExtractURLFromAppLink(id appLink);

#ifdef __cplusplus
}
#endif
