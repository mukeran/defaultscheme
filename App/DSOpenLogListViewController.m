#import "DSOpenLogListViewController.h"
#import "DSOpenLogDetailViewController.h"
#import "DSRootUIHelpers.h"
#import "../Shared/DSRoutingConfig.h"

@implementation DSOpenLogListViewController

- (instancetype)initWithInstalledOptionsByBundleID:(NSDictionary<NSString *,DSAppOption *> *)installedOptionsByBundleID {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _installedOptionsByBundleID = installedOptionsByBundleID ?: @{};
        _logItems = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Log";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash
                                                                                           target:self
                                                                                           action:@selector(promptClearLogs)];
    [self updateClearButtonState];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"DSOpenLogCell"];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(applicationDidBecomeActive:)
                                               name:UIApplicationDidBecomeActiveNotification
                                             object:nil];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)setLogItems:(NSArray<NSDictionary<NSString *,id> *> *)logItems {
    _logItems = logItems ?: @[];
    [self updateClearButtonState];
}

- (void)updateClearButtonState {
    self.navigationItem.rightBarButtonItem.enabled = self.logItems.count > 0;
}

- (void)promptClearLogs {
    if (self.logItems.count == 0) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Clear Logs?"
                                                                   message:@"Remove all open logs?"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Clear" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        NSError *error = nil;
        if ([DSRoutingConfig clearOpenLogs:&error]) {
            self.logItems = @[];
            [self.tableView reloadData];
            return;
        }

        UIAlertController *errorAlert = [UIAlertController alertControllerWithTitle:@"Failed to Clear Logs"
                                                                            message:error.localizedDescription ?: @"Unknown error"
                                                                     preferredStyle:UIAlertControllerStyleAlert];
        [errorAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:errorAlert animated:YES completion:nil];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadLogs];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    if (!self.view.hidden) {
        [self reloadLogs];
    }
}

- (void)reloadLogs {
    self.logItems = DSSortedOpenLogs();
    [self.tableView reloadData];
}

- (NSString *)summaryForBundleID:(NSString *)bundleID fallbackName:(NSString *)fallbackName unknownText:(NSString *)unknownText {
    NSString *displayName = DSDisplayNameForBundleIDInOptions(self.installedOptionsByBundleID, bundleID);
    if (displayName.length > 0) {
        return displayName;
    }
    if (fallbackName.length > 0) {
        return fallbackName;
    }
    return unknownText;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.logItems.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return self.logItems.count == 0 ? @"No open logs yet. Open a URL scheme or Universal Link to populate this list." : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DSOpenLogCell" forIndexPath:indexPath];
    NSDictionary<NSString *, id> *entry = self.logItems[(NSUInteger)indexPath.row];

    NSString *sourceBundleID = entry[kDSOpenLogSourceBundleIDKey];
    NSString *sourceName = entry[kDSOpenLogSourceNameKey];
    NSString *targetBundleID = entry[kDSOpenLogTargetBundleIDKey];
    NSString *targetName = entry[kDSOpenLogTargetNameKey];
    NSString *url = entry[kDSOpenLogURLKey] ?: @"";
    NSString *type = DSOpenLogDisplayType(entry[kDSOpenLogTypeKey]);
    NSString *time = DSOpenLogFormattedTimestamp(entry[kDSOpenLogTimestampKey]) ?: @"Unknown time";

    NSString *sourceSummary = [self summaryForBundleID:sourceBundleID fallbackName:sourceName unknownText:@"System / Unknown source"];
    NSString *targetSummary = [self summaryForBundleID:targetBundleID fallbackName:targetName unknownText:@"Unknown target"];

    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    content.text = [NSString stringWithFormat:@"%@ → %@", sourceSummary, targetSummary];
    content.textProperties.numberOfLines = 2;
    content.secondaryText = [NSString stringWithFormat:@"%@\n%@ · %@", url.length > 0 ? url : @"Unknown URL", time, type];
    content.secondaryTextProperties.numberOfLines = 2;
    content.secondaryTextProperties.color = UIColor.secondaryLabelColor;
    content.imageProperties.maximumSize = CGSizeMake(34, 34);
    UIImage *combinedImage = DSCombinedAppIconForBundleIDs(sourceBundleID, targetBundleID);
    content.imageProperties.cornerRadius = combinedImage ? 0 : 8;
    content.image = combinedImage ?: [UIImage systemImageNamed:@"arrow.left.arrow.right.circle"];
    cell.contentConfiguration = content;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary<NSString *, id> *entry = self.logItems[(NSUInteger)indexPath.row];
    DSOpenLogDetailViewController *controller = [[DSOpenLogDetailViewController alloc] initWithEntry:entry
                                                                       installedOptionsByBundleID:self.installedOptionsByBundleID];
    [self.navigationController pushViewController:controller animated:YES];
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point API_AVAILABLE(ios(13.0)) {
    if (indexPath.row < 0 || indexPath.row >= (NSInteger)self.logItems.count) {
        return nil;
    }
    NSDictionary<NSString *, id> *entry = self.logItems[(NSUInteger)indexPath.row];
    NSString *url = [entry[kDSOpenLogURLKey] isKindOfClass:NSString.class] ? entry[kDSOpenLogURLKey] : nil;
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
