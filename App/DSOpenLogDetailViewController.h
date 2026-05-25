#import <UIKit/UIKit.h>
#import "DSRuleModels.h"

@interface DSOpenLogDetailViewController : UITableViewController
- (instancetype)initWithEntry:(NSDictionary<NSString *, id> *)entry
   installedOptionsByBundleID:(NSDictionary<NSString *, DSAppOption *> *)installedOptionsByBundleID;
@end
