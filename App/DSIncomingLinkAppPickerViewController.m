#import "DSIncomingLinkAppPickerViewController.h"
#import "DSRootUIHelpers.h"

@interface DSIncomingLinkAppPickerViewController ()
@property (nonatomic, copy) NSString *searchText;
@end

@implementation DSIncomingLinkAppPickerViewController

- (instancetype)initWithStyle:(UITableViewStyle)style {
    self = [super initWithStyle:style];
    if (self) {
        _options = @[];
        _searchText = @"";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Open With";
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"DSIncomingLinkAppCell"];

    UISearchController *search = [[UISearchController alloc] initWithSearchResultsController:nil];
    search.obscuresBackgroundDuringPresentation = NO;
    search.searchResultsUpdater = self;
    search.searchBar.placeholder = @"Search apps or bundle IDs";
    self.navigationItem.searchController = search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
}

- (NSArray<DSIncomingLinkOption *> *)displayedOptions {
    NSString *query = [self.searchText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString;
    if (query.length == 0) {
        return self.options;
    }
    NSMutableArray<DSIncomingLinkOption *> *result = [NSMutableArray array];
    for (DSIncomingLinkOption *option in self.options) {
        if ([option.displayName.lowercaseString containsString:query] ||
            [option.bundleID.lowercaseString containsString:query]) {
            [result addObject:option];
        }
    }
    return result;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self displayedOptions].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return self.options.count == 0 ? @"No apps registered this scheme or link." : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DSIncomingLinkAppCell" forIndexPath:indexPath];
    DSIncomingLinkOption *option = [self displayedOptions][(NSUInteger)indexPath.row];

    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    content.text = option.displayName.length > 0 ? option.displayName : option.bundleID;
    content.secondaryText = option.bundleID;
    content.image = DSIconForBundleID(option.bundleID);
    content.imageProperties.maximumSize = CGSizeMake(32, 32);
    content.imageProperties.cornerRadius = 7;
    cell.contentConfiguration = content;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    DSIncomingLinkOption *option = [self displayedOptions][(NSUInteger)indexPath.row];
    if (self.selectionHandler) {
        self.selectionHandler(option);
    }
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    self.searchText = searchController.searchBar.text ?: @"";
    [self.tableView reloadData];
}

@end
