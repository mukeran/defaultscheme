#import "DSRootViewController.h"
#import "DSRuleModels.h"
#import "DSRootUIHelpers.h"
#import "DSLaunchServicesCompat.h"
#import "DSAppPickerViewController.h"
#import "DSLinkPathListViewController.h"
#import "DSAppFilterViewController.h"
#import "DSSettingsViewController.h"
#import "DSTestViewController.h"
#import "DSOpenLogListViewController.h"
#import "../Shared/DSRoutingConfig.h"

static const NSInteger DSTabTagTest = 2;
static const NSInteger DSTabTagLog = 3;
static const NSInteger DSTabTagSettings = 4;
static NSString *const kDSMixedConfiguredBundleID = @"__DS_MIXED__";

@interface DSRootViewController () <UITableViewDataSource, UITableViewDelegate, UITabBarDelegate, UISearchBarDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UITabBar *tabBar;
@property (nonatomic, strong) UIView *filterBar;
@property (nonatomic, strong) UISearchBar *inlineSearchBar;
@property (nonatomic, strong) UITapGestureRecognizer *dismissKeyboardTap;
@property (nonatomic, strong) UIButton *appFilterButton;
@property (nonatomic, strong) UIButton *clearFilterButton;
@property (nonatomic, strong) NSArray<DSRuleItem *> *schemeItems;
@property (nonatomic, strong) NSArray<DSRuleItem *> *hostItems;
@property (nonatomic, strong) NSDictionary<NSString *, DSAppOption *> *installedOptionsByBundleID;
@property (nonatomic, copy) NSString *linksFooterText;
@property (nonatomic, assign) DSRuleSection currentSection;
@property (nonatomic, copy) NSString *searchText;
@property (nonatomic, copy) NSString *selectedAppBundleID;
@property (nonatomic, copy) NSString *selectedAppDisplayName;
@property (nonatomic, strong) DSTestViewController *testController;
@property (nonatomic, strong) DSOpenLogListViewController *logController;
@property (nonatomic, strong) DSSettingsViewController *settingsController;
@property (nonatomic, assign) BOOL showingTestPage;
@property (nonatomic, assign) BOOL showingLogPage;
@property (nonatomic, assign) BOOL showingSettingsPage;
@property (nonatomic, strong) UIBarButtonItem *refreshButtonItem;
@property (nonatomic, assign) BOOL rulesLoading;
@property (nonatomic, strong) UIView *rulesLoadingView;
@property (nonatomic, strong) UIActivityIndicatorView *rulesLoadingIndicator;
@property (nonatomic, strong) UILabel *rulesLoadingTitleLabel;
@property (nonatomic, strong) UILabel *rulesLoadingSubtitleLabel;
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *cachedRuleDisplaySections;
@property (nonatomic, copy) NSArray<NSString *> *cachedRuleSectionIndexTitles;
@end

@implementation DSRootViewController

- (id)ds_safeInvokeNoArgSelector:(SEL)selector onObject:(id)obj {
    if (!obj || !selector || ![obj respondsToSelector:selector]) {
        return nil;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    return [obj performSelector:selector];
#pragma clang diagnostic pop
}

- (NSString *)ds_stringByInvoking:(SEL)selector onObject:(id)obj {
    id value = [self ds_safeInvokeNoArgSelector:selector onObject:obj];
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

- (NSArray *)ds_arrayByInvoking:(SEL)selector onObject:(id)obj {
    id value = [self ds_safeInvokeNoArgSelector:selector onObject:obj];
    return [value isKindOfClass:[NSArray class]] ? value : nil;
}

- (NSDictionary *)ds_dictByInvoking:(SEL)selector onObject:(id)obj {
    id value = [self ds_safeInvokeNoArgSelector:selector onObject:obj];
    return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.currentSection = DSRuleSectionSchemes;
    self.searchText = @"";
    self.selectedAppBundleID = nil;
    self.selectedAppDisplayName = nil;
    self.title = @"URL Schemes";

    self.navigationItem.searchController = nil;

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.sectionHeaderHeight = 0;
    self.tableView.estimatedSectionHeaderHeight = 0;
    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 0;
    }
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 49, 0);
    self.tableView.scrollIndicatorInsets = self.tableView.contentInset;
    [self.view addSubview:self.tableView];
    [self configureRulesLoadingView];

    self.filterBar = [[UIView alloc] initWithFrame:CGRectZero];
    self.filterBar.backgroundColor = UIColor.systemBackgroundColor;
    self.filterBar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleBottomMargin;
    [self.view addSubview:self.filterBar];

    self.inlineSearchBar = [[UISearchBar alloc] initWithFrame:CGRectZero];
    self.inlineSearchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.inlineSearchBar.placeholder = @"Search schemes, apps, bundle IDs";
    self.inlineSearchBar.delegate = self;
    [self.filterBar addSubview:self.inlineSearchBar];

    self.dismissKeyboardTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    self.dismissKeyboardTap.cancelsTouchesInView = NO;
    [self.tableView addGestureRecognizer:self.dismissKeyboardTap];

    self.appFilterButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.appFilterButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    self.appFilterButton.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.appFilterButton.layer.cornerRadius = 10;
    self.appFilterButton.clipsToBounds = YES;
    [self.appFilterButton addTarget:self action:@selector(showAppFilter) forControlEvents:UIControlEventTouchUpInside];
    [self.filterBar addSubview:self.appFilterButton];

    self.clearFilterButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.clearFilterButton.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.clearFilterButton.layer.cornerRadius = 10;
    self.clearFilterButton.clipsToBounds = YES;
    [self.clearFilterButton setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    [self.clearFilterButton addTarget:self action:@selector(clearAppFilter) forControlEvents:UIControlEventTouchUpInside];
    [self.filterBar addSubview:self.clearFilterButton];

    UIImage *schemeIcon = [UIImage systemImageNamed:@"link"];
    UIImage *linkIcon = [UIImage systemImageNamed:@"globe"];
    UIImage *testIcon = [UIImage systemImageNamed:@"testtube.2"];
    UIImage *logIcon = [UIImage systemImageNamed:@"clock"];
    UIImage *settingsIcon = [UIImage systemImageNamed:@"gearshape"];
    if (!testIcon) {
        testIcon = [UIImage systemImageNamed:@"flask"];
    }
    UITabBarItem *schemeItem = [[UITabBarItem alloc] initWithTitle:@"Schemes" image:schemeIcon tag:DSRuleSectionSchemes];
    UITabBarItem *hostItem = [[UITabBarItem alloc] initWithTitle:@"Links" image:linkIcon tag:DSRuleSectionHosts];
    UITabBarItem *testItem = [[UITabBarItem alloc] initWithTitle:@"Test" image:testIcon tag:DSTabTagTest];
    UITabBarItem *logItem = [[UITabBarItem alloc] initWithTitle:@"Log" image:logIcon tag:DSTabTagLog];
    UITabBarItem *settingsItem = [[UITabBarItem alloc] initWithTitle:@"Settings" image:settingsIcon tag:DSTabTagSettings];
    self.tabBar = [[UITabBar alloc] initWithFrame:CGRectZero];
    self.tabBar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    self.tabBar.delegate = self;
    self.tabBar.items = @[schemeItem, hostItem, testItem, logItem, settingsItem];
    self.tabBar.selectedItem = schemeItem;
    [self.view addSubview:self.tabBar];

    self.testController = [DSTestViewController new];
    [self addChildViewController:self.testController];
    [self.view addSubview:self.testController.view];
    [self.testController didMoveToParentViewController:self];
    self.testController.view.hidden = YES;

    self.logController = [[DSOpenLogListViewController alloc] initWithInstalledOptionsByBundleID:@{}];
    [self addChildViewController:self.logController];
    [self.view addSubview:self.logController.view];
    [self.logController didMoveToParentViewController:self];
    self.logController.view.hidden = YES;

    BOOL recordsMatchedOnly = [DSRoutingConfig openLogRecordsMatchedOnlyFromConfig:[DSRoutingConfig loadConfig]];
    self.settingsController = [[DSSettingsViewController alloc] initWithRecordsMatchedOnly:recordsMatchedOnly];
    __weak typeof(self) weakSelf = self;
    self.settingsController.saveHandler = ^(BOOL matchedOnly) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        NSMutableDictionary *cfg = [[DSRoutingConfig loadConfig] mutableCopy] ?: [NSMutableDictionary dictionary];
        cfg[kDSOpenLogRecordMatchedOnlyKey] = @(matchedOnly);
        NSError *error = nil;
        if (![DSRoutingConfig saveConfig:cfg error:&error]) {
            [strongSelf showMessage:error.localizedDescription ?: @"Failed to save settings."];
            return;
        }
        NSString *syncFailureMessage = [strongSelf routeConfigMirrorSyncFailureMessage];
        DSKillProcesses(@[@"lsd"]);
        if (syncFailureMessage.length > 0) {
            [strongSelf showMessage:syncFailureMessage];
        }
    };
    [self addChildViewController:self.settingsController];
    [self.view addSubview:self.settingsController.view];
    [self.settingsController didMoveToParentViewController:self];
    self.settingsController.view.hidden = YES;

    self.refreshButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                            target:self
                                                                            action:@selector(reloadData)];
    self.navigationItem.leftBarButtonItem = nil;
    [self updateAppFilterHeader];
    [self updateNavigationItems];
    [self reloadData];
}

- (void)configureRulesLoadingView {
    UIView *container = [[UIView alloc] initWithFrame:self.tableView.bounds];
    container.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    container.backgroundColor = UIColor.clearColor;

    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 10;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:stack];

    UIActivityIndicatorView *indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    indicator.hidesWhenStopped = NO;
    [stack addArrangedSubview:indicator];

    UILabel *titleLabel = [UILabel new];
    titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    titleLabel.textColor = UIColor.labelColor;
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [stack addArrangedSubview:titleLabel];

    UILabel *subtitleLabel = [UILabel new];
    subtitleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    subtitleLabel.textColor = UIColor.secondaryLabelColor;
    subtitleLabel.textAlignment = NSTextAlignmentCenter;
    subtitleLabel.numberOfLines = 2;
    [stack addArrangedSubview:subtitleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:container.centerYAnchor constant:-36.0],
        [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:container.leadingAnchor constant:32.0],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:container.trailingAnchor constant:-32.0],
    ]];

    self.rulesLoadingView = container;
    self.rulesLoadingIndicator = indicator;
    self.rulesLoadingTitleLabel = titleLabel;
    self.rulesLoadingSubtitleLabel = subtitleLabel;
}

