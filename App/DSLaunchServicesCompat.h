#import <Foundation/Foundation.h>

@interface LSApplicationProxy : NSObject
- (NSString *)bundleIdentifier;
- (NSString *)localizedName;
- (NSDictionary *)entitlements;
- (NSArray *)claimedURLSchemes;
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray *)allInstalledApplications;
- (NSArray *)applicationsAvailableForOpeningURL:(NSURL *)url;
@end
