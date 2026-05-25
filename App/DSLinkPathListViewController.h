#import <UIKit/UIKit.h>
#import "DSRuleModels.h"

@interface DSLinkPathListViewController : UITableViewController
@property (nonatomic, strong) DSRuleItem *domainItem;
@property (nonatomic, copy) DSRuleItemSubtitleProvider subtitleProvider;
@property (nonatomic, copy) DSRuleItemHandler selectionHandler;
- (instancetype)initWithDomainItem:(DSRuleItem *)domainItem;
@end
