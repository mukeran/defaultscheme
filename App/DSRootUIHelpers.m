#import "DSRootUIHelpers.h"
#import "../Shared/DSRoutingConfig.h"
#import <objc/message.h>
#import <spawn.h>
#import <sys/wait.h>
#if DEFAULTSCHEME_ROOTHIDE
#import <roothide/roothide.h>
#endif

extern char **environ;

void DSKillProcesses(NSArray<NSString *> *processes) {
    for (NSString *process in processes) {
        if (process.length == 0) {
            continue;
        }
        pid_t pid = 0;
        const char *name = process.UTF8String;
        char *const argv[] = {"killall", "-9", (char *)name, NULL};
        posix_spawn(&pid, "/usr/bin/killall", NULL, NULL, argv, environ);
    }
}

static BOOL DSSyncDefaultSchemeHelperCommand(NSString *command, NSError **error) {
    NSMutableArray<NSString *> *helperPaths = [NSMutableArray array];
#if DEFAULTSCHEME_ROOTHIDE
    NSString *jbrootHelperPath = jbroot(@"/usr/bin/defaultschemectl");
    if (jbrootHelperPath.length > 0) {
        [helperPaths addObject:jbrootHelperPath];
    }
#endif
    [helperPaths addObjectsFromArray:@[
        @"/usr/bin/defaultschemectl",
        @"/var/jb/usr/bin/defaultschemectl",
    ]];

    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSString *lastFailure = nil;

    for (NSString *helperPath in helperPaths) {
        if (![fileManager isExecutableFileAtPath:helperPath]) {
            continue;
        }

        pid_t pid = 0;
        const char *path = helperPath.fileSystemRepresentation;
        char *const argv[] = { (char *)path, (char *)command.UTF8String, NULL };
        int spawnResult = posix_spawn(&pid, path, NULL, NULL, argv, environ);
        if (spawnResult != 0) {
            lastFailure = [NSString stringWithFormat:@"Failed to launch %@ (%d).", helperPath, spawnResult];
            continue;
        }

        int status = 0;
        if (waitpid(pid, &status, 0) < 0) {
            lastFailure = [NSString stringWithFormat:@"Failed to wait for %@.", helperPath];
            continue;
        }
        if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
            return YES;
        }
        lastFailure = [NSString stringWithFormat:@"%@ exited with status %d.", helperPath, WIFEXITED(status) ? WEXITSTATUS(status) : status];
    }

    if (error) {
        *error = [NSError errorWithDomain:@"DefaultScheme" code:7 userInfo:@{
            NSLocalizedDescriptionKey: lastFailure ?: @"defaultschemectl was not found."
        }];
    }
    return NO;
}

BOOL DSSyncRouteConfigMirror(NSError **error) {
    return DSSyncDefaultSchemeHelperCommand(@"sync-route-config-mirror", error);
}

NSString *DSDecodedDisplayString(NSString *value) {
    if (![value isKindOfClass:NSString.class] || value.length == 0) {
        return value ?: @"";
    }
    NSString *decoded = [value stringByRemovingPercentEncoding];
    return decoded.length > 0 ? decoded : value;
}

NSString *DSLinkDisplayTitle(DSRuleItem *item) {
    if (!item) {
        return @"";
    }
    if (item.domainGroup) {
        return item.key ?: item.ruleHost ?: @"";
    }
    if (!item.usesLinkRules) {
        return @"Domain Default";
    }

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSString *path = item.pathMatcher.length > 0 ? DSDecodedDisplayString(item.pathMatcher) : @"/";
    [parts addObject:path];
    if (item.queryMatcher.length > 0) {
        [parts addObject:[@"?" stringByAppendingString:DSDecodedDisplayString(item.queryMatcher)]];
    }
    return [parts componentsJoinedByString:@" "];
}

