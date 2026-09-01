#import "DSIncomingLinkViewController.h"
#import "DSAppDelegate.h"
#import "DSRootViewController.h"
#import "DSIncomingLinkAppPickerViewController.h"
#import "DSForwardingSupport.h"
#import "DSLaunchServicesCompat.h"
#import "DSRootUIHelpers.h"
#import "../Shared/DSRoutingConfig.h"
#import <objc/message.h>

@interface DSIncomingLinkViewController ()
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *hintLabel;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UITextView *linkView;
@property (nonatomic, strong) UIButton *duplicateLinkButton;
@property (nonatomic, strong) UIButton *testButton;
@property (nonatomic, strong) UIButton *openWithButton;
@end

@implementation DSIncomingLinkViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Incoming Link";
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.titleLabel.text = @"Complete Link";
    self.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    self.titleLabel.textColor = UIColor.labelColor;
    self.titleLabel.numberOfLines = 1;
    [self.view addSubview:self.titleLabel];

    self.hintLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.hintLabel.text = @"Opened from an external scheme or link.";
    self.hintLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    self.hintLabel.textColor = UIColor.secondaryLabelColor;
    self.hintLabel.numberOfLines = 0;
    [self.view addSubview:self.hintLabel];

    self.scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    self.scrollView.showsVerticalScrollIndicator = YES;
    self.scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:self.scrollView];

    self.linkView = [[UITextView alloc] initWithFrame:CGRectZero];
    self.linkView.editable = NO;
    self.linkView.selectable = YES;
    self.linkView.scrollEnabled = NO;
    self.linkView.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
    self.linkView.textColor = UIColor.labelColor;
    self.linkView.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.linkView.layer.cornerRadius = 12;
    self.linkView.textContainerInset = UIEdgeInsetsMake(14, 12, 14, 12);
    self.linkView.text = self.linkString ?: @"";
    [self.scrollView addSubview:self.linkView];

    self.duplicateLinkButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *copyConfiguration = [UIButtonConfiguration filledButtonConfiguration];
    copyConfiguration.title = @"Copy Link";
    copyConfiguration.image = [UIImage systemImageNamed:@"doc.on.doc"];
    copyConfiguration.imagePlacement = NSDirectionalRectEdgeLeading;
    copyConfiguration.imagePadding = 8;
    self.duplicateLinkButton.configuration = copyConfiguration;
    [self.duplicateLinkButton addTarget:self action:@selector(copyTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.duplicateLinkButton];

    self.testButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *testConfiguration = [UIButtonConfiguration borderedButtonConfiguration];
    testConfiguration.title = @"Test This Link";
    testConfiguration.image = [UIImage systemImageNamed:@"checkmark.shield"];
    testConfiguration.imagePlacement = NSDirectionalRectEdgeLeading;
    testConfiguration.imagePadding = 8;
    self.testButton.configuration = testConfiguration;
    [self.testButton addTarget:self action:@selector(testTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.testButton];

    self.openWithButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *openWithConfiguration = [UIButtonConfiguration tintedButtonConfiguration];
    openWithConfiguration.title = @"Open With";
    openWithConfiguration.image = [UIImage systemImageNamed:@"arrow.up.forward.app"];
    openWithConfiguration.imagePlacement = NSDirectionalRectEdgeLeading;
    openWithConfiguration.imagePadding = 8;
    self.openWithButton.configuration = openWithConfiguration;
    [self.openWithButton addTarget:self action:@selector(openWithTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.openWithButton];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                                                                             target:self
                                                                                             action:@selector(closeTapped)];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = CGRectGetWidth(self.view.bounds);
    CGFloat top = self.view.safeAreaInsets.top + 16;
    CGFloat contentWidth = width - 32;

    self.titleLabel.frame = CGRectMake(16, top, contentWidth, 24);
    self.hintLabel.frame = CGRectMake(16, CGRectGetMaxY(self.titleLabel.frame) + 5, contentWidth, 40);

    self.duplicateLinkButton.frame = CGRectMake(16, CGRectGetMaxY(self.hintLabel.frame) + 14, (contentWidth - 10) / 2.0, 44);
    self.testButton.frame = CGRectMake(CGRectGetMaxX(self.duplicateLinkButton.frame) + 10, CGRectGetMinY(self.duplicateLinkButton.frame), (contentWidth - 10) / 2.0, 44);
    self.openWithButton.frame = CGRectMake(16, CGRectGetMaxY(self.testButton.frame) + 10, contentWidth, 44);

    CGFloat linkTop = CGRectGetMaxY(self.openWithButton.frame) + 12;
    CGFloat bottomLimit = CGRectGetHeight(self.view.bounds) - 16;
    self.scrollView.frame = CGRectMake(0, linkTop, width, MAX(0, bottomLimit - linkTop));

    CGSize fittedSize = [self.linkView sizeThatFits:CGSizeMake(contentWidth, CGFLOAT_MAX)];
    CGFloat linkHeight = MAX(120, fittedSize.height + 28);
    self.linkView.frame = CGRectMake(16, 0, contentWidth, linkHeight);
    self.scrollView.contentSize = CGSizeMake(width, linkHeight);
}

- (void)openWithTapped {
    NSURL *url = [NSURL URLWithString:self.linkString ?: @""];
    if (!url) {
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<DSIncomingLinkOption *> *options = [self originalCandidatesForURL:url];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self presentAppPickerWithOptions:options];
        });
    });
}

