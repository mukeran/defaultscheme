#import <UIKit/UIKit.h>
#import "DSRuleModels.h"

@interface DSOpenLogListViewController : UITableViewController
@property (nonatomic, strong) NSArray<NSDictionary<NSString *, id> *> *logItems;
@property (nonatomic, strong) NSDictionary<NSString *, DSAppOption *> *installedOptionsByBundleID;
- (instancetype)initWithInstalledOptionsByBundleID:(NSDictionary<NSString *, DSAppOption *> *)installedOptionsByBundleID;
- (void)reloadLogs;
- (void)promptClearLogs;
@end
