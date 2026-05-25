#import "DSTestViewController.h"
#import "DSRuleModels.h"
#import "DSTestHistoryViewController.h"
#import "DSLaunchServicesCompat.h"

@interface DSTestViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *urlField;
@property (nonatomic, strong) UITextView *resultView;
@property (nonatomic, strong) UIButton *testButton;
@property (nonatomic, strong) UIButton *openButton;
@property (nonatomic, strong) UIButton *recentButton;
@property (nonatomic, strong) NSMutableArray<NSString *> *historyItems;
@end

@implementation DSTestViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Test";
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.urlField = [[UITextField alloc] initWithFrame:CGRectZero];
    self.urlField.borderStyle = UITextBorderStyleRoundedRect;
    self.urlField.placeholder = @"scheme://path or https://example.com/path";
    self.urlField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.urlField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.urlField.keyboardType = UIKeyboardTypeURL;
    self.urlField.returnKeyType = UIReturnKeyDone;
    self.urlField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.urlField.delegate = self;
    [self.view addSubview:self.urlField];

    self.testButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *testConfig = [UIButtonConfiguration filledButtonConfiguration];
    testConfig.title = @"Test Rule";
    testConfig.image = [UIImage systemImageNamed:@"checkmark.shield"];
    testConfig.imagePlacement = NSDirectionalRectEdgeLeading;
    testConfig.imagePadding = 8;
    self.testButton.configuration = testConfig;
    [self.testButton addTarget:self action:@selector(testTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.testButton];

    self.openButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *openConfig = [UIButtonConfiguration borderedButtonConfiguration];
    openConfig.title = @"Open";
    openConfig.image = [UIImage systemImageNamed:@"safari"];
    openConfig.imagePlacement = NSDirectionalRectEdgeLeading;
    openConfig.imagePadding = 8;
    self.openButton.configuration = openConfig;
    [self.openButton addTarget:self action:@selector(openTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.openButton];

    self.recentButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *recentConfig = [UIButtonConfiguration borderedButtonConfiguration];
    recentConfig.title = @"Recent Tests";
    UIImage *recentIcon = [UIImage systemImageNamed:@"clock.arrow.trianglehead.counterclockwise.rotate.90"];
    if (!recentIcon) {
        recentIcon = [UIImage systemImageNamed:@"clock.arrow.circlepath"];
    }
    if (!recentIcon) {
        recentIcon = [UIImage systemImageNamed:@"clock"];
    }
    recentConfig.image = recentIcon;
    recentConfig.imagePlacement = NSDirectionalRectEdgeLeading;
    recentConfig.imagePadding = 8;
    self.recentButton.configuration = recentConfig;
    [self.recentButton addTarget:self action:@selector(showRecentTests) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.recentButton];

    self.resultView = [[UITextView alloc] initWithFrame:CGRectZero];
    self.resultView.editable = NO;
    self.resultView.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    self.resultView.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.resultView.layer.cornerRadius = 10;
    self.resultView.textContainerInset = UIEdgeInsetsMake(12, 12, 12, 12);
    [self.view addSubview:self.resultView];
    self.historyItems = [[[NSUserDefaults standardUserDefaults] arrayForKey:kDSTestHistoryDefaultsKey] mutableCopy] ?: [NSMutableArray array];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = CGRectGetWidth(self.view.bounds);
    CGFloat top = self.view.safeAreaInsets.top + 16;
    self.urlField.frame = CGRectMake(16, top, width - 32, 42);
    self.testButton.frame = CGRectMake(16, CGRectGetMaxY(self.urlField.frame) + 12, (width - 40) / 2.0, 44);
    self.openButton.frame = CGRectMake(CGRectGetMaxX(self.testButton.frame) + 8, CGRectGetMinY(self.testButton.frame), (width - 40) / 2.0, 44);
    self.recentButton.frame = CGRectMake(16, CGRectGetMaxY(self.testButton.frame) + 10, width - 32, 38);
    CGFloat resultY = CGRectGetMaxY(self.recentButton.frame) + 12;
    self.resultView.frame = CGRectMake(16, resultY, width - 32, MAX(0, CGRectGetHeight(self.view.bounds) - resultY - 16 - self.view.safeAreaInsets.bottom));
}

- (NSURL *)enteredURL {
    NSString *text = [self.urlField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (text.length == 0) {
        return nil;
    }
    return [NSURL URLWithString:text];
}

- (NSArray *)candidatesForURL:(NSURL *)url {
    Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
    id ws = [wsClass respondsToSelector:@selector(defaultWorkspace)] ? [wsClass defaultWorkspace] : nil;
    if (!ws || ![ws respondsToSelector:@selector(applicationsAvailableForOpeningURL:)]) {
        return @[];
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id value = [ws performSelector:@selector(applicationsAvailableForOpeningURL:) withObject:url];
#pragma clang diagnostic pop
    return [value isKindOfClass:NSArray.class] ? value : @[];
}

- (NSString *)bundleIDForProxy:(id)proxy {
    if (![proxy respondsToSelector:@selector(bundleIdentifier)]) {
        return @"";
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id value = [proxy performSelector:@selector(bundleIdentifier)];
#pragma clang diagnostic pop
    return [value isKindOfClass:NSString.class] ? value : @"";
}

- (NSString *)nameForProxy:(id)proxy {
    if (![proxy respondsToSelector:@selector(localizedName)]) {
        return @"";
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id value = [proxy performSelector:@selector(localizedName)];
#pragma clang diagnostic pop
    return [value isKindOfClass:NSString.class] ? value : @"";
}

- (NSString *)resultTextForURL:(NSURL *)url {
    if (!url) {
        return @"Invalid URL.";
    }

    NSString *scheme = url.scheme.lowercaseString ?: @"";
    NSString *host = url.host.lowercaseString ?: @"";

    NSMutableString *text = [NSMutableString string];
    [text appendFormat:@"URL: %@\n", url.absoluteString];
    [text appendFormat:@"Scheme: %@\n", scheme.length > 0 ? scheme : @"(none)"];
    [text appendFormat:@"Host: %@\n\n", host.length > 0 ? host : @"(none)"];

    NSArray *candidates = [self candidatesForURL:url];
    BOOL canOpen = [UIApplication.sharedApplication canOpenURL:url];
    BOOL blocked = (!canOpen && candidates.count == 0);
    [text appendFormat:@"System canOpenURL: %@\n", canOpen ? @"YES" : @"NO"];
    [text appendFormat:@"System decision: %@\n\n", blocked ? @"Blocked" : @"Allowed"];

    [text appendFormat:@"Candidates: %lu\n", (unsigned long)candidates.count];
    for (id proxy in candidates) {
        NSString *name = [self nameForProxy:proxy];
        NSString *bundleID = [self bundleIDForProxy:proxy];
        [text appendFormat:@"- %@%@%@\n", name.length > 0 ? name : bundleID, (name.length > 0 && bundleID.length > 0) ? @"  " : @"", (name.length > 0 && bundleID.length > 0) ? bundleID : @""];
    }
    return text;
}

- (void)testTapped {
    [self.urlField resignFirstResponder];
    NSURL *url = [self enteredURL];
    [self recordHistoryWithURL:url];
    self.resultView.text = [self resultTextForURL:url];
}

- (void)openTapped {
    [self.urlField resignFirstResponder];
    NSURL *url = [self enteredURL];
    if (!url) {
        self.resultView.text = @"Invalid URL.";
        return;
    }
    [self recordHistoryWithURL:url];
    self.resultView.text = [NSString stringWithFormat:@"URL: %@\n\nOpening…", url.absoluteString];
    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:^(BOOL success) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.resultView.text = [NSString stringWithFormat:@"URL: %@\n\nOpen result: %@", url.absoluteString, success ? @"success" : @"failed"];
        });
    }];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self testTapped];
    return YES;
}

- (void)recordHistoryWithURL:(NSURL *)url {
    if (!url.absoluteString.length) {
        return;
    }
    [self.historyItems removeObject:url.absoluteString];
    [self.historyItems insertObject:url.absoluteString atIndex:0];
    while (self.historyItems.count > 12) {
        [self.historyItems removeLastObject];
    }
    [[NSUserDefaults standardUserDefaults] setObject:self.historyItems forKey:kDSTestHistoryDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)showRecentTests {
    DSTestHistoryViewController *controller = [[DSTestHistoryViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    __weak typeof(self) weakSelf = self;
    controller.selectionHandler = ^(NSString *urlString) {
        if (urlString.length == 0) {
            return;
        }
        weakSelf.urlField.text = urlString;
        [weakSelf testTapped];
    };
    [self.navigationController pushViewController:controller animated:YES];
}

@end