- (NSArray<DSIncomingLinkOption *> *)originalCandidatesForURL:(NSURL *)url {
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    id workspace = [workspaceClass respondsToSelector:@selector(defaultWorkspace)] ? [workspaceClass defaultWorkspace] : nil;
    id candidatesValue = nil;
    if ([workspace respondsToSelector:@selector(applicationsAvailableForOpeningURL:)]) {
        @try {
            candidatesValue = [workspace applicationsAvailableForOpeningURL:url];
        } @catch (__unused NSException *exception) {
            candidatesValue = nil;
        }
    }
    NSArray *candidates = [candidatesValue isKindOfClass:NSArray.class] ? candidatesValue : @[];

    NSMutableDictionary<NSString *, DSIncomingLinkOption *> *optionsByBundleID = [NSMutableDictionary dictionary];
    BOOL isWebURL = [url.scheme.lowercaseString isEqualToString:@"http"] || [url.scheme.lowercaseString isEqualToString:@"https"];
    if (isWebURL) {
        [self addUniversalLinkCandidatesForURL:url intoOptions:optionsByBundleID];
    } else if ([url.scheme.lowercaseString isEqualToString:@"defaultscheme"] &&
               [self incomingURLFromPresentationURL:url]) {
        [self addUniversalLinkCandidatesForURL:[self incomingURLFromPresentationURL:url]
                                  intoOptions:optionsByBundleID];
    }

    for (id proxy in candidates) {
        NSString *bundleID = [proxy respondsToSelector:@selector(bundleIdentifier)] ? [proxy performSelector:@selector(bundleIdentifier)] : nil;
        if (![bundleID isKindOfClass:NSString.class] || bundleID.length == 0 ||
            [bundleID isEqualToString:kDSDefaultSchemeAppBundleID] ||
            optionsByBundleID[bundleID]) {
            continue;
        }

        NSString *displayName = [proxy respondsToSelector:@selector(localizedName)] ? [proxy performSelector:@selector(localizedName)] : nil;
        if (![displayName isKindOfClass:NSString.class] || displayName.length == 0) {
            displayName = bundleID;
        }
        DSIncomingLinkOption *option = [DSIncomingLinkOption new];
        option.bundleID = bundleID;
        option.displayName = displayName;
        optionsByBundleID[bundleID] = option;
    }

    if (optionsByBundleID.count == 0 && !isWebURL) {
        [self addCandidatesFromRoutingRulesForURL:url intoOptions:optionsByBundleID];
    }
    return DSSortedIncomingLinkOptions(optionsByBundleID.allValues);
}

- (NSURL *)incomingURLFromPresentationURL:(NSURL *)url {
    if (![url isKindOfClass:NSURL.class]) {
        return nil;
    }
    NSString *encodedLink = url.query ?: @"";
    if (encodedLink.length == 0) {
        return nil;
    }
    NSString *decodedLink = [encodedLink stringByRemovingPercentEncoding];
    NSURL *incomingURL = [NSURL URLWithString:decodedLink];
    if (![incomingURL.scheme.lowercaseString isEqualToString:@"http"] &&
        ![incomingURL.scheme.lowercaseString isEqualToString:@"https"]) {
        return nil;
    }
    return incomingURL;
}

