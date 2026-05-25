#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DSOpenActionDecision : NSObject
@property (nonatomic, copy) NSString *hookSource;
@property (nonatomic, strong) NSURL *url;
@property (nonatomic, copy, nullable) NSString *targetBundleID;
@property (nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *sourceInfo;
@property (nonatomic, assign) BOOL matchedRule;
@property (nonatomic, assign) BOOL blocked;
@end

FOUNDATION_EXPORT DSOpenActionDecision * _Nullable DSHandleOpenURLAction(NSString *hookSource,
                                                                         NSURL *url,
                                                                         NSDictionary<NSString *, NSString *> * _Nullable sourceInfo,
                                                                         NSString * _Nullable observedBundleID);

FOUNDATION_EXPORT DSOpenActionDecision * _Nullable DSHandleOpenURLActionWithConfiguredBundleID(NSString *hookSource,
                                                                                                NSURL *url,
                                                                                                NSDictionary<NSString *, NSString *> * _Nullable sourceInfo,
                                                                                                NSString * _Nullable observedBundleID,
                                                                                                NSString * _Nullable configuredBundleID);

FOUNDATION_EXPORT id _Nullable DSResolvedApplicationForOpenActionDecision(DSOpenActionDecision * _Nullable decision,
                                                                          id _Nullable fallbackApplication,
                                                                          NSString *source);
FOUNDATION_EXPORT id _Nullable DSPreferredApplicationForConfiguredOpenURL(NSString *source,
                                                                          NSURL * _Nullable url,
                                                                          NSString * _Nullable configuredBundleID);
FOUNDATION_EXPORT BOOL DSConfiguredOpenURLTargetIsAvailable(NSString *source,
                                                            NSURL * _Nullable url,
                                                            NSString * _Nullable configuredBundleID,
                                                            NSError * _Nullable * _Nullable error);

FOUNDATION_EXPORT NSError *DSDefaultSchemeBlockedError(void);
FOUNDATION_EXPORT NSError *DSDefaultSchemeUnavailableError(void);

NS_ASSUME_NONNULL_END