- (BOOL)isShowingRulesLoadingState {
    if (!self.rulesLoading || self.showingTestPage || self.showingLogPage) {
        return NO;
    }
    return [self currentItems].count == 0;
}

- (void)updateRulesLoadingState {
    BOOL showing = [self isShowingRulesLoadingState];
    if (showing) {
        BOOL loadingLinks = self.currentSection == DSRuleSectionHosts;
        self.rulesLoadingTitleLabel.text = loadingLinks ? @"Loading Universal Links" : @"Loading URL Schemes";
        self.rulesLoadingSubtitleLabel.text = @"Reading installed apps and saved routing rules…";
        [self.rulesLoadingIndicator startAnimating];
        self.tableView.backgroundView = self.rulesLoadingView;
        self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    } else {
        [self.rulesLoadingIndicator stopAnimating];
        if (self.tableView.backgroundView == self.rulesLoadingView) {
            self.tableView.backgroundView = nil;
        }
        self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    }
}

- (void)updateNavigationItems {
    if (self.showingTestPage || self.showingSettingsPage) {
        self.navigationItem.leftBarButtonItem = nil;
        self.navigationItem.rightBarButtonItems = nil;
        return;
    }
    if (self.showingLogPage) {
        self.navigationItem.leftBarButtonItem = nil;
        self.navigationItem.rightBarButtonItems = self.logController.navigationItem.rightBarButtonItem ? @[self.logController.navigationItem.rightBarButtonItem] : nil;
        return;
    }
    self.navigationItem.leftBarButtonItem = nil;
    NSMutableArray<UIBarButtonItem *> *items = [NSMutableArray array];
    if (self.refreshButtonItem) {
        [items addObject:self.refreshButtonItem];
    }
    self.navigationItem.rightBarButtonItems = items;
}

- (void)refreshOpenLogController {
    self.logController.installedOptionsByBundleID = self.installedOptionsByBundleID ?: @{};
    if (self.logController.isViewLoaded) {
        [self.logController reloadLogs];
    } else {
        self.logController.logItems = DSSortedOpenLogs();
    }
}

- (void)updateTitle {
    if (self.showingTestPage) {
        self.title = @"Test";
        return;
    }
    if (self.showingLogPage) {
        self.title = @"Log";
        return;
    }
    if (self.showingSettingsPage) {
        self.title = @"Settings";
        return;
    }
    self.title = self.currentSection == DSRuleSectionSchemes ? @"URL Schemes" : @"Universal Links";
}

- (void)updateAppFilterHeader {
    NSString *title = self.selectedAppDisplayName.length > 0 ? self.selectedAppDisplayName : @"Filter by App";
    NSString *subtitle = self.selectedAppBundleID.length > 0 ? self.selectedAppBundleID : @"Filter by app";
    UIImage *image = self.selectedAppBundleID.length > 0 ? DSImageScaledToSize(DSIconForBundleID(self.selectedAppBundleID), CGSizeMake(24, 24)) : [UIImage systemImageNamed:@"app.badge"];

    UIButtonConfiguration *configuration = [UIButtonConfiguration plainButtonConfiguration];
    configuration.title = title;
    configuration.subtitle = subtitle;
    configuration.image = image;
    configuration.imagePlacement = NSDirectionalRectEdgeLeading;
    configuration.imagePadding = 10;
    configuration.contentInsets = NSDirectionalEdgeInsetsMake(8, 12, 8, 12);
    configuration.titleAlignment = UIButtonConfigurationTitleAlignmentLeading;
    configuration.preferredSymbolConfigurationForImage = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightRegular];
    self.appFilterButton.configuration = configuration;
    self.appFilterButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.clearFilterButton.hidden = self.selectedAppBundleID.length == 0;
    [self updateNavigationItems];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat bottomInset = self.view.safeAreaInsets.bottom;
    CGFloat tabHeight = 49.0 + bottomInset;
    CGFloat searchHeight = 44.0;
    CGFloat filterHeight = 50.0;
    CGFloat topInset = self.view.safeAreaInsets.top;
    CGRect bounds = self.view.bounds;
    CGFloat contentTop = topInset + searchHeight + filterHeight;
    self.tabBar.frame = CGRectMake(0, CGRectGetHeight(bounds) - tabHeight, CGRectGetWidth(bounds), tabHeight);
    self.filterBar.frame = CGRectMake(0, topInset, CGRectGetWidth(bounds), searchHeight + filterHeight);
    self.inlineSearchBar.frame = CGRectMake(8, 0, CGRectGetWidth(bounds) - 16, searchHeight);
    CGFloat clearWidth = self.selectedAppBundleID.length > 0 ? 46.0 : 0.0;
    CGFloat gap = self.selectedAppBundleID.length > 0 ? 8.0 : 0.0;
    CGFloat controlsY = searchHeight + 2;
    self.appFilterButton.frame = CGRectMake(16, controlsY, MAX(0, CGRectGetWidth(bounds) - 32 - clearWidth - gap), 42);
    self.clearFilterButton.frame = CGRectMake(CGRectGetMaxX(self.appFilterButton.frame) + gap, controlsY, clearWidth, 42);
    self.tableView.frame = CGRectMake(0, contentTop, CGRectGetWidth(bounds), MAX(0, CGRectGetHeight(bounds) - contentTop - tabHeight));
    self.rulesLoadingView.frame = self.tableView.bounds;
    self.tableView.contentInset = UIEdgeInsetsMake(12, 0, 0, 0);
    self.tableView.scrollIndicatorInsets = self.tableView.contentInset;
    self.testController.view.frame = CGRectMake(0, topInset, CGRectGetWidth(bounds), MAX(0, CGRectGetHeight(bounds) - topInset - tabHeight));
    self.logController.view.frame = CGRectMake(0, topInset, CGRectGetWidth(bounds), MAX(0, CGRectGetHeight(bounds) - topInset - tabHeight));
    self.settingsController.view.frame = CGRectMake(0, topInset, CGRectGetWidth(bounds), MAX(0, CGRectGetHeight(bounds) - topInset - tabHeight));
    [self.view bringSubviewToFront:self.filterBar];
    [self.view bringSubviewToFront:self.tabBar];
}

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar {
    if (searchBar == self.inlineSearchBar) {
        [self.inlineSearchBar setShowsCancelButton:YES animated:YES];
        [self.view setNeedsLayout];
    }
}

- (void)searchBarTextDidEndEditing:(UISearchBar *)searchBar {
    if (searchBar == self.inlineSearchBar) {
        [self.inlineSearchBar setShowsCancelButton:NO animated:YES];
        [self.view setNeedsLayout];
    }
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (searchBar != self.inlineSearchBar) {
        return;
    }
    self.searchText = searchText ?: @"";
    [self reloadRuleTable];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [self dismissKeyboard];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    if (searchBar != self.inlineSearchBar) {
        return;
    }
    [self dismissKeyboard];
}

- (void)dismissKeyboard {
    [self.inlineSearchBar resignFirstResponder];
    [self.inlineSearchBar setShowsCancelButton:NO animated:YES];
    [self.view endEditing:YES];
}

- (void)switchToSection:(DSRuleSection)section {
    self.showingTestPage = NO;
    self.showingLogPage = NO;
    self.showingSettingsPage = NO;
    self.currentSection = section;
    self.inlineSearchBar.placeholder = self.currentSection == DSRuleSectionSchemes ? @"Search schemes, apps, bundle IDs" : @"Search domains, paths, apps, bundle IDs";
    [self updateTitle];
    [self updateNavigationItems];
    [self reloadRuleTable];
}

- (void)tabBar:(UITabBar *)tabBar didSelectItem:(UITabBarItem *)item {
    [self dismissKeyboard];
    if (item.tag == DSTabTagTest) {
        self.showingTestPage = YES;
        self.showingLogPage = NO;
        self.showingSettingsPage = NO;
        self.testController.view.hidden = NO;
        self.logController.view.hidden = YES;
        self.settingsController.view.hidden = YES;
        self.filterBar.hidden = YES;
        self.tableView.hidden = YES;
        [self updateRulesLoadingState];
        [self updateTitle];
        [self updateNavigationItems];
        return;
    }
    if (item.tag == DSTabTagLog) {
        self.showingTestPage = NO;
        self.showingLogPage = YES;
        self.showingSettingsPage = NO;
        self.testController.view.hidden = YES;
        self.logController.view.hidden = NO;
        self.settingsController.view.hidden = YES;
        self.filterBar.hidden = YES;
        self.tableView.hidden = YES;
        [self refreshOpenLogController];
        [self updateRulesLoadingState];
        [self updateTitle];
        [self updateNavigationItems];
        return;
    }
    if (item.tag == DSTabTagSettings) {
        self.showingTestPage = NO;
        self.showingLogPage = NO;
        self.showingSettingsPage = YES;
        self.testController.view.hidden = YES;
        self.logController.view.hidden = YES;
        self.settingsController.view.hidden = NO;
        self.filterBar.hidden = YES;
        self.tableView.hidden = YES;
        self.settingsController.recordsMatchedOnly = [DSRoutingConfig openLogRecordsMatchedOnlyFromConfig:[DSRoutingConfig loadConfig]];
        [self.settingsController.tableView reloadData];
        [self updateRulesLoadingState];
        [self updateTitle];
        [self updateNavigationItems];
        return;
    }
    self.testController.view.hidden = YES;
    self.logController.view.hidden = YES;
    self.settingsController.view.hidden = YES;
    self.filterBar.hidden = NO;
    self.tableView.hidden = NO;
    [self updateRulesLoadingState];
    [self switchToSection:(DSRuleSection)item.tag];
}

