#import "DSLinkPathListViewController.h"
#import "DSRootUIHelpers.h"

@implementation DSLinkPathListViewController

- (instancetype)initWithDomainItem:(DSRuleItem *)domainItem {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _domainItem = domainItem;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.domainItem.key;
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"LinkPathCell"];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (NSArray<DSRuleItem *> *)displayItems {
    NSMutableArray<DSRuleItem *> *items = [NSMutableArray array];
    if (self.domainItem.domainDefaultItem) {
        [items addObject:self.domainItem.domainDefaultItem];
    }
    [items addObjectsFromArray:self.domainItem.childItems ?: @[]];
    return items;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? [self displayItems].count : 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section != 0) {
        return nil;
    }
    return @"Select a path to configure it. Domain Default applies to all paths under this domain.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"LinkPathCell" forIndexPath:indexPath];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    NSArray<DSRuleItem *> *items = [self displayItems];
    DSRuleItem *item = items[(NSUInteger)indexPath.row];
    content.text = DSLinkDisplayTitle(item);
    content.secondaryText = self.subtitleProvider ? self.subtitleProvider(item) : nil;
    content.secondaryTextProperties.color = UIColor.secondaryLabelColor;
    cell.contentConfiguration = content;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (!self.selectionHandler) {
        return;
    }
    NSArray<DSRuleItem *> *items = [self displayItems];
    DSRuleItem *item = items[(NSUInteger)indexPath.row];
    self.selectionHandler(item);
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point API_AVAILABLE(ios(13.0)) {
    NSArray<DSRuleItem *> *items = [self displayItems];
    if (indexPath.row < 0 || indexPath.row >= (NSInteger)items.count) {
        return nil;
    }
    DSRuleItem *item = items[(NSUInteger)indexPath.row];
    NSString *copyValue = item.usesLinkRules ? DSLinkDisplayTitle(item) : self.domainItem.key;
    NSString *configuredBundleID = item.configuredBundleID ?: @"";
    NSString *fullURL = DSCopyableUniversalLinkForItem(item);

    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu * _Nullable(NSArray<UIMenuElement *> * _Nonnull suggestedActions) {
        NSMutableArray<UIMenuElement *> *actions = [NSMutableArray array];
        [actions addObject:[UIAction actionWithTitle:@"Copy"
                                               image:[UIImage systemImageNamed:@"doc.on.doc"]
                                          identifier:nil
                                             handler:^(__kindof UIAction * _Nonnull action) {
            UIPasteboard.generalPasteboard.string = copyValue;
        }]];
        if (fullURL.length > 0) {
            [actions addObject:[UIAction actionWithTitle:@"Copy full URL"
                                                   image:[UIImage systemImageNamed:@"link"]
                                              identifier:nil
                                                 handler:^(__kindof UIAction * _Nonnull action) {
                UIPasteboard.generalPasteboard.string = fullURL;
            }]];
        }
        if (configuredBundleID.length > 0) {
            [actions addObject:[UIAction actionWithTitle:@"Copy Configured Bundle ID"
                                                   image:[UIImage systemImageNamed:@"doc.on.doc.fill"]
                                              identifier:nil
                                                 handler:^(__kindof UIAction * _Nonnull action) {
                UIPasteboard.generalPasteboard.string = configuredBundleID;
            }]];
        }
        return [UIMenu menuWithTitle:copyValue ?: @"" children:actions];
    }];
}

@end