NSArray<NSDictionary<NSString *, id> *> *DSIndexedRuleSections(NSArray<DSRuleItem *> *items, NSString * (^titleProvider)(DSRuleItem *item)) {
    if (items.count == 0 || !titleProvider) {
        return @[];
    }

    UILocalizedIndexedCollation *collation = [UILocalizedIndexedCollation currentCollation];
    NSArray<NSString *> *sectionTitles = [collation sectionTitles];
    NSMutableArray<NSMutableArray<DSRuleItem *> *> *buckets = [NSMutableArray arrayWithCapacity:sectionTitles.count];
    for (NSUInteger idx = 0; idx < sectionTitles.count; idx++) {
        [buckets addObject:[NSMutableArray array]];
    }

    for (DSRuleItem *item in items) {
        NSString *title = titleProvider(item) ?: @"";
        NSInteger sectionIndex = [collation sectionForObject:(title.length > 0 ? title : @"#") collationStringSelector:@selector(description)];
        if (sectionIndex < 0 || sectionIndex >= (NSInteger)buckets.count) {
            sectionIndex = (NSInteger)buckets.count - 1;
        }
        [buckets[(NSUInteger)sectionIndex] addObject:item];
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *sections = [NSMutableArray array];
    for (NSUInteger idx = 0; idx < buckets.count; idx++) {
        NSArray<DSRuleItem *> *bucketItems = buckets[idx];
        if (bucketItems.count == 0) {
            continue;
        }
        NSArray<DSRuleItem *> *sortedItems = [bucketItems sortedArrayUsingComparator:^NSComparisonResult(DSRuleItem *lhs, DSRuleItem *rhs) {
            NSString *lhsTitle = titleProvider(lhs) ?: @"";
            NSString *rhsTitle = titleProvider(rhs) ?: @"";
            NSComparisonResult result = [lhsTitle localizedCaseInsensitiveCompare:rhsTitle];
            if (result == NSOrderedSame) {
                return [(lhs.key ?: @"") localizedCaseInsensitiveCompare:(rhs.key ?: @"")];
            }
            return result;
        }];
        [sections addObject:@{
            @"title": sectionTitles[idx],
            @"items": sortedItems
        }];
    }
    return sections;
}

NSString *DSNormalizedCopyableUniversalLinkPath(NSString *pathMatcher) {
    if (![pathMatcher isKindOfClass:NSString.class]) {
        return @"/";
    }

    NSString *path = [pathMatcher stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (path.length == 0) {
        return @"/";
    }
    if ([path hasPrefix:@"NOT "]) {
        return nil;
    }

    NSRange queryRange = [path rangeOfString:@"?"];
    if (queryRange.location != NSNotFound) {
        path = [path substringToIndex:queryRange.location];
    }
    while ([path hasSuffix:@"*"]) {
        path = [path substringToIndex:path.length - 1];
    }
    if (path.length == 0) {
        return @"/";
    }
    if (![path hasPrefix:@"/"]) {
        path = [@"/" stringByAppendingString:path];
    }
    return path;
}

NSString *DSCopyableUniversalLinkForItem(DSRuleItem *item) {
    if (!item.usesLinkRules || item.ruleHost.length == 0) {
        return nil;
    }
    NSString *path = DSNormalizedCopyableUniversalLinkPath(item.pathMatcher);
    if (path.length == 0) {
        return nil;
    }
    return [NSString stringWithFormat:@"https://%@%@", item.ruleHost, path];
}

NSString *DSNormalizedRuleIdentityString(id value, BOOL lowercase) {
    if (![value isKindOfClass:[NSString class]]) {
        return nil;
    }
    NSString *result = [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (result.length == 0) {
        return nil;
    }
    return lowercase ? result.lowercaseString : result;
}

BOOL DSNormalizedRuleIdentityBool(id value) {
    if ([value respondsToSelector:@selector(boolValue)]) {
        return [value boolValue];
    }
    return NO;
}

UIImage *DSIconForBundleID(NSString *bundleID) {
    if (bundleID.length == 0) {
        return nil;
    }
    SEL selector = NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
    if (![UIImage respondsToSelector:selector]) {
        return nil;
    }
    CGFloat scale = UIScreen.mainScreen.scale ?: 2.0;
    UIImage *(*msgSend)(id, SEL, NSString *, NSInteger, CGFloat) = (UIImage *(*)(id, SEL, NSString *, NSInteger, CGFloat))objc_msgSend;
    UIImage *image = msgSend(UIImage.class, selector, bundleID, 2, scale);
    if (![image isKindOfClass:UIImage.class]) {
        image = msgSend(UIImage.class, selector, bundleID, 0, scale);
    }
    return [image isKindOfClass:UIImage.class] ? image : nil;
}

UIImage *DSImageScaledToSize(UIImage *image, CGSize size) {
    if (![image isKindOfClass:UIImage.class] || size.width <= 0 || size.height <= 0) {
        return image;
    }
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    [image drawInRect:CGRectMake(0, 0, size.width, size.height)];
    UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return scaled ?: image;
}

static UIImage *DSOpenLogFallbackAppIcon(BOOL isSource, BOOL isNoApp) {
    CGSize size = CGSizeMake(30, 30);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);

    CGRect bounds = CGRectMake(0, 0, size.width, size.height);
    UIColor *backgroundColor = isNoApp ? [UIColor colorWithRed:0.95 green:0.33 blue:0.31 alpha:1.0]
                                       : [UIColor colorWithRed:0.50 green:0.56 blue:0.68 alpha:1.0];
    UIColor *foregroundColor = UIColor.whiteColor;
    UIBezierPath *backgroundPath = [UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:7.5];
    [backgroundColor setFill];
    [backgroundPath fill];

    NSString *symbolName = nil;
    if (isNoApp) {
        symbolName = @"nosign";
    } else if (isSource) {
        symbolName = @"questionmark";
    } else {
        symbolName = @"app";
    }

    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:(isNoApp ? 16.0 : 15.0)
                                                                                                weight:UIImageSymbolWeightBold];
    UIImage *symbol = [[UIImage systemImageNamed:symbolName] imageWithConfiguration:configuration];
    if ([symbol isKindOfClass:UIImage.class]) {
        symbol = [symbol imageWithTintColor:foregroundColor renderingMode:UIImageRenderingModeAlwaysOriginal];
        CGSize symbolSize = CGSizeMake(isNoApp ? 16.0 : 15.0, isNoApp ? 16.0 : 15.0);
        CGRect symbolRect = CGRectMake((size.width - symbolSize.width) * 0.5,
                                       (size.height - symbolSize.height) * 0.5,
                                       symbolSize.width,
                                       symbolSize.height);
        [symbol drawInRect:symbolRect];
    }

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (image) {
        return image;
    }
    return [UIImage systemImageNamed:(isNoApp ? @"nosign" : (isSource ? @"questionmark" : @"app"))];
}

static void DSDrawRoundedImage(UIImage *image, CGRect rect, CGFloat cornerRadius) {
    if (![image isKindOfClass:UIImage.class] || CGRectIsEmpty(rect)) {
        return;
    }
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context) {
        [image drawInRect:rect];
        return;
    }
    CGContextSaveGState(context);
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:MAX(0, cornerRadius)];
    [path addClip];
    [image drawInRect:rect];
    CGContextRestoreGState(context);
}