- (void)reloadData {
    self.rulesLoading = YES;
    [self reloadRuleTable];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<DSRuleItem *> *schemes = @[];
        NSArray<DSRuleItem *> *hosts = @[];
        NSDictionary<NSString *, DSAppOption *> *installedOptions = @{};
        NSString *linksFooterText = @"Select a domain to view and configure its paths.";
        @try {
            NSDictionary *cfg = [DSRoutingConfig loadConfig];
            NSDictionary<NSString *, NSString *> *schemeRules = [DSRoutingConfig schemeRulesFromConfig:cfg];
            NSDictionary<NSString *, NSString *> *hostRules = [DSRoutingConfig hostRulesFromConfig:cfg];
            NSArray<NSDictionary<NSString *, id> *> *linkRules = [DSRoutingConfig linkRulesFromConfig:cfg];
            NSDictionary<NSString *, id> *swcSnapshot = [DSRoutingConfig sharedWebCredentialsSnapshot];

            Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
            id ws = nil;
            if ([wsClass respondsToSelector:@selector(defaultWorkspace)]) {
                ws = [wsClass defaultWorkspace];
            }
            NSArray *allApps = [self ds_arrayByInvoking:@selector(allInstalledApplications) onObject:ws];
            if (!allApps) {
                allApps = @[];
            }
            installedOptions = [self installedOptionsByBundleIDForApps:allApps];
            schemes = [self buildSchemeItems:allApps workspace:ws configured:schemeRules];
            hosts = [self buildLinkItemsWithInstalledOptions:installedOptions
                                             configuredHosts:hostRules
                                             configuredLinks:linkRules
                                                    snapshot:swcSnapshot];

            NSString *snapshotError = DSNormalizedRuleIdentityString(swcSnapshot[kDSSWCSnapshotErrorKey], NO);
            if (snapshotError.length > 0) {
                linksFooterText = @"Some Universal Link rules could not be loaded. Saved overrides are still shown.";
            }
        } @catch (__unused NSException *e) {
            schemes = @[];
            hosts = @[];
            installedOptions = @{};
            linksFooterText = @"Failed to load Universal Link rules.";
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self.rulesLoading = NO;
            self.schemeItems = schemes;
            self.hostItems = hosts;
            self.installedOptionsByBundleID = installedOptions;
            self.linksFooterText = linksFooterText;
            [self invalidateRuleDisplayCache];
            [self refreshOpenLogController];
            [self updateTitle];
            [self updateNavigationItems];
            [self reloadRuleTable];
        });
    });
}

- (void)addOptionWithBundleID:(NSString *)bundleID displayName:(NSString *)displayName bundlePath:(NSString *)bundlePath executableName:(NSString *)executableName toMap:(NSMutableDictionary<NSString *, NSMutableArray<DSAppOption *> *> *)map key:(NSString *)key {
    if (key.length == 0 || bundleID.length == 0) {
        return;
    }
    if (!map[key]) {
        map[key] = [NSMutableArray array];
    }
    for (DSAppOption *existing in map[key]) {
        if ([existing.bundleID isEqualToString:bundleID]) {
            if (existing.executableName.length == 0 && executableName.length > 0) {
                existing.executableName = executableName;
            }
            return;
        }
    }
    DSAppOption *opt = [DSAppOption new];
    opt.bundleID = bundleID;
    opt.displayName = displayName.length > 0 ? displayName : bundleID;
    opt.bundlePath = bundlePath;
    opt.executableName = executableName;
    [map[key] addObject:opt];
}

- (NSArray<NSDictionary *> *)installedBundleInfoDictionaries {
    NSMutableArray<NSDictionary *> *results = [NSMutableArray array];
    NSArray<NSString *> *roots = @[
        @"/var/containers/Bundle/Application",
        @"/Applications",
        @"/var/jb/Applications"
    ];
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *root in roots) {
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:root isDirectory:&isDir] || !isDir) {
            continue;
        }
        NSDirectoryEnumerator *enumerator = [fm enumeratorAtURL:[NSURL fileURLWithPath:root isDirectory:YES]
                                     includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                                                        options:NSDirectoryEnumerationSkipsHiddenFiles
                                                   errorHandler:nil];
        for (NSURL *url in enumerator) {
            if (![url.pathExtension.lowercaseString isEqualToString:@"app"]) {
                continue;
            }
            [enumerator skipDescendants];
            NSString *infoPath = [url.path stringByAppendingPathComponent:@"Info.plist"];
            NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
            if (![info isKindOfClass:NSDictionary.class]) {
                continue;
            }
            NSString *bundleID = [info[@"CFBundleIdentifier"] isKindOfClass:NSString.class] ? info[@"CFBundleIdentifier"] : nil;
            if (bundleID.length == 0) {
                continue;
            }
            NSMutableDictionary *entry = [info mutableCopy];
            entry[@"DSBundlePath"] = url.path;
            [results addObject:entry];
        }
    }
    return results;
}

