#import <UIKit/UIKit.h>

@class DSRootViewController;

@interface DSAppDelegate : UIResponder <UIApplicationDelegate>

@property (nonatomic, strong) UIWindow *window;

- (DSRootViewController *)rootViewController;

@end