NSString *DSDisplayNameForBundleIDInOptions(NSDictionary<NSString *, DSAppOption *> *installedOptionsByBundleID,
                                                   NSString *bundleID) {
    if ([bundleID isEqualToString:kDSNoAppBundleSentinel]) {
        return @"No App";
    }
    DSAppOption *option = installedOptionsByBundleID[bundleID];
    return option.displayName.length > 0 ? option.displayName : nil;
}

NSString *DSAppSummaryForBundleIDInOptions(NSDictionary<NSString *, DSAppOption *> *installedOptionsByBundleID,
                                                  NSString *bundleID,
                                                  NSString *fallbackName) {
    if ([bundleID isEqualToString:kDSNoAppBundleSentinel]) {
        return @"No App";
    }
    NSString *displayName = DSDisplayNameForBundleIDInOptions(installedOptionsByBundleID, bundleID);
    if (displayName.length == 0) {
        displayName = fallbackName;
    }
    if (displayName.length > 0 && bundleID.length > 0) {
        return [NSString stringWithFormat:@"%@ (%@)", displayName, bundleID];
    }
    if (displayName.length > 0) {
        return displayName;
    }
    if (bundleID.length > 0) {
        return [NSString stringWithFormat:@"%@ (not installed)", bundleID];
    }
    return nil;
}

