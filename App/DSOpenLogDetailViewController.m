#import "DSOpenLogDetailViewController.h"
#import "DSRootUIHelpers.h"
#import "../Shared/DSRoutingConfig.h"

@interface DSOpenLogDetailViewController ()
@property (nonatomic, strong) NSDictionary<NSString *, id> *entry;
@property (nonatomic, strong) NSDictionary<NSString *, DSAppOption *> *installedOptionsByBundleID;
@end

@implementation DSOpenLogDetailViewController

- (instancetype)initWithEntry:(NSDictionary<NSString *,id> *)entry
   installedOptionsByBundleID:(NSDictionary<NSString *,DSAppOption *> *)installedOptionsByBundleID {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _entry = entry ?: @{};
        _installedOptionsByBundleID = installedOptionsByBundleID ?: @{};
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Log Detail";
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"DSOpenLogDetailCell"];
}

- (NSString *)titleForAppWithBundleID:(NSString *)bundleID fallbackName:(NSString *)fallbackName unknownText:(NSString *)unknownText {
    NSString *title = DSDisplayNameForBundleIDInOptions(self.installedOptionsByBundleID, bundleID);
    if (title.length == 0) {
        title = fallbackName;
    }
    if (title.length == 0) {
        title = bundleID;
    }
    return title.length > 0 ? title : unknownText;
}

- (NSString *)secondaryTextForBundleID:(NSString *)bundleID fallbackName:(NSString *)fallbackName {
    NSString *summary = DSAppSummaryForBundleIDInOptions(self.installedOptionsByBundleID, bundleID, fallbackName);
    if (summary.length > 0 && ![summary isEqualToString:(fallbackName ?: @"")] && ![summary isEqualToString:(bundleID ?: @"")]) {
        return summary;
    }
    if (bundleID.length > 0) {
        return bundleID;
    }
    return fallbackName.length > 0 ? fallbackName : @"Unavailable";
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 2 ? 4 : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"Source";
        case 1: return @"Target";
        case 2: return @"Open";
        default: return nil;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DSOpenLogDetailCell" forIndexPath:indexPath];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    content.secondaryTextProperties.color = UIColor.secondaryLabelColor;
    content.secondaryTextProperties.numberOfLines = 0;
    content.textProperties.numberOfLines = 2;
    content.imageProperties.maximumSize = CGSizeMake(34, 34);
    content.imageProperties.cornerRadius = 8;

    if (indexPath.section == 0 || indexPath.section == 1) {
        BOOL isSource = indexPath.section == 0;
        NSString *bundleID = self.entry[isSource ? kDSOpenLogSourceBundleIDKey : kDSOpenLogTargetBundleIDKey];
        NSString *name = self.entry[isSource ? kDSOpenLogSourceNameKey : kDSOpenLogTargetNameKey];
        content.text = [self titleForAppWithBundleID:bundleID fallbackName:name unknownText:(isSource ? @"Unknown source" : @"Unknown target")];
        content.secondaryText = [self secondaryTextForBundleID:bundleID fallbackName:name];
        content.image = DSOpenLogAppIconForBundleID(bundleID, isSource) ?: [UIImage systemImageNamed:@"app.dashed"];
    } else if (indexPath.row == 0) {
        content.text = @"URL";
        content.secondaryText = self.entry[kDSOpenLogURLKey] ?: @"Unavailable";
        content.image = [UIImage systemImageNamed:@"link"];
    } else if (indexPath.row == 1) {
        content.text = @"Type";
        content.secondaryText = DSOpenLogDisplayType(self.entry[kDSOpenLogTypeKey]);
        content.image = [UIImage systemImageNamed:@"arrow.triangle.branch"];
    } else if (indexPath.row == 2) {
        content.text = @"Hook";
        content.secondaryText = self.entry[kDSOpenLogHookSourceKey] ?: @"Unavailable";
        content.image = [UIImage systemImageNamed:@"bolt.horizontal"];
    } else {
        content.text = @"Time";
        content.secondaryText = DSOpenLogFormattedTimestamp(self.entry[kDSOpenLogTimestampKey]) ?: @"Unavailable";
        content.image = [UIImage systemImageNamed:@"clock"];
    }

    cell.contentConfiguration = content;
    return cell;
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point API_AVAILABLE(ios(13.0)) {
    if (indexPath.section != 2 || indexPath.row != 0) {
        return nil;
    }
    NSString *url = [self.entry[kDSOpenLogURLKey] isKindOfClass:NSString.class] ? self.entry[kDSOpenLogURLKey] : nil;
    if (url.length == 0) {
        return nil;
    }

    return [UIContextMenuConfiguration configurationWithIdentifier:nil
                                                   previewProvider:nil
                                                    actionProvider:^UIMenu * _Nullable(NSArray<UIMenuElement *> * _Nonnull suggestedActions) {
        UIAction *copyAction = [UIAction actionWithTitle:@"Copy URL"
                                                   image:[UIImage systemImageNamed:@"doc.on.doc"]
                                              identifier:nil
                                                 handler:^(__unused UIAction *action) {
            UIPasteboard.generalPasteboard.string = url;
        }];
        return [UIMenu menuWithTitle:@"" children:@[copyAction]];
    }];
}

@end
