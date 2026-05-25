#import "DSTweakCommon.h"

void DSLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"[DefaultScheme] %@", msg ?: @"");
}

// ============================================================
// Helpers
// ============================================================
BOOL DSIsNoAppRule(NSString *bundleID) {
    return [bundleID isEqualToString:kDSNoAppBundleSentinel];
}

NSString *const kDSApplicationInfoBundleIDKey = @"bundleID";
NSString *const kDSApplicationInfoNameKey = @"name";

NSString *DSTrimmedString(id value) {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *result = [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return result.length > 0 ? result : nil;
}