- (NSArray<DSRuleItem *> *)buildSchemeItems:(NSArray *)apps workspace:(LSApplicationWorkspace *)ws configured:(NSDictionary<NSString *, NSString *> *)configured {
    NSMutableDictionary<NSString *, NSMutableArray<DSAppOption *> *> *map = [NSMutableDictionary dictionary];
    for (NSDictionary *info in [self installedBundleInfoDictionaries]) {
        NSString *bundleID = [info[@"CFBundleIdentifier"] isKindOfClass:NSString.class] ? info[@"CFBundleIdentifier"] : @"";
        NSString *name = [info[@"CFBundleDisplayName"] isKindOfClass:NSString.class] ? info[@"CFBundleDisplayName"] : nil;
        if (name.length == 0) {
            name = [info[@"CFBundleName"] isKindOfClass:NSString.class] ? info[@"CFBundleName"] : bundleID;
        }
        NSString *bundlePath = [info[@"DSBundlePath"] isKindOfClass:NSString.class] ? info[@"DSBundlePath"] : nil;
        NSString *executableName = [info[@"CFBundleExecutable"] isKindOfClass:NSString.class] ? info[@"CFBundleExecutable"] : nil;
        NSArray *urlTypes = [info[@"CFBundleURLTypes"] isKindOfClass:NSArray.class] ? info[@"CFBundleURLTypes"] : @[];
        for (id typeObj in urlTypes) {
            if (![typeObj isKindOfClass:NSDictionary.class]) {
                continue;
            }
            NSArray *schemes = [((NSDictionary *)typeObj)[@"CFBundleURLSchemes"] isKindOfClass:NSArray.class] ? ((NSDictionary *)typeObj)[@"CFBundleURLSchemes"] : @[];
            for (id obj in schemes) {
                if (![obj isKindOfClass:NSString.class]) {
                    continue;
                }
                NSString *scheme = [(NSString *)obj lowercaseString];
                [self addOptionWithBundleID:bundleID displayName:name bundlePath:bundlePath executableName:executableName toMap:map key:scheme];
            }
        }
    }

    for (id app in apps) {
        NSString *bundleID = [self ds_stringByInvoking:@selector(bundleIdentifier) onObject:app] ?: @"";
        if (bundleID.length == 0) {
            continue;
        }
        NSString *name = [self ds_stringByInvoking:@selector(localizedName) onObject:app] ?: bundleID;
        NSString *executableName = [self ds_stringByInvoking:@selector(bundleExecutable) onObject:app];
        if (executableName.length == 0) {
            executableName = [self ds_stringByInvoking:@selector(canonicalExecutablePath) onObject:app].lastPathComponent;
        }
        NSArray *schemes = [self ds_arrayByInvoking:@selector(claimedURLSchemes) onObject:app];
        if (!schemes) {
            continue;
        }
        for (id obj in schemes) {
            if (![obj isKindOfClass:[NSString class]]) {
                continue;
            }
            NSString *scheme = [(NSString *)obj lowercaseString];
            if (scheme.length == 0) {
                continue;
            }
            [self addOptionWithBundleID:bundleID displayName:name bundlePath:nil executableName:executableName toMap:map key:scheme];
        }
    }

    NSMutableArray<DSRuleItem *> *items = [NSMutableArray array];
    NSArray<NSString *> *keys = [[map allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    for (NSString *key in keys) {
        DSRuleItem *item = [DSRuleItem new];
        item.key = key;
        item.section = DSRuleSectionSchemes;
        item.candidates = [self sortedOptions:map[key]];
        item.configuredBundleID = configured[key];

        [items addObject:item];
    }

    for (NSString *key in configured) {
        if (map[key]) {
            continue;
        }
        DSRuleItem *item = [DSRuleItem new];
        item.key = key;
        item.section = DSRuleSectionSchemes;
        item.candidates = @[];
        item.configuredBundleID = configured[key];
        [items addObject:item];
    }

    return [items sortedArrayUsingComparator:^NSComparisonResult(DSRuleItem *a, DSRuleItem *b) {
        return [a.key localizedCaseInsensitiveCompare:b.key];
    }];
}

- (NSString *)linkDisplayKeyForHost:(NSString *)host hostWildcard:(BOOL)hostWildcard pathMatcher:(NSString *)pathMatcher queryMatcher:(NSString *)queryMatcher {
    NSString *displayHost = host.length > 0 ? host : @"";
    if (hostWildcard && displayHost.length > 0) {
        displayHost = [@"*." stringByAppendingString:displayHost];
    }

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (displayHost.length > 0) {
        [parts addObject:displayHost];
    }
    if (pathMatcher.length > 0) {
        [parts addObject:pathMatcher];
    }
    if (queryMatcher.length > 0) {
        [parts addObject:[@"?" stringByAppendingString:queryMatcher]];
    }
    return [parts componentsJoinedByString:@" "];
}

- (NSString *)linkRuleIdentityKeyForRule:(NSDictionary<NSString *, id> *)rule {
    if (![rule isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    NSString *ruleID = DSNormalizedRuleIdentityString(rule[kDSLinkRuleRuleIDKey], NO);
    if (ruleID.length > 0) {
        return [@"ruleid:" stringByAppendingString:ruleID];
    }

    NSString *host = DSNormalizedRuleIdentityString(rule[kDSLinkRuleHostKey], YES);
    NSString *pathMatcher = DSNormalizedRuleIdentityString(rule[kDSLinkRulePathMatcherKey], NO) ?: [DSRoutingConfig pathMatcherStringForLinkRule:rule];
    NSString *queryMatcher = DSNormalizedRuleIdentityString(rule[kDSLinkRuleQueryMatcherKey], NO);
    BOOL hostWildcard = DSNormalizedRuleIdentityBool(rule[kDSLinkRuleHostWildcardKey]);
    if (host.length == 0) {
        return nil;
    }
    return [NSString stringWithFormat:@"host:%@|path:%@|query:%@|wild:%d", host, pathMatcher ?: @"", queryMatcher ?: @"", hostWildcard];
}

- (BOOL)linkRule:(NSDictionary<NSString *, id> *)lhs hasSameIdentityAsRule:(NSDictionary<NSString *, id> *)rhs {
    NSString *lhsIdentity = [self linkRuleIdentityKeyForRule:lhs];
    NSString *rhsIdentity = [self linkRuleIdentityKeyForRule:rhs];
    return lhsIdentity.length > 0 && [lhsIdentity isEqualToString:rhsIdentity];
}

- (NSDictionary<NSString *, id> *)identityRuleForItem:(DSRuleItem *)item bundleID:(NSString *)bundleID {
    if (!item || !item.usesLinkRules) {
        return nil;
    }
    return [DSRoutingConfig normalizedLinkRuleWithRuleID:item.ruleID
                                                   host:item.ruleHost
                                            pathMatcher:item.pathMatcher
                                           queryMatcher:item.queryMatcher
                                               bundleID:bundleID
                                           hostWildcard:item.hostWildcard
                                             sourceHint:item.sourceHint];
}

- (NSDictionary<NSString *, DSAppOption *> *)installedOptionsByBundleIDForApps:(NSArray *)apps {
    NSMutableDictionary<NSString *, DSAppOption *> *map = [NSMutableDictionary dictionary];

    void (^storeOption)(NSString *, NSString *, NSString *, NSString *) = ^(NSString *bundleID, NSString *displayName, NSString *bundlePath, NSString *executableName) {
        if (bundleID.length == 0) {
            return;
        }
        DSAppOption *option = map[bundleID];
        if (!option) {
            option = [DSAppOption new];
            option.bundleID = bundleID;
            option.displayName = displayName.length > 0 ? displayName : bundleID;
            option.bundlePath = bundlePath;
            option.executableName = executableName;
            map[bundleID] = option;
            return;
        }
        if ((option.displayName.length == 0 || [option.displayName isEqualToString:option.bundleID]) && displayName.length > 0) {
            option.displayName = displayName;
        }
        if (option.bundlePath.length == 0 && bundlePath.length > 0) {
            option.bundlePath = bundlePath;
        }
        if (option.executableName.length == 0 && executableName.length > 0) {
            option.executableName = executableName;
        }
    };

    for (NSDictionary *info in [self installedBundleInfoDictionaries]) {
        NSString *bundleID = [info[@"CFBundleIdentifier"] isKindOfClass:NSString.class] ? info[@"CFBundleIdentifier"] : @"";
        NSString *displayName = [info[@"CFBundleDisplayName"] isKindOfClass:NSString.class] ? info[@"CFBundleDisplayName"] : nil;
        if (displayName.length == 0) {
            displayName = [info[@"CFBundleName"] isKindOfClass:NSString.class] ? info[@"CFBundleName"] : bundleID;
        }
        NSString *bundlePath = [info[@"DSBundlePath"] isKindOfClass:NSString.class] ? info[@"DSBundlePath"] : nil;
        NSString *executableName = [info[@"CFBundleExecutable"] isKindOfClass:NSString.class] ? info[@"CFBundleExecutable"] : nil;
        storeOption(bundleID, displayName, bundlePath, executableName);
    }

    for (id app in apps ?: @[]) {
        NSString *bundleID = [self ds_stringByInvoking:@selector(bundleIdentifier) onObject:app] ?: @"";
        NSString *displayName = [self ds_stringByInvoking:@selector(localizedName) onObject:app] ?: bundleID;
        NSString *executableName = [self ds_stringByInvoking:@selector(bundleExecutable) onObject:app];
        if (executableName.length == 0) {
            executableName = [self ds_stringByInvoking:@selector(canonicalExecutablePath) onObject:app].lastPathComponent;
        }
        storeOption(bundleID, displayName, nil, executableName);
    }

    return [map copy];
}

- (NSArray<DSAppOption *> *)optionsForBundleIDs:(NSArray<NSString *> *)bundleIDs installedOptions:(NSDictionary<NSString *, DSAppOption *> *)installedOptions {
    NSMutableArray<DSAppOption *> *result = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSString *bundleID in bundleIDs ?: @[]) {
        if (![bundleID isKindOfClass:NSString.class] || bundleID.length == 0 || [seen containsObject:bundleID]) {
            continue;
        }
        [seen addObject:bundleID];
        DSAppOption *option = installedOptions[bundleID];
        if (option) {
            [result addObject:option];
        }
    }
    return [self sortedOptions:result];
}

- (NSString *)displayNameForBundleID:(NSString *)bundleID {
    DSAppOption *option = self.installedOptionsByBundleID[bundleID];
    return option.displayName.length > 0 ? option.displayName : nil;
}

- (NSString *)appSummaryForBundleID:(NSString *)bundleID {
    if (bundleID.length == 0) {
        return nil;
    }
    NSString *displayName = [self displayNameForBundleID:bundleID];
    if (displayName.length > 0) {
        return [NSString stringWithFormat:@"%@ (%@)", displayName, bundleID];
    }
    return [NSString stringWithFormat:@"%@ (not installed)", bundleID];
}

- (NSDictionary<NSString *, NSString *> *)associatedDomainComponentsForEntry:(NSString *)entry {
    if (![entry isKindOfClass:NSString.class] || ![entry hasPrefix:@"applinks:"]) {
        return nil;
    }

    NSString *value = [[entry substringFromIndex:@"applinks:".length] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (value.length == 0) {
        return nil;
    }

    NSRange queryRange = [value rangeOfString:@"?"];
    if (queryRange.location != NSNotFound) {
        value = [value substringToIndex:queryRange.location];
    }

    NSString *host = value;
    NSString *pathMatcher = nil;
    NSRange slash = [value rangeOfString:@"/"];
    if (slash.location != NSNotFound) {
        host = [value substringToIndex:slash.location];
        NSString *rawPathMatcher = [value substringFromIndex:slash.location];
        NSDictionary<NSString *, NSString *> *normalizedRule = [DSRoutingConfig normalizedLinkRuleWithHost:host
                                                                                                pathMatcher:rawPathMatcher
                                                                                                   bundleID:@"codes.var.tweak.defaultscheme.placeholder"
                                                                                                 sourceHint:nil];
        pathMatcher = [DSRoutingConfig pathMatcherStringForLinkRule:normalizedRule];
    }

    host = [[host lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (host.length == 0) {
        return nil;
    }

    if (pathMatcher.length > 0) {
        return @{@"host": host, @"pathMatcher": pathMatcher};
    }
    return @{@"host": host};
}

- (NSArray<DSRuleItem *> *)buildLinkItemsWithInstalledOptions:(NSDictionary<NSString *, DSAppOption *> *)installedOptions
                                             configuredHosts:(NSDictionary<NSString *, NSString *> *)configuredHosts
                                             configuredLinks:(NSArray<NSDictionary<NSString *, id> *> *)configuredLinks
                                                    snapshot:(NSDictionary<NSString *, id> *)snapshot {
    NSArray<NSDictionary<NSString *, id> *> *systemRules = [DSRoutingConfig systemLinkRulesFromSnapshot:snapshot];
    NSMutableDictionary<NSString *, NSMutableDictionary *> *hostEntriesByHost = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSMutableDictionary *> *linkEntriesByIdentity = [NSMutableDictionary dictionary];
    NSMutableArray<NSMutableDictionary *> *linkEntries = [NSMutableArray array];

    for (NSDictionary<NSString *, id> *rule in systemRules) {
        NSString *host = DSNormalizedRuleIdentityString(rule[kDSLinkRuleHostKey], YES);
        NSString *associatedBundleID = DSNormalizedRuleIdentityString(rule[kDSLinkRuleAssociatedBundleIDKey], NO);
        BOOL hostWildcard = DSNormalizedRuleIdentityBool(rule[kDSLinkRuleHostWildcardKey]);
        if (host.length == 0) {
            continue;
        }

        NSMutableDictionary *hostEntry = hostEntriesByHost[host];
        if (!hostEntry) {
            hostEntry = [@{
                @"host": host,
                @"hostWildcard": @(hostWildcard),
                @"sourceHint": @"swc",
                @"bundleIDs": [NSMutableOrderedSet orderedSet]
            } mutableCopy];
            hostEntriesByHost[host] = hostEntry;
        } else if (hostWildcard) {
            hostEntry[@"hostWildcard"] = @YES;
        }
        if (associatedBundleID.length > 0) {
            [(NSMutableOrderedSet *)hostEntry[@"bundleIDs"] addObject:associatedBundleID];
        }

        NSString *pathMatcher = DSNormalizedRuleIdentityString(rule[kDSLinkRulePathMatcherKey], NO) ?: [DSRoutingConfig pathMatcherStringForLinkRule:rule];
        NSString *queryMatcher = DSNormalizedRuleIdentityString(rule[kDSLinkRuleQueryMatcherKey], NO);
        if (pathMatcher.length == 0 && queryMatcher.length == 0) {
            continue;
        }

        NSString *identity = [self linkRuleIdentityKeyForRule:rule];
        if (identity.length == 0) {
            continue;
        }

        NSMutableDictionary *entry = linkEntriesByIdentity[identity];
        if (!entry) {
            entry = [NSMutableDictionary dictionaryWithDictionary:@{
                @"host": host,
                @"hostWildcard": @(hostWildcard),
                @"sourceHint": DSNormalizedRuleIdentityString(rule[kDSLinkRuleSourceHintKey], NO) ?: @"swc",
                @"bundleIDs": [NSMutableOrderedSet orderedSet],
                @"ruleID": DSNormalizedRuleIdentityString(rule[kDSLinkRuleRuleIDKey], NO) ?: @"",
                @"patternKind": DSNormalizedRuleIdentityString(rule[kDSLinkRulePatternKindKey], NO) ?: @"",
            }];
            if (pathMatcher.length > 0) {
                entry[@"pathMatcher"] = pathMatcher;
            }
            if (queryMatcher.length > 0) {
                entry[@"queryMatcher"] = queryMatcher;
            }
            if (associatedBundleID.length > 0) {
                entry[@"associatedBundleID"] = associatedBundleID;
            }
            linkEntriesByIdentity[identity] = entry;
            [linkEntries addObject:entry];
        }
        if (associatedBundleID.length > 0) {
            [(NSMutableOrderedSet *)entry[@"bundleIDs"] addObject:associatedBundleID];
        }
    }

    for (NSString *host in configuredHosts) {
        if (host.length == 0) {
            continue;
        }
        NSMutableDictionary *hostEntry = hostEntriesByHost[host];
        if (!hostEntry) {
            hostEntry = [@{
                @"host": host,
                @"hostWildcard": @NO,
                @"sourceHint": @"configured",
                @"bundleIDs": [NSMutableOrderedSet orderedSet]
            } mutableCopy];
            hostEntriesByHost[host] = hostEntry;
        }
        NSString *configuredBundleID = DSNormalizedRuleIdentityString(configuredHosts[host], NO);
        if (configuredBundleID.length > 0) {
            hostEntry[@"configuredBundleID"] = configuredBundleID;
        }
    }

    for (NSDictionary<NSString *, id> *rule in configuredLinks) {
        NSString *configuredBundleID = DSNormalizedRuleIdentityString(rule[kDSLinkRuleBundleIDKey], NO);
        NSString *identity = [self linkRuleIdentityKeyForRule:rule];
        NSMutableDictionary *entry = identity.length > 0 ? linkEntriesByIdentity[identity] : nil;
        if (entry) {
            if (configuredBundleID.length > 0) {
                entry[@"configuredBundleID"] = configuredBundleID;
            }
            continue;
        }

        NSString *host = DSNormalizedRuleIdentityString(rule[kDSLinkRuleHostKey], YES);
        NSString *pathMatcher = DSNormalizedRuleIdentityString(rule[kDSLinkRulePathMatcherKey], NO) ?: [DSRoutingConfig pathMatcherStringForLinkRule:rule];
        NSString *queryMatcher = DSNormalizedRuleIdentityString(rule[kDSLinkRuleQueryMatcherKey], NO);
        NSString *ruleID = DSNormalizedRuleIdentityString(rule[kDSLinkRuleRuleIDKey], NO);
        if (host.length == 0 || (pathMatcher.length == 0 && queryMatcher.length == 0 && ruleID.length == 0)) {
            continue;
        }

        NSMutableDictionary *staleEntry = [NSMutableDictionary dictionaryWithDictionary:@{
            @"host": host,
            @"hostWildcard": @(DSNormalizedRuleIdentityBool(rule[kDSLinkRuleHostWildcardKey])),
            @"sourceHint": DSNormalizedRuleIdentityString(rule[kDSLinkRuleSourceHintKey], NO) ?: @"configured",
            @"bundleIDs": [NSMutableOrderedSet orderedSet],
            @"stale": @YES,
            @"ruleID": ruleID ?: @"",
            @"patternKind": DSNormalizedRuleIdentityString(rule[kDSLinkRulePatternKindKey], NO) ?: @"",
        }];
        if (pathMatcher.length > 0) {
            staleEntry[@"pathMatcher"] = pathMatcher;
        }
        if (queryMatcher.length > 0) {
            staleEntry[@"queryMatcher"] = queryMatcher;
        }
        NSString *associatedBundleID = DSNormalizedRuleIdentityString(rule[kDSLinkRuleAssociatedBundleIDKey], NO);
        if (associatedBundleID.length > 0) {
            staleEntry[@"associatedBundleID"] = associatedBundleID;
        }
        if (configuredBundleID.length > 0) {
            staleEntry[@"configuredBundleID"] = configuredBundleID;
        }
        [linkEntries addObject:staleEntry];
    }

    NSMutableArray<DSRuleItem *> *items = [NSMutableArray array];
    for (NSDictionary *entry in hostEntriesByHost.allValues) {
        NSString *host = entry[@"host"];
        if (host.length == 0) {
            continue;
        }
        DSRuleItem *item = [DSRuleItem new];
        item.ruleHost = host;
        item.section = DSRuleSectionHosts;
        item.usesLinkRules = NO;
        item.hostWildcard = DSNormalizedRuleIdentityBool(entry[@"hostWildcard"]);
        item.key = [self linkDisplayKeyForHost:host hostWildcard:item.hostWildcard pathMatcher:nil queryMatcher:nil];
        item.sourceHint = [entry[@"sourceHint"] isKindOfClass:NSString.class] ? entry[@"sourceHint"] : @"swc";
        item.candidates = [self optionsForBundleIDs:[(NSMutableOrderedSet *)entry[@"bundleIDs"] array] installedOptions:installedOptions];
        item.configuredBundleID = [entry[@"configuredBundleID"] isKindOfClass:NSString.class] ? entry[@"configuredBundleID"] : nil;
        [items addObject:item];
    }

    for (NSDictionary *entry in linkEntries) {
        NSString *host = entry[@"host"];
        NSString *pathMatcher = entry[@"pathMatcher"];
        NSString *queryMatcher = entry[@"queryMatcher"];
        NSString *ruleID = entry[@"ruleID"];
        if (host.length == 0 || (pathMatcher.length == 0 && queryMatcher.length == 0 && ruleID.length == 0)) {
            continue;
        }
        DSRuleItem *item = [DSRuleItem new];
        item.ruleHost = host;
        item.hostWildcard = DSNormalizedRuleIdentityBool(entry[@"hostWildcard"]);
        item.pathMatcher = [pathMatcher isKindOfClass:NSString.class] ? pathMatcher : nil;
        item.queryMatcher = [queryMatcher isKindOfClass:NSString.class] ? queryMatcher : nil;
        item.ruleID = [ruleID isKindOfClass:NSString.class] && ruleID.length > 0 ? ruleID : nil;
        item.key = [self linkDisplayKeyForHost:host hostWildcard:item.hostWildcard pathMatcher:item.pathMatcher queryMatcher:item.queryMatcher];
        item.sourceHint = [entry[@"sourceHint"] isKindOfClass:NSString.class] ? entry[@"sourceHint"] : @"swc";
        item.associatedBundleID = [entry[@"associatedBundleID"] isKindOfClass:NSString.class] ? entry[@"associatedBundleID"] : nil;
        item.patternKind = [entry[@"patternKind"] isKindOfClass:NSString.class] ? entry[@"patternKind"] : nil;
        item.stale = DSNormalizedRuleIdentityBool(entry[@"stale"]);
        item.section = DSRuleSectionHosts;
        item.usesLinkRules = YES;
        item.candidates = [self optionsForBundleIDs:[(NSMutableOrderedSet *)entry[@"bundleIDs"] array] installedOptions:installedOptions];
        item.configuredBundleID = [entry[@"configuredBundleID"] isKindOfClass:NSString.class] ? entry[@"configuredBundleID"] : nil;
        [items addObject:item];
    }

    return [items sortedArrayUsingComparator:^NSComparisonResult(DSRuleItem *a, DSRuleItem *b) {
        NSComparisonResult result = [a.ruleHost localizedCaseInsensitiveCompare:b.ruleHost];
        if (result != NSOrderedSame) {
            return result;
        }

        NSString *aPath = a.pathMatcher ?: @"";
        NSString *bPath = b.pathMatcher ?: @"";
        if (aPath.length == 0 && bPath.length > 0) {
            return NSOrderedAscending;
        }
        if (aPath.length > 0 && bPath.length == 0) {
            return NSOrderedDescending;
        }

        result = [aPath localizedCaseInsensitiveCompare:bPath];
        if (result != NSOrderedSame) {
            return result;
        }

        NSString *aQuery = a.queryMatcher ?: @"";
        NSString *bQuery = b.queryMatcher ?: @"";
        result = [aQuery localizedCaseInsensitiveCompare:bQuery];
        if (result != NSOrderedSame) {
            return result;
        }

        return [a.key localizedCaseInsensitiveCompare:b.key];
    }];
}

- (NSString *)effectiveConfiguredBundleIDForRepresentedItems:(NSArray<DSRuleItem *> *)items {
    NSString *resolved = nil;
    BOOL hasResolved = NO;
    for (DSRuleItem *item in items ?: @[]) {
        NSString *current = item.configuredBundleID ?: @"";
        if (!hasResolved) {
            resolved = current;
            hasResolved = YES;
            continue;
        }
        if (![resolved isEqualToString:current]) {
            return kDSMixedConfiguredBundleID;
        }
    }
    return resolved.length > 0 ? resolved : nil;
}

- (NSArray<DSRuleItem *> *)representedItemsForItem:(DSRuleItem *)item {
    if (item.representedItems.count > 0) {
        return item.representedItems;
    }
    return item ? @[item] : @[];
}

- (NSString *)effectiveConfiguredBundleIDForItem:(DSRuleItem *)item {
    return [self effectiveConfiguredBundleIDForRepresentedItems:[self representedItemsForItem:item]];
}

- (NSArray<DSAppOption *> *)mergedCandidatesForItems:(NSArray<DSRuleItem *> *)items {
    NSMutableDictionary<NSString *, DSAppOption *> *optionsByBundleID = [NSMutableDictionary dictionary];
    for (DSRuleItem *item in items ?: @[]) {
        for (DSAppOption *option in item.candidates ?: @[]) {
            if (option.bundleID.length == 0 || optionsByBundleID[option.bundleID]) {
                continue;
            }
            optionsByBundleID[option.bundleID] = option;
        }
    }
    return [self sortedOptions:optionsByBundleID.allValues];
}

- (NSString *)pathGroupingKeyForItem:(DSRuleItem *)item {
    return [NSString stringWithFormat:@"host:%@|path:%@|query:%@|wild:%d",
            item.ruleHost ?: @"",
            item.pathMatcher ?: @"",
            item.queryMatcher ?: @"",
            item.hostWildcard];
}

- (NSArray<DSRuleItem *> *)mergedPathItems:(NSArray<DSRuleItem *> *)items {
    NSMutableOrderedSet<NSString *> *orderedKeys = [NSMutableOrderedSet orderedSet];
    NSMutableDictionary<NSString *, NSMutableArray<DSRuleItem *> *> *itemsByKey = [NSMutableDictionary dictionary];

    for (DSRuleItem *item in items ?: @[]) {
        if (!item.usesLinkRules) {
            continue;
        }
        NSString *key = [self pathGroupingKeyForItem:item];
        [orderedKeys addObject:key];
        if (!itemsByKey[key]) {
            itemsByKey[key] = [NSMutableArray array];
        }
        [itemsByKey[key] addObject:item];
    }

    NSMutableArray<DSRuleItem *> *mergedItems = [NSMutableArray array];
    for (NSString *key in orderedKeys) {
        NSArray<DSRuleItem *> *groupItems = [itemsByKey[key] copy] ?: @[];
        DSRuleItem *firstItem = groupItems.firstObject;
        if (!firstItem) {
            continue;
        }
        DSRuleItem *mergedItem = [DSRuleItem new];
        mergedItem.key = firstItem.key;
        mergedItem.ruleHost = firstItem.ruleHost;
        mergedItem.pathMatcher = firstItem.pathMatcher;
        mergedItem.queryMatcher = firstItem.queryMatcher;
        mergedItem.ruleID = firstItem.ruleID;
        mergedItem.associatedBundleID = firstItem.associatedBundleID;
        mergedItem.patternKind = firstItem.patternKind;
        mergedItem.sourceHint = firstItem.sourceHint;
        mergedItem.usesLinkRules = YES;
        mergedItem.hostWildcard = firstItem.hostWildcard;
        mergedItem.stale = firstItem.stale;
        mergedItem.section = firstItem.section;
        mergedItem.candidates = [self mergedCandidatesForItems:groupItems];
        mergedItem.configuredBundleID = [self effectiveConfiguredBundleIDForRepresentedItems:groupItems];
        mergedItem.representedItems = groupItems;
        for (DSRuleItem *groupItem in groupItems) {
            if (!groupItem.stale) {
                mergedItem.stale = NO;
                break;
            }
        }
        [mergedItems addObject:mergedItem];
    }
    return mergedItems;
}

- (NSArray<DSRuleItem *> *)pathItemsForDomainItem:(DSRuleItem *)domainItem {
    NSMutableArray<DSRuleItem *> *items = [NSMutableArray array];
    if (domainItem.domainDefaultItem) {
        [items addObject:domainItem.domainDefaultItem];
    }
    [items addObjectsFromArray:domainItem.childItems ?: @[]];
    return items;
}

- (NSString *)configurationStatusForItem:(DSRuleItem *)item {
    NSString *configuredBundleID = [self effectiveConfiguredBundleIDForItem:item];
    if ([configuredBundleID isEqualToString:kDSMixedConfiguredBundleID]) {
        return @"Mixed";
    }
    if ([configuredBundleID isEqualToString:kDSNoAppBundleSentinel]) {
        return @"No App";
    }
    if (configuredBundleID.length > 0) {
        return [self appSummaryForBundleID:configuredBundleID] ?: configuredBundleID;
    }
    return @"System Default";
}

- (NSArray<DSRuleItem *> *)groupedHostItemsForDisplayFromItems:(NSArray<DSRuleItem *> *)items {
    NSMutableOrderedSet<NSString *> *orderedHosts = [NSMutableOrderedSet orderedSet];
    NSMutableDictionary<NSString *, NSMutableArray<DSRuleItem *> *> *pathItemsByHost = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, DSRuleItem *> *defaultItemsByHost = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSNumber *> *wildcardsByHost = [NSMutableDictionary dictionary];

    for (DSRuleItem *item in self.hostItems ?: @[]) {
        if (item.ruleHost.length == 0) {
            continue;
        }
        if (!item.usesLinkRules && !defaultItemsByHost[item.ruleHost]) {
            defaultItemsByHost[item.ruleHost] = item;
        }
        if (item.hostWildcard) {
            wildcardsByHost[item.ruleHost] = @YES;
        }
    }

    for (DSRuleItem *item in items ?: @[]) {
        if (item.ruleHost.length == 0) {
            continue;
        }
        [orderedHosts addObject:item.ruleHost];
        if (item.usesLinkRules) {
            if (!pathItemsByHost[item.ruleHost]) {
                pathItemsByHost[item.ruleHost] = [NSMutableArray array];
            }
            [pathItemsByHost[item.ruleHost] addObject:item];
        }
    }

    NSMutableArray<DSRuleItem *> *groups = [NSMutableArray array];
    for (NSString *host in orderedHosts) {
        DSRuleItem *group = [DSRuleItem new];
        group.section = DSRuleSectionHosts;
        group.domainGroup = YES;
        group.ruleHost = host;
        group.hostWildcard = [wildcardsByHost[host] boolValue];
        group.key = [self linkDisplayKeyForHost:host hostWildcard:group.hostWildcard pathMatcher:nil queryMatcher:nil];
        group.domainDefaultItem = defaultItemsByHost[host];
        group.childItems = [self mergedPathItems:pathItemsByHost[host]];
        group.configuredBundleID = [self effectiveConfiguredBundleIDForItem:group.domainDefaultItem];
        [groups addObject:group];
    }
    return groups;
}

- (DSRuleItem *)domainItemForHost:(NSString *)host {
    if (host.length == 0) {
        return nil;
    }
    for (DSRuleItem *item in [self groupedHostItemsForDisplayFromItems:self.hostItems]) {
        if ([item.ruleHost isEqualToString:host]) {
            return item;
        }
    }
    return nil;
}

- (NSArray<DSAppOption *> *)sortedOptions:(NSArray<DSAppOption *> *)options {
    return [options sortedArrayUsingComparator:^NSComparisonResult(DSAppOption *a, DSAppOption *b) {
        NSComparisonResult r = [a.displayName localizedCaseInsensitiveCompare:b.displayName];
        if (r == NSOrderedSame) {
            return [a.bundleID localizedCaseInsensitiveCompare:b.bundleID];
        }
        return r;
    }];
}

- (void)reloadLsdTapped {
    DSKillProcesses(@[@"lsd"]);
    [self showMessage:@"lsd reloaded."];
}

- (NSArray<DSRuleItem *> *)itemsForSelectedAppInSection:(DSRuleSection)section {
    if (self.selectedAppBundleID.length == 0) {
        return @[];
    }
    NSMutableArray<DSRuleItem *> *items = [NSMutableArray array];
    for (DSRuleItem *item in [self itemsForSection:section] ?: @[]) {
        BOOL matches = [item.configuredBundleID isEqualToString:self.selectedAppBundleID];
        if (!matches) {
            for (DSAppOption *opt in item.candidates) {
                if ([opt.bundleID isEqualToString:self.selectedAppBundleID]) {
                    matches = YES;
                    break;
                }
            }
        }
        if (matches) {
            [items addObject:item];
        }
    }
    return items;
}

- (BOOL)showsBulkRuleSection {
    return self.selectedAppBundleID.length > 0;
}

- (NSInteger)ruleListSection {
    return [self firstRuleTableSection];
}

- (NSInteger)lastRuleTableSection {
    return [self firstRuleTableSection] + [self ruleDisplaySections].count - 1;
}

- (void)showBulkRuleActions {
    if (self.selectedAppBundleID.length == 0) {
        return;
    }
    NSArray<DSRuleItem *> *items = [self itemsForSelectedAppInSection:self.currentSection];
    if (items.count == 0) {
        NSString *kind = self.currentSection == DSRuleSectionSchemes ? @"URL schemes" : @"Universal Link rules";
        [self showMessage:[NSString stringWithFormat:@"This app has no registered %@.", kind]];
        return;
    }

    NSString *name = self.selectedAppDisplayName.length > 0 ? self.selectedAppDisplayName : self.selectedAppBundleID;
    NSString *kind = self.currentSection == DSRuleSectionSchemes ? @"URL schemes" : @"Universal Link rules";
    NSString *message = [NSString stringWithFormat:@"Apply to all %lu %@ registered by %@.", (unsigned long)items.count, kind, name];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:(self.currentSection == DSRuleSectionSchemes ? @"Set App Schemes" : @"Set App Links")
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"System Default"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        [weakSelf setBulkRule:nil items:items section:weakSelf.currentSection label:@"System Default"];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"No App"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        [weakSelf setBulkRule:kDSNoAppBundleSentinel items:items section:weakSelf.currentSection label:@"No App"];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"Default to %@", name]
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        [weakSelf setBulkRule:weakSelf.selectedAppBundleID items:items section:weakSelf.currentSection label:name];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UIPopoverPresentationController *popover = sheet.popoverPresentationController;
    if (popover) {
        popover.sourceView = self.tableView;
        popover.sourceRect = CGRectMake(CGRectGetMidX(self.tableView.bounds), 0, 1, 1);
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (NSString *)routeConfigMirrorSyncFailureMessage {
    NSError *syncError = nil;
    if (DSSyncRouteConfigMirror(&syncError)) {
        return nil;
    }
    return [NSString stringWithFormat:@"Saved, but config mirror sync failed: %@", syncError.localizedDescription ?: @"unknown error"];
}

- (void)setBulkRule:(NSString *)bundleIDOrNil items:(NSArray<DSRuleItem *> *)items section:(DSRuleSection)section label:(NSString *)label {
    if (items.count == 0) {
        return;
    }
    NSMutableDictionary *cfg = [[DSRoutingConfig loadConfig] mutableCopy] ?: [NSMutableDictionary dictionary];
    for (DSRuleItem *item in items) {
        [self applyRuleBundleID:bundleIDOrNil forItem:item inConfig:cfg];
    }

    NSError *error = nil;
    if (![DSRoutingConfig saveConfig:cfg error:&error]) {
        [self showMessage:error.localizedDescription ?: @"Save failed."];
        return;
    }
    NSString *syncFailureMessage = [self routeConfigMirrorSyncFailureMessage];
    DSKillProcesses(@[@"lsd"]);
    [self reloadData];
    NSString *kind = section == DSRuleSectionSchemes ? @"schemes" : @"links";
    NSString *message = syncFailureMessage ?: [NSString stringWithFormat:@"Updated %lu %@ to %@.", (unsigned long)items.count, kind, label ?: @"System Default"];
    [self showMessage:message];
}

- (NSArray<DSAppFilterItem *> *)appFilterItems {
    NSMutableDictionary<NSString *, DSAppFilterItem *> *itemsByBundleID = [NSMutableDictionary dictionary];

    void (^addItems)(NSArray<DSRuleItem *> *, BOOL) = ^(NSArray<DSRuleItem *> *items, BOOL isScheme) {
        for (DSRuleItem *rule in items) {
            NSMutableSet<NSString *> *seen = [NSMutableSet set];
            for (DSAppOption *opt in rule.candidates) {
                if (opt.bundleID.length == 0 || [seen containsObject:opt.bundleID]) {
                    continue;
                }
                [seen addObject:opt.bundleID];
                DSAppFilterItem *filter = itemsByBundleID[opt.bundleID];
                if (!filter) {
                    filter = [DSAppFilterItem new];
                    filter.bundleID = opt.bundleID;
                    filter.displayName = opt.displayName.length > 0 ? opt.displayName : opt.bundleID;
                    itemsByBundleID[opt.bundleID] = filter;
                }
                if (isScheme) {
                    filter.schemeCount += 1;
                } else {
                    filter.hostCount += 1;
                }
            }
        }
    };

    addItems(self.schemeItems ?: @[], YES);
    addItems(self.hostItems ?: @[], NO);

    return [itemsByBundleID.allValues sortedArrayUsingComparator:^NSComparisonResult(DSAppFilterItem *a, DSAppFilterItem *b) {
        NSComparisonResult result = [a.displayName localizedCaseInsensitiveCompare:b.displayName];
        if (result == NSOrderedSame) {
            return [a.bundleID localizedCaseInsensitiveCompare:b.bundleID];
        }
        return result;
    }];
}

- (void)showAppFilter {
    [self dismissKeyboard];
    DSAppFilterViewController *controller = [[DSAppFilterViewController alloc] initWithApps:[self appFilterItems]
                                                                           selectedBundleID:self.selectedAppBundleID];
    __weak typeof(self) weakSelf = self;
    controller.selectionHandler = ^(DSAppFilterItem *itemOrNil) {
        weakSelf.selectedAppBundleID = itemOrNil.bundleID;
        weakSelf.selectedAppDisplayName = itemOrNil.displayName;
        [weakSelf updateAppFilterHeader];
        [weakSelf updateNavigationItems];
        [weakSelf.view setNeedsLayout];
        [weakSelf reloadRuleTable];
        [weakSelf.navigationController popViewControllerAnimated:YES];
    };
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)clearAppFilter {
    [self dismissKeyboard];
    self.selectedAppBundleID = nil;
    self.selectedAppDisplayName = nil;
    [self updateAppFilterHeader];
    [self updateNavigationItems];
    [self.view setNeedsLayout];
    [self reloadRuleTable];
}

- (void)showMessage:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"DefaultScheme"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSArray<DSRuleItem *> *)itemsForSection:(NSInteger)section {
    return section == DSRuleSectionSchemes ? self.schemeItems : self.hostItems;
}

- (NSArray<DSRuleItem *> *)currentItems {
    return [self itemsForSection:self.currentSection];
}

- (void)invalidateRuleDisplayCache {
    self.cachedRuleDisplaySections = nil;
    self.cachedRuleSectionIndexTitles = nil;
}

- (void)reloadRuleTable {
    [self invalidateRuleDisplayCache];
    [self updateRulesLoadingState];
    [self.tableView reloadData];
}

- (NSArray<NSDictionary<NSString *, id> *> *)ruleDisplaySections {
    if (self.cachedRuleDisplaySections.count > 0) {
        return self.cachedRuleDisplaySections;
    }
    NSString * (^titleProvider)(DSRuleItem *item) = ^NSString * _Nonnull(DSRuleItem *item) {
        return self.currentSection == DSRuleSectionHosts ? DSLinkDisplayTitle(item) : (item.key ?: @"");
    };
    NSArray<NSDictionary<NSString *, id> *> *sections = DSIndexedRuleSections([self displayedItems], titleProvider);
    if (sections.count == 0) {
        sections = @[@{ @"title": @"", @"items": @[] }];
    }
    self.cachedRuleDisplaySections = sections;
    return sections;
}

- (NSInteger)firstRuleTableSection {
    return [self showsBulkRuleSection] ? 1 : 0;
}

- (NSArray<DSRuleItem *> *)rulesInDisplaySection:(NSInteger)section {
    NSInteger displaySection = section - [self firstRuleTableSection];
    NSArray<NSDictionary<NSString *, id> *> *sections = [self ruleDisplaySections];
    if (displaySection < 0 || displaySection >= (NSInteger)sections.count) {
        return @[];
    }
    NSArray<DSRuleItem *> *items = sections[(NSUInteger)displaySection][@"items"];
    return [items isKindOfClass:NSArray.class] ? items : @[];
}

- (NSArray<NSString *> *)ruleSectionIndexTitles {
    if (self.cachedRuleSectionIndexTitles) {
        return self.cachedRuleSectionIndexTitles;
    }
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    for (NSDictionary<NSString *, id> *section in [self ruleDisplaySections]) {
        NSString *title = section[@"title"];
        if (title.length > 0) {
            [titles addObject:title];
        }
    }
    self.cachedRuleSectionIndexTitles = [titles copy];
    return self.cachedRuleSectionIndexTitles;
}

- (BOOL)item:(DSRuleItem *)item matchesSearchText:(NSString *)searchText {
    if (searchText.length == 0) {
        return YES;
    }
    NSString *needle = searchText.lowercaseString;
    NSString *configuredBundleID = [self effectiveConfiguredBundleIDForItem:item] ?: @"";
    NSString *displayTitle = item.section == DSRuleSectionHosts ? DSLinkDisplayTitle(item) : item.key;
    if ([item.key.lowercaseString containsString:needle] ||
        [displayTitle.lowercaseString containsString:needle] ||
        [configuredBundleID.lowercaseString containsString:needle]) {
        return YES;
    }
    for (DSAppOption *opt in item.candidates) {
        if ([opt.displayName.lowercaseString containsString:needle] || [opt.bundleID.lowercaseString containsString:needle]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)itemMatchesSelectedApp:(DSRuleItem *)item {
    if (self.selectedAppBundleID.length == 0) {
        return YES;
    }
    for (DSAppOption *opt in item.candidates) {
        if ([opt.bundleID isEqualToString:self.selectedAppBundleID]) {
            return YES;
        }
    }
    return [[self effectiveConfiguredBundleIDForItem:item] isEqualToString:self.selectedAppBundleID];
}

- (NSArray<DSRuleItem *> *)displayedItems {
    NSArray<DSRuleItem *> *items = [self currentItems];
    NSString *query = [self.searchText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSMutableArray<DSRuleItem *> *filtered = [NSMutableArray array];
    for (DSRuleItem *item in items) {
        if ([self itemMatchesSelectedApp:item] && [self item:item matchesSearchText:query]) {
            [filtered addObject:item];
        }
    }
    NSArray<DSRuleItem *> *result = (query.length == 0 && self.selectedAppBundleID.length == 0) ? items : filtered;
    if (self.currentSection == DSRuleSectionHosts) {
        return [self groupedHostItemsForDisplayFromItems:result];
    }
    return result;
}

- (void)showPathListForDomainItem:(DSRuleItem *)item {
    if (!item.domainGroup) {
        return;
    }
    DSRuleItem *domainItem = [self domainItemForHost:item.ruleHost] ?: item;
    DSLinkPathListViewController *controller = [[DSLinkPathListViewController alloc] initWithDomainItem:domainItem];
    controller.subtitleProvider = ^NSString * _Nullable(DSRuleItem *pathItem) {
        return [self subtitleForItem:pathItem];
    };
    __weak typeof(self) weakSelf = self;
    controller.selectionHandler = ^(DSRuleItem *selectedItem) {
        [weakSelf showPickerForItem:selectedItem];
    };
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)showPickerForItem:(DSRuleItem *)item {
    if (!item || item.domainGroup) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    DSAppPickerViewController *picker = [[DSAppPickerViewController alloc] initWithItem:item];
    picker.selectionHandler = ^(NSString *bundleIDOrNil) {
        [weakSelf setRule:bundleIDOrNil forItem:item];
        [weakSelf.navigationController popViewControllerAnimated:YES];
    };
    [self.navigationController pushViewController:picker animated:YES];
}

- (void)setDictionaryRuleBundleID:(NSString *)bundleIDOrNil forKey:(NSString *)ruleKey configKey:(NSString *)configKey inConfig:(NSMutableDictionary *)cfg {
    if (ruleKey.length == 0 || configKey.length == 0) {
        return;
    }
    NSMutableDictionary *map = [cfg[configKey] isKindOfClass:[NSDictionary class]] ? [cfg[configKey] mutableCopy] : [NSMutableDictionary dictionary];
    if (bundleIDOrNil.length == 0) {
        [map removeObjectForKey:ruleKey];
    } else {
        map[ruleKey] = bundleIDOrNil;
    }
    if (map.count > 0) {
        cfg[configKey] = map;
    } else {
        [cfg removeObjectForKey:configKey];
    }
}

- (void)setLinkRuleBundleID:(NSString *)bundleIDOrNil forItem:(DSRuleItem *)item inConfig:(NSMutableDictionary *)cfg {
    NSArray<DSRuleItem *> *representedItems = [self representedItemsForItem:item];
    NSMutableSet<NSString *> *identityKeys = [NSMutableSet set];
    NSMutableArray<NSDictionary<NSString *, id> *> *identityRules = [NSMutableArray array];

    for (DSRuleItem *representedItem in representedItems) {
        NSDictionary<NSString *, id> *identityRule = [self identityRuleForItem:representedItem bundleID:kDSNoAppBundleSentinel];
        NSString *identityKey = [self linkRuleIdentityKeyForRule:identityRule];
        if (identityRule && identityKey.length > 0 && ![identityKeys containsObject:identityKey]) {
            [identityKeys addObject:identityKey];
            [identityRules addObject:identityRule];
        }
    }
    if (identityRules.count == 0) {
        return;
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *updatedRules = [NSMutableArray array];
    for (NSDictionary<NSString *, id> *rule in [DSRoutingConfig linkRulesFromConfig:cfg]) {
        NSString *identityKey = [self linkRuleIdentityKeyForRule:rule];
        if (identityKey.length > 0 && [identityKeys containsObject:identityKey]) {
            continue;
        }
        [updatedRules addObject:rule];
    }

    if (bundleIDOrNil.length > 0) {
        for (DSRuleItem *representedItem in representedItems) {
            NSDictionary<NSString *, id> *rule = [self identityRuleForItem:representedItem bundleID:bundleIDOrNil];
            NSString *identityKey = [self linkRuleIdentityKeyForRule:rule];
            if (!rule || identityKey.length == 0 || [identityKeys containsObject:[@"saved:" stringByAppendingString:identityKey]]) {
                continue;
            }
            [identityKeys addObject:[@"saved:" stringByAppendingString:identityKey]];
            [updatedRules addObject:rule];
        }
    }

    if (updatedRules.count > 0) {
        cfg[kDSRoutingLinksKey] = updatedRules;
    } else {
        [cfg removeObjectForKey:kDSRoutingLinksKey];
    }
}

- (void)applyRuleBundleID:(NSString *)bundleIDOrNil forItem:(DSRuleItem *)item inConfig:(NSMutableDictionary *)cfg {
    if (!item || !cfg) {
        return;
    }
    if (item.section == DSRuleSectionSchemes) {
        [self setDictionaryRuleBundleID:bundleIDOrNil forKey:item.key configKey:@"schemes" inConfig:cfg];
        return;
    }
    if (item.usesLinkRules) {
        [self setLinkRuleBundleID:bundleIDOrNil forItem:item inConfig:cfg];
        return;
    }
    [self setDictionaryRuleBundleID:bundleIDOrNil forKey:item.key configKey:@"hosts" inConfig:cfg];
}

- (void)setRule:(NSString *)bundleIDOrNil forItem:(DSRuleItem *)item {
    NSMutableDictionary *cfg = [[DSRoutingConfig loadConfig] mutableCopy] ?: [NSMutableDictionary dictionary];
    [self applyRuleBundleID:bundleIDOrNil forItem:item inConfig:cfg];

    NSError *error = nil;
    if (![DSRoutingConfig saveConfig:cfg error:&error]) {
        [self showMessage:error.localizedDescription ?: @"Save failed."];
        return;
    }
    NSString *syncFailureMessage = [self routeConfigMirrorSyncFailureMessage];
    for (DSRuleItem *representedItem in [self representedItemsForItem:item]) {
        representedItem.configuredBundleID = bundleIDOrNil;
    }
    item.configuredBundleID = bundleIDOrNil;
    DSKillProcesses(@[@"lsd"]);
    [self reloadData];
    if (syncFailureMessage.length > 0) {
        [self showMessage:syncFailureMessage];
    }
}

- (NSString *)defaultDescriptionForItem:(DSRuleItem *)item {
    if (item.usesLinkRules) {
        NSString *associatedSummary = [self appSummaryForBundleID:item.associatedBundleID];
        if (associatedSummary.length > 0) {
            return [NSString stringWithFormat:@"System app: %@", associatedSummary];
        }
    }

    if (item.candidates.count == 0) {
        return item.usesLinkRules ? @"No installed SWC app candidate" : @"No installed SWC candidates";
    }

    if (!item.usesLinkRules && item.candidates.count > 1) {
        return [NSString stringWithFormat:@"Installed SWC candidates: %lu", (unsigned long)item.candidates.count];
    }

    DSAppOption *first = item.candidates.firstObject;
    NSString *label = item.usesLinkRules ? @"System app" : @"Installed SWC candidate";
    return [NSString stringWithFormat:@"%@: %@ (%@)", label, first.displayName, first.bundleID];
}

- (NSString *)sourceDescriptionForItem:(DSRuleItem *)item {
    if (item.section == DSRuleSectionSchemes) {
        return @"registered scheme";
    }

    if (item.stale) {
        return @"saved override (stale)";
    }

    NSString *sourceHint = [(item.sourceHint ?: @"") lowercaseString];
    if ([sourceHint isEqualToString:@"swc"]) {
        return @"swc.db";
    }
    if ([sourceHint isEqualToString:@"configured"]) {
        return item.usesLinkRules ? @"saved override" : @"saved host override";
    }
    if ([sourceHint isEqualToString:@"legacy"]) {
        return @"legacy rule";
    }
    if ([sourceHint isEqualToString:@"stale"]) {
        return @"saved override (stale)";
    }
    return sourceHint.length > 0 ? sourceHint : @"swc.db";
}

- (NSString *)scopeDescriptionForItem:(DSRuleItem *)item {
    if (item.section == DSRuleSectionSchemes) {
        return @"Source: registered scheme";
    }

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (item.usesLinkRules) {
        [parts addObject:item.pathMatcher.length > 0 ? [NSString stringWithFormat:@"Path: %@", item.pathMatcher] : @"Path: all"];
        if (item.queryMatcher.length > 0) {
            [parts addObject:[NSString stringWithFormat:@"Query: %@", item.queryMatcher]];
        }
    } else {
        [parts addObject:@"Scope: host fallback"];
    }
    if (item.hostWildcard) {
        [parts addObject:@"Host: wildcard"];
    }
    if (item.patternKind.length > 0) {
        [parts addObject:[NSString stringWithFormat:@"Kind: %@", item.patternKind]];
    }
    if (item.stale) {
        [parts addObject:@"Missing from current swc.db"];
    }
    [parts addObject:[NSString stringWithFormat:@"Source: %@", [self sourceDescriptionForItem:item]]];
    return [parts componentsJoinedByString:@"  •  "];
}

- (NSString *)subtitleForItem:(DSRuleItem *)item {
    if (item.domainGroup) {
        NSUInteger pathCount = item.childItems.count;
        NSString *status = [self configurationStatusForItem:item.domainDefaultItem ?: item];
        if (pathCount == 0) {
            return [NSString stringWithFormat:@"Default: %@", status];
        }
        return [NSString stringWithFormat:@"%lu path%@  •  Default: %@", (unsigned long)pathCount, pathCount == 1 ? @"" : @"s", status];
    }

    NSString *status = [self configurationStatusForItem:item];
    if (item.section == DSRuleSectionHosts && !item.usesLinkRules) {
        return [NSString stringWithFormat:@"All paths  •  %@", status];
    }
    return status;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if ([self isShowingRulesLoadingState]) {
        return 0;
    }
    return [self firstRuleTableSection] + [self ruleDisplaySections].count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if ([self showsBulkRuleSection] && section == 0) {
        return 1;
    }
    return [self rulesInDisplaySection:section].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section < [self firstRuleTableSection]) {
        return nil;
    }
    NSArray<NSDictionary<NSString *, id> *> *sections = [self ruleDisplaySections];
    NSInteger displaySection = section - [self firstRuleTableSection];
    if (displaySection < 0 || displaySection >= (NSInteger)sections.count) {
        return nil;
    }
    NSString *title = sections[(NSUInteger)displaySection][@"title"];
    return title.length > 0 ? title : nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    NSString *title = [self tableView:tableView titleForHeaderInSection:section];
    if (title.length > 0) {
        return 28.0;
    }
    if ([self showsBulkRuleSection] && section == [self ruleListSection]) {
        return 12.0;
    }
    return 0.01;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section != [self lastRuleTableSection]) {
        return nil;
    }

    NSString *baseFooter = nil;
    if (self.currentSection == DSRuleSectionSchemes) {
        baseFooter = @"Tap one row to change default app / set No App / restore system default.";
    } else {
        baseFooter = self.linksFooterText.length > 0 ? self.linksFooterText : @"Select a domain to view and configure its paths.";
    }

    if (self.selectedAppDisplayName.length > 0) {
        return [NSString stringWithFormat:@"Filtered by %@. %@", self.selectedAppDisplayName, baseFooter];
    }
    return baseFooter;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self showsBulkRuleSection] && indexPath.section == 0) {
        static NSString *bulkCellID = @"BulkRuleCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:bulkCellID];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:bulkCellID];
        }
        NSArray<DSRuleItem *> *items = [self itemsForSelectedAppInSection:self.currentSection];
        NSString *name = self.selectedAppDisplayName.length > 0 ? self.selectedAppDisplayName : self.selectedAppBundleID;
        BOOL isSchemes = self.currentSection == DSRuleSectionSchemes;
        cell.textLabel.text = isSchemes ? @"Set All Registered Schemes" : @"Set All Universal Links";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu %@ for %@", (unsigned long)items.count, isSchemes ? @"schemes" : @"links", name];
        cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
        cell.imageView.image = [UIImage systemImageNamed:@"slider.horizontal.3"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }

    static NSString *cellID = @"RuleCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellID];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    cell.imageView.image = nil;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    NSArray<DSRuleItem *> *sectionItems = [self rulesInDisplaySection:indexPath.section];
    if (indexPath.row < 0 || indexPath.row >= (NSInteger)sectionItems.count) {
        cell.textLabel.text = nil;
        cell.detailTextLabel.text = nil;
        return cell;
    }
    DSRuleItem *item = sectionItems[(NSUInteger)indexPath.row];
    cell.textLabel.text = self.currentSection == DSRuleSectionHosts ? DSLinkDisplayTitle(item) : item.key;
    cell.detailTextLabel.text = [self subtitleForItem:item];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [self dismissKeyboard];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if ([self showsBulkRuleSection] && indexPath.section == 0) {
        [self showBulkRuleActions];
        return;
    }
    NSArray<DSRuleItem *> *sectionItems = [self rulesInDisplaySection:indexPath.section];
    if (indexPath.row < 0 || indexPath.row >= (NSInteger)sectionItems.count) {
        return;
    }
    DSRuleItem *item = sectionItems[(NSUInteger)indexPath.row];
    if (self.currentSection == DSRuleSectionHosts && item.domainGroup) {
        [self showPathListForDomainItem:item];
        return;
    }
    [self showPickerForItem:item];
}

- (NSArray<NSString *> *)sectionIndexTitlesForTableView:(UITableView *)tableView {
    if (tableView != self.tableView || self.showingTestPage || self.showingLogPage || [self isShowingRulesLoadingState]) {
        return nil;
    }
    NSArray<NSString *> *titles = [self ruleSectionIndexTitles];
    return titles.count > 1 ? titles : nil;
}

- (NSInteger)tableView:(UITableView *)tableView sectionForSectionIndexTitle:(NSString *)title atIndex:(NSInteger)index {
    if (tableView != self.tableView) {
        return index;
    }
    return [self firstRuleTableSection] + index;
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point API_AVAILABLE(ios(13.0)) {
    if (tableView != self.tableView || indexPath.section < [self firstRuleTableSection]) {
        return nil;
    }
    NSArray<DSRuleItem *> *sectionItems = [self rulesInDisplaySection:indexPath.section];
    if (indexPath.row < 0 || indexPath.row >= (NSInteger)sectionItems.count) {
        return nil;
    }
    DSRuleItem *item = sectionItems[(NSUInteger)indexPath.row];
    NSString *ruleKey = self.currentSection == DSRuleSectionHosts ? DSLinkDisplayTitle(item) : (item.key ?: @"");
    NSString *configuredBundleID = [self effectiveConfiguredBundleIDForItem:item] ?: @"";
    NSString *fullURL = DSCopyableUniversalLinkForItem(item);
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu * _Nullable(NSArray<UIMenuElement *> * _Nonnull suggestedActions) {
        NSMutableArray<UIMenuElement *> *actions = [NSMutableArray array];
        [actions addObject:[UIAction actionWithTitle:@"Copy"
                                               image:[UIImage systemImageNamed:@"doc.on.doc"]
                                          identifier:nil
                                             handler:^(__kindof UIAction * _Nonnull action) {
            UIPasteboard.generalPasteboard.string = ruleKey;
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
        return [UIMenu menuWithTitle:ruleKey children:actions];
    }];
}

@end
