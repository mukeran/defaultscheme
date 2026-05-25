#import "DSAppFilterViewController.h"
#import "DSRootUIHelpers.h"

@interface DSAppFilterViewController ()
@property (nonatomic, copy) NSString *searchText;
@end

@implementation DSAppFilterViewController

- (instancetype)initWithApps:(NSArray<DSAppFilterItem *> *)apps selectedBundleID:(NSString *)selectedBundleID {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _apps = apps ?: @[];
        _selectedBundleID = selectedBundleID;
        _searchText = @"";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Apps";
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"AppFilterCell"];

    UISearchController *search = [[UISearchController alloc] initWithSearchResultsController:nil];
    search.obscuresBackgroundDuringPresentation = NO;
    search.searchResultsUpdater = self;
    search.searchBar.placeholder = @"Search apps or bundle IDs";
    self.navigationItem.searchController = search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
}

- (NSArray<DSAppFilterItem *> *)displayedApps {
    NSString *query = [self.searchText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString;
    if (query.length == 0) {
        return self.apps;
    }
    NSMutableArray<DSAppFilterItem *> *filtered = [NSMutableArray array];
    for (DSAppFilterItem *item in self.apps) {
        if ([item.displayName.lowercaseString containsString:query] || [item.bundleID.lowercaseString containsString:query]) {
            [filtered addObject:item];
        }
    }
    return filtered;
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    self.searchText = searchController.searchBar.text ?: @"";
    [self.view setNeedsLayout];
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self displayedApps].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @"Apps";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"AppFilterCell" forIndexPath:indexPath];
    cell.accessoryType = UITableViewCellAccessoryNone;

    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    content.imageProperties.maximumSize = CGSizeMake(32, 32);
    content.imageProperties.cornerRadius = 7;

    DSAppFilterItem *item = [self displayedApps][(NSUInteger)indexPath.row];
    content.text = item.displayName.length > 0 ? item.displayName : item.bundleID;
    content.secondaryText = [NSString stringWithFormat:@"%@  |  %lu schemes, %lu links", item.bundleID, (unsigned long)item.schemeCount, (unsigned long)item.hostCount];
    content.image = DSIconForBundleID(item.bundleID);
    cell.accessoryType = [item.bundleID isEqualToString:self.selectedBundleID] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;

    cell.contentConfiguration = content;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    DSAppFilterItem *selected = [self displayedApps][(NSUInteger)indexPath.row];
    if (self.selectionHandler) {
        self.selectionHandler(selected);
    }
}

@end