NSString *DSOpenLogDisplayType(NSString *type) {
    if ([type isEqualToString:@"universalLink"]) {
        return @"Universal Link";
    }
    if ([type isEqualToString:@"scheme"]) {
        return @"URL Scheme";
    }
    return type.length > 0 ? type : @"Unknown";
}

NSString *DSOpenLogFormattedTimestamp(id timestampValue) {
    NSTimeInterval timestamp = [timestampValue respondsToSelector:@selector(doubleValue)] ? [timestampValue doubleValue] : 0;
    if (timestamp <= 0) {
        return nil;
    }
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [NSDateFormatter new];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    });
    return [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:timestamp]];
}

NSArray<NSDictionary<NSString *, id> *> *DSSortedOpenLogs(void) {
    return [[DSRoutingConfig openLogs] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary<NSString *, id> *lhs,
                                                                                      NSDictionary<NSString *, id> *rhs) {
        NSTimeInterval lhsTimestamp = [lhs[kDSOpenLogTimestampKey] respondsToSelector:@selector(doubleValue)] ? [lhs[kDSOpenLogTimestampKey] doubleValue] : 0;
        NSTimeInterval rhsTimestamp = [rhs[kDSOpenLogTimestampKey] respondsToSelector:@selector(doubleValue)] ? [rhs[kDSOpenLogTimestampKey] doubleValue] : 0;
        if (lhsTimestamp > rhsTimestamp) {
            return NSOrderedAscending;
        }
        if (lhsTimestamp < rhsTimestamp) {
            return NSOrderedDescending;
        }
        NSString *lhsURL = lhs[kDSOpenLogURLKey] ?: @"";
        NSString *rhsURL = rhs[kDSOpenLogURLKey] ?: @"";
        return [lhsURL localizedCaseInsensitiveCompare:rhsURL];
    }];
}

UIImage *DSOpenLogAppIconForBundleID(NSString *bundleID, BOOL isSource) {
    BOOL isNoApp = [bundleID isEqualToString:kDSNoAppBundleSentinel];
    UIImage *icon = isNoApp ? nil : DSIconForBundleID(bundleID);
    if (!icon) {
        icon = DSOpenLogFallbackAppIcon(isSource, isNoApp);
    }
    return icon ? DSImageScaledToSize(icon, CGSizeMake(30, 30)) : nil;
}

UIImage *DSCombinedAppIconForBundleIDs(NSString *sourceBundleID, NSString *targetBundleID) {
    UIImage *sourceImage = DSOpenLogAppIconForBundleID(sourceBundleID, YES);
    UIImage *targetImage = DSOpenLogAppIconForBundleID(targetBundleID, NO);
    if (!sourceImage && !targetImage) {
        return nil;
    }
    if (!sourceImage) {
        return targetImage;
    }
    if (!targetImage) {
        return sourceImage;
    }

    CGSize canvasSize = CGSizeMake(34, 34);
    UIGraphicsBeginImageContextWithOptions(canvasSize, NO, 0);
    DSDrawRoundedImage(targetImage, CGRectMake(10, 10, 24, 24), 5.5);
    DSDrawRoundedImage(sourceImage, CGRectMake(0, 0, 20, 20), 4.5);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image ?: targetImage;
}
