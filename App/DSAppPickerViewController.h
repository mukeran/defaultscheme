#import <UIKit/UIKit.h>
#import "DSRuleModels.h"

@interface DSAppPickerViewController : UITableViewController
@property (nonatomic, strong) DSRuleItem *item;
@property (nonatomic, copy) DSAppPickerSelectionHandler selectionHandler;
- (instancetype)initWithItem:(DSRuleItem *)item;
@end