- (void)addUniversalLinkCandidatesForURL:(NSURL *)url intoOptions:(NSMutableDictionary<NSString *, DSIncomingLinkOption *> *)optionsByBundleID {
    NSMutableOrderedSet<NSString *> *bundleIDs = [NSMutableOrderedSet orderedSet];
    for (NSDictionary<NSString *, id> *rule in [DSRoutingConfig systemLinkRules]) {
        if ([DSRoutingConfig matchScoreForSystemLinkRule:rule URL:url] == NSNotFound) {
            continue;
        }
        NSString *bundleID = rule[kDSLinkRuleAssociatedBundleIDKey];
        if (bundleID.length > 0) {
            [bundleIDs addObject:bundleID];
        }
    }

    NSDictionary<NSString *, id> *configuredRule = [DSRoutingConfig bestSystemLinkRuleForURL:url
                                                                                     fromRules:[DSRoutingConfig linkRulesFromConfig:[DSRoutingConfig loadConfig]]];
    NSString *configuredBundleID = configuredRule[kDSLinkRuleBundleIDKey];
    if (configuredBundleID.length > 0 &&
        ![configuredBundleID isEqualToString:kDSDefaultSchemeAppBundleID] &&
        ![configuredBundleID isEqualToString:kDSNoAppBundleSentinel]) {
        [bundleIDs addObject:configuredBundleID];
    }

    if (bundleIDs.count == 0) {
        return;
    }

    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    id workspace = [workspaceClass respondsToSelector:@selector(defaultWorkspace)] ? [workspaceClass defaultWorkspace] : nil;
    NSArray *installedApps = @[];
    if ([workspace respondsToSelector:@selector(allInstalledApplications)]) {
        @try {
            installedApps = [workspace allInstalledApplications];
        } @catch (__unused NSException *exception) {
            installedApps = @[];
        }
    }

    NSMutableDictionary<NSString *, NSString *> *namesByBundleID = [NSMutableDictionary dictionary];
    for (id app in installedApps) {
        NSString *bundleID = [app respondsToSelector:@selector(bundleIdentifier)] ? [app performSelector:@selector(bundleIdentifier)] : nil;
        if (![bundleID isKindOfClass:NSString.class] || bundleID.length == 0) {
            continue;
        }
        NSString *displayName = [app respondsToSelector:@selector(localizedName)] ? [app performSelector:@selector(localizedName)] : nil;
        if ([displayName isKindOfClass:NSString.class] && displayName.length > 0) {
            namesByBundleID[bundleID] = displayName;
        }
    }

    for (NSString *bundleID in bundleIDs) {
        if (bundleID.length == 0 || [bundleID isEqualToString:kDSDefaultSchemeAppBundleID] || optionsByBundleID[bundleID]) {
            continue;
        }
        DSIncomingLinkOption *option = [DSIncomingLinkOption new];
        option.bundleID = bundleID;
        option.displayName = namesByBundleID[bundleID] ?: bundleID;
        optionsByBundleID[bundleID] = option;
    }
}

- (void)addCandidatesFromRoutingRulesForURL:(NSURL *)url intoOptions:(NSMutableDictionary<NSString *, DSIncomingLinkOption *> *)optionsByBundleID {
    NSDictionary *config = [DSRoutingConfig loadConfig];
    NSString *scheme = url.scheme.lowercaseString;
    NSArray<NSString *> *bundleIDs = @[];

    NSDictionary<NSString *, NSString *> *schemeRules = [DSRoutingConfig schemeRulesFromConfig:config];
    NSString *schemeCandidate = scheme.length > 0 ? schemeRules[scheme] : nil;
    if (schemeCandidate.length > 0 &&
        ![schemeCandidate isEqualToString:kDSDefaultSchemeAppBundleID] &&
        ![schemeCandidate isEqualToString:kDSNoAppBundleSentinel]) {
        bundleIDs = @[schemeCandidate];
    }

    if (bundleIDs.count == 0) {
        NSDictionary<NSString *, id> *matchedRule = [DSRoutingConfig bestSystemLinkRuleForURL:url
                                                                                     fromRules:[DSRoutingConfig linkRulesFromConfig:config]];
        NSString *linkCandidate = matchedRule[kDSLinkRuleBundleIDKey];
        if (linkCandidate.length > 0 &&
            ![linkCandidate isEqualToString:kDSDefaultSchemeAppBundleID] &&
            ![linkCandidate isEqualToString:kDSNoAppBundleSentinel]) {
            bundleIDs = @[linkCandidate];
        }
    }

    for (NSString *bundleID in bundleIDs) {
        if (bundleID.length == 0 || optionsByBundleID[bundleID]) {
            continue;
        }
        DSIncomingLinkOption *option = [DSIncomingLinkOption new];
        option.bundleID = bundleID;
        option.displayName = bundleID;
        optionsByBundleID[bundleID] = option;
    }
}

