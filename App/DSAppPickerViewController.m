#import "DSAppPickerViewController.h"
#import "DSRootUIHelpers.h"
#import "../Shared/DSRoutingConfig.h"

@interface DSAppPickerViewController ()
@property (nonatomic, strong) UILabel *titleLabel;
@end

@implementation DSAppPickerViewController

- (instancetype)initWithItem:(DSRuleItem *)item {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _item = item;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = nil;
    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    NSString *title = DSLinkDisplayTitle(self.item);
    if (title.length == 0) {
        title = self.item.key;
    }
    self.titleLabel.text = title;
    self.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    self.titleLabel.textColor = UIColor.labelColor;
    self.titleLabel.userInteractionEnabled = YES;
    UILongPressGestureRecognizer *titleLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleTitleLongPress:)];
    [self.titleLabel addGestureRecognizer:titleLongPress];
    [self.titleLabel sizeToFit];
    self.navigationItem.titleView = self.titleLabel;
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"PickerCell"];
}

- (void)handleTitleLongPress:(UILongPressGestureRecognizer *)gesture {
    NSString *title = self.titleLabel.text ?: self.item.key;
    if (gesture.state != UIGestureRecognizerStateBegan || title.length == 0) {
        return;
    }
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:title
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = title;
    }]];
    NSString *fullURL = DSCopyableUniversalLinkForItem(self.item);
    if (fullURL.length > 0) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Copy full URL"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction *action) {
            UIPasteboard.generalPasteboard.string = fullURL;
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UIPopoverPresentationController *popover = sheet.popoverPresentationController;
    if (popover) {
        popover.sourceView = self.titleLabel;
        popover.sourceRect = self.titleLabel.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 2 : self.item.candidates.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"Routing" : @"Apps";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"PickerCell" forIndexPath:indexPath];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.imageView.image = nil;

    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    content.imageProperties.maximumSize = CGSizeMake(32, 32);
    content.imageProperties.cornerRadius = 7;

    NSString *current = self.item.configuredBundleID;
    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            content.text = @"System Default";
            content.secondaryText = @"Use LaunchServices order";
            cell.accessoryType = current.length == 0 ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        } else {
            content.text = @"No App";
            content.secondaryText = @"Return no candidate app";
            cell.accessoryType = [current isEqualToString:kDSNoAppBundleSentinel] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        }
    } else {
        DSAppOption *opt = self.item.candidates[(NSUInteger)indexPath.row];
        content.text = opt.displayName.length > 0 ? opt.displayName : opt.bundleID;
        content.secondaryText = opt.bundleID;
        content.image = DSIconForBundleID(opt.bundleID);
        cell.accessoryType = [opt.bundleID isEqualToString:current] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    }

    cell.contentConfiguration = content;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *selected = nil;
    if (indexPath.section == 0) {
        selected = indexPath.row == 0 ? nil : kDSNoAppBundleSentinel;
    } else {
        selected = self.item.candidates[(NSUInteger)indexPath.row].bundleID;
    }
    if (self.selectionHandler) {
        self.selectionHandler(selected);
    }
}

@end
