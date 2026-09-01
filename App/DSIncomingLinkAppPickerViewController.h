#import <UIKit/UIKit.h>
#import "DSRuleModels.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^DSIncomingLinkAppSelectionHandler)(DSIncomingLinkOption * _Nonnull option);

@interface DSIncomingLinkAppPickerViewController : UITableViewController <UISearchResultsUpdating>

@property (nonatomic, copy) NSArray<DSIncomingLinkOption *> *options;
@property (nonatomic, copy) DSIncomingLinkAppSelectionHandler selectionHandler;

@end

NS_ASSUME_NONNULL_END
