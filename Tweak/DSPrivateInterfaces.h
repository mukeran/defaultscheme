#import <Foundation/Foundation.h>

@interface LSApplicationProxy : NSObject
- (NSString *)bundleIdentifier;
- (NSString *)localizedName;
- (NSURL *)bundleURL;
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray *)allInstalledApplications;
- (NSArray *)applicationsAvailableForOpeningURL:(NSURL *)url;
- (NSArray *)applicationsAvailableForOpeningURL:(NSURL *)url legacySPI:(BOOL)legacySPI;
- (NSArray *)applicationsAvailableForHandlingURLScheme:(NSString *)scheme;
- (BOOL)isApplicationAvailableToOpenURL:(NSURL *)url error:(NSError **)error;
- (BOOL)isApplicationAvailableToOpenURL:(NSURL *)url includePrivateURLSchemes:(BOOL)includePrivateURLSchemes error:(NSError **)error;
- (BOOL)isApplicationAvailableToOpenURLCommon:(NSURL *)url includePrivateURLSchemes:(BOOL)includePrivateURLSchemes error:(NSError **)error;
- (id)applicationForOpeningResource:(id)resource;
- (id)URLOverrideForURL:(NSURL *)url;
- (BOOL)openApplicationWithBundleID:(NSString *)bundleID;
- (void)openApplicationWithBundleIdentifier:(NSString *)bundleIdentifier configuration:(id)config completionHandler:(id)completion;
- (void)openApplicationWithBundleIdentifier:(NSString *)bundleIdentifier usingConfiguration:(id)config completionHandler:(id)completion;
- (id)operationToOpenResource:(id)resource usingApplication:(id)application uniqueDocumentIdentifier:(id)uniqueDocumentIdentifier userInfo:(id)userInfo delegate:(id)delegate;
- (id)operationToOpenResource:(id)resource usingApplication:(id)application userInfo:(id)userInfo delegate:(id)delegate;
- (void)openURL:(NSURL *)url configuration:(id)config completionHandler:(id)completion;
- (void)openURL:(NSURL *)url;
- (void)openURL:(NSURL *)url withOptions:(id)options;
- (BOOL)openURL:(NSURL *)url withOptions:(id)options error:(NSError **)error;
- (BOOL)openSensitiveURL:(NSURL *)url withOptions:(id)options;
- (BOOL)openSensitiveURL:(NSURL *)url withOptions:(id)options error:(NSError **)error;
- (void)_sf_openURL:(NSURL *)url withOptions:(id)options completionHandler:(id)completion;
- (void)_sf_openURL:(NSURL *)url inApplication:(id)application withOptions:(id)options completionHandler:(id)completion;
- (void)_sf_tryOpeningURLInDefaultApp:(NSURL *)url isContentManaged:(BOOL)isContentManaged completionHandler:(id)completion;
@end

@interface _LSDOpenClient : NSObject
- (void)getURLOverrideForURL:(NSURL *)url completionHandler:(id)completion;
- (void)canOpenURL:(NSURL *)url publicSchemes:(BOOL)publicSchemes privateSchemes:(BOOL)privateSchemes completionHandler:(id)completion;
- (void)openApplicationWithIdentifier:(NSString *)identifier options:(id)options useClientProcessHandle:(BOOL)useClientProcessHandle completionHandler:(id)completion;
- (void)openURL:(NSURL *)url options:(id)options completionHandler:(id)completion;
- (void)openAppLink:(id)appLink state:(id)state completionHandler:(id)completion;
- (void)performOpenOperationWithURL:(NSURL *)url bundleIdentifier:(NSString *)bundleIdentifier documentIdentifier:(id)documentIdentifier isContentManaged:(BOOL)isContentManaged sourceAuditToken:(const void *)sourceAuditToken userInfo:(id)userInfo options:(id)options delegate:(id)delegate completionHandler:(id)completion;
@end

@interface SBWorkspaceTransitionRequest : NSObject
@property (nonatomic, copy) NSString *eventLabel;
@end

@interface SBWorkspaceApplicationTransitionRequest : SBWorkspaceTransitionRequest
@property (nonatomic, strong) id applicationContext;
@end

@interface SBMainWorkspace : NSObject
- (void)executeTransitionRequest:(SBWorkspaceApplicationTransitionRequest *)request;
- (void)executeTransitionRequest:(SBWorkspaceApplicationTransitionRequest *)request completion:(id)completion;
- (void)_handleOpenApplicationRequest:(id)request options:(id)options activationSettings:(id)activationSettings origin:(id)origin withResult:(id)result;
- (void)_handleTrustedOpenRequestForApplication:(id)application options:(id)options activationSettings:(id)activationSettings origin:(id)origin withResult:(id)result;
- (void)_handleUntrustedOpenRequestForApplication:(id)application options:(id)options activationSettings:(id)activationSettings origin:(id)origin withResult:(id)result;
- (void)systemService:(id)systemService handleOpenApplicationRequest:(id)request withCompletion:(id)completion;
@end

@interface LSAppLink : NSObject
@property (nonatomic, copy) NSURL *URL;
+ (void)openWithURL:(NSURL *)url completionHandler:(id)completion;
+ (void)openWithURL:(NSURL *)url configuration:(id)config completionHandler:(id)completion;
+ (void)_openWithAppLink:(LSAppLink *)appLink state:(id)state completionHandler:(id)completion;
+ (void)_openAppLink:(LSAppLink *)appLink state:(id)state completionHandler:(id)completion;
- (void)openWithCompletionHandler:(id)completion;
- (void)openWithConfiguration:(id)config completionHandler:(id)completion;
@end
