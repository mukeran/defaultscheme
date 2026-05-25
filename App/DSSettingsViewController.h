#import <UIKit/UIKit.h>

@interface DSSettingsViewController : UITableViewController
- (instancetype)initWithRecordsMatchedOnly:(BOOL)recordsMatchedOnly;
@property (nonatomic, assign) BOOL recordsMatchedOnly;
@property (nonatomic, copy) void (^saveHandler)(BOOL recordsMatchedOnly);
@end
