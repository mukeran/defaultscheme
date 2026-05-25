#import "DSTestHistoryViewController.h"

@interface DSTestHistoryViewController ()
@property (nonatomic, strong) NSMutableArray<NSString *> *historyItems;
@end

@implementation DSTestHistoryViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Recent Tests";
    self.historyItems = [[[NSUserDefaults standardUserDefaults] arrayForKey:kDSTestHistoryDefaultsKey] mutableCopy] ?: [NSMutableArray array];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"DSTestHistoryPageCell"];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.historyItems = [[[NSUserDefaults standardUserDefaults] arrayForKey:kDSTestHistoryDefaultsKey] mutableCopy] ?: [NSMutableArray array];
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.historyItems.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.historyItems.count > 0 ? @"Tap one to retest" : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return self.historyItems.count == 0 ? @"No test history yet." : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DSTestHistoryPageCell" forIndexPath:indexPath];
    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    content.text = self.historyItems[(NSUInteger)indexPath.row];
    content.secondaryText = @"Tap to retest";
    content.image = [UIImage systemImageNamed:@"clock.arrow.trianglehead.counterclockwise.rotate.90"];
    content.textProperties.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    content.secondaryTextProperties.color = UIColor.secondaryLabelColor;
    cell.contentConfiguration = content;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *selected = self.historyItems[(NSUInteger)indexPath.row];
    if (self.selectionHandler) {
        self.selectionHandler(selected);
    }
    [self.navigationController popViewControllerAnimated:YES];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) {
        return;
    }
    if (indexPath.row < 0 || indexPath.row >= (NSInteger)self.historyItems.count) {
        return;
    }
    [self.historyItems removeObjectAtIndex:(NSUInteger)indexPath.row];
    [[NSUserDefaults standardUserDefaults] setObject:self.historyItems forKey:kDSTestHistoryDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
}

@end