- (void)presentAppPickerWithOptions:(NSArray<DSIncomingLinkOption *> *)options {
    if (options.count == 1) {
        [self openSelectedApplicationWithBundleID:options.firstObject.bundleID];
        return;
    }

    DSIncomingLinkAppPickerViewController *picker = [[DSIncomingLinkAppPickerViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    picker.options = options;
    __weak typeof(self) weakSelf = self;
    picker.selectionHandler = ^(DSIncomingLinkOption *option) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf openSelectedApplicationWithBundleID:option.bundleID];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) innerSelf = weakSelf;
            [innerSelf.navigationController popViewControllerAnimated:YES];
        });
    };
    [self.navigationController pushViewController:picker animated:YES];
}

- (void)openSelectedApplicationWithBundleID:(NSString *)bundleID {
    if (bundleID.length == 0) {
        return;
    }

    NSURL *url = [NSURL URLWithString:self.linkString ?: @""];
    if (!url) {
        [self showOpenError:@"The incoming link is invalid."];
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BOOL opened = [self openSelectedURL:url withBundleID:bundleID];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!opened) {
                [self showOpenError:[NSString stringWithFormat:@"Failed to open %@ with %@.",
                                                        url.absoluteString ?: @"the link",
                                                        bundleID]];
            }
        });
    });
}

- (BOOL)openSelectedURL:(NSURL *)url withBundleID:(NSString *)bundleID {
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    id workspace = [workspaceClass respondsToSelector:@selector(defaultWorkspace)] ? [workspaceClass defaultWorkspace] : nil;
    if (!workspace) {
        return NO;
    }

    NSDictionary<NSString *, id> *options = @{
        UIApplicationOpenURLOptionUniversalLinksOnly : @NO,
        kDSDefaultSchemeForwardTargetBundleIDKey : bundleID ?: @"",
    };
    BOOL hasForwardingSupport = DSForwardingSupportIsAvailable();
    if (hasForwardingSupport) {
        DSForwardingSupportCallWorkspaceBegin(bundleID);
        DSForwardingSupportSetTargetBundleID(bundleID);
    }
    BOOL opened = NO;
    @try {
        if ([workspace respondsToSelector:@selector(openURL:withOptions:)]) {
            opened = ((BOOL (*)(id, SEL, NSURL *, id))objc_msgSend)(workspace,
                                                                     @selector(openURL:withOptions:),
                                                                     url,
                                                                     options);
        }
    } @catch (__unused NSException *exception) {
        opened = NO;
    }
    if (hasForwardingSupport) {
        DSForwardingSupportCallWorkspaceEnd(bundleID);
        DSForwardingSupportSetTargetBundleID(nil);
    }
    return opened;
}

- (void)showOpenError:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Open Failed"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)copyTapped {
    if (self.linkString.length == 0) {
        return;
    }
    UIPasteboard.generalPasteboard.string = self.linkString;
}

- (void)testTapped {
    if (self.linkString.length == 0) {
        return;
    }
    DSAppDelegate *appDelegate = (DSAppDelegate *)UIApplication.sharedApplication.delegate;
    DSRootViewController *root = [appDelegate rootViewController];
    void (^openTestTool)(void) = ^{
        [root openIncomingLinkInTestTool:self.linkString];
    };
    if (self.presentingViewController) {
        [self.presentingViewController dismissViewControllerAnimated:YES completion:openTestTool];
    } else {
        openTestTool();
    }
}

- (void)closeTapped {
    [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

@end
