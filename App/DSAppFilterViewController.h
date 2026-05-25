#import <UIKit/UIKit.h>
#import "DSRuleModels.h"

@interface DSAppFilterViewController : UITableViewController <UISearchResultsUpdating>
@property (nonatomic, strong) NSArray<DSAppFilterItem *> *apps;
@property (nonatomic, copy) NSString *selectedBundleID;
@property (nonatomic, copy) DSAppFilterSelectionHandler selectionHandler;
- (instancetype)initWithApps:(NSArray<DSAppFilterItem *> *)apps selectedBundleID:(NSString *)selectedBundleID;
@end
