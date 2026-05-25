#import "DSApplicationSupport.h"
#import "DSObjectExtraction.h"
#import "DSTweakCommon.h"
#import "DSPrivateInterfaces.h"
#import <mach/mach.h>
#import <objc/message.h>
#import <objc/runtime.h>

#if __has_include(<libproc.h>)
#import <libproc.h>
#else
#ifndef PROC_PIDPATHINFO_MAXSIZE
#define PROC_PIDPATHINFO_MAXSIZE 4096
#endif
#ifdef __cplusplus
extern "C" {
#endif
extern int proc_pidpath(int pid, void *buffer, uint32_t buffersize);
#ifdef __cplusplus
}
#endif
#endif

static NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *gDSApplicationInfoCacheByBundleID;
static NSArray *gDSInstalledApplicationProxyCache;
static NSObject *gDSApplicationCacheLock;

static NSObject *DSApplicationCacheLock(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gDSApplicationCacheLock = [NSObject new];
    });
    return gDSApplicationCacheLock;
}

NSString *DSBundleIdentifierForProxy(id proxy) {
    if (!proxy) return nil;
    @try {
        if ([proxy respondsToSelector:@selector(bundleIdentifier)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id value = [proxy performSelector:@selector(bundleIdentifier)];
#pragma clang diagnostic pop
            if ([value isKindOfClass:NSString.class]) return value;
        }
    } @catch (__unused NSException *exception) {}
    return nil;
}

NSString *DSLocalizedNameForProxy(id proxy) {
    if (!proxy) return nil;
    @try {
        if ([proxy respondsToSelector:@selector(localizedName)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id value = [proxy performSelector:@selector(localizedName)];
#pragma clang diagnostic pop
            return DSTrimmedString(value);
        }
    } @catch (__unused NSException *exception) {}
    return nil;
}

NSURL *DSBundleURLForProxy(id proxy) {
    if (!proxy) return nil;
    @try {
        if ([proxy respondsToSelector:@selector(bundleURL)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id value = [proxy performSelector:@selector(bundleURL)];
#pragma clang diagnostic pop
            if ([value isKindOfClass:NSURL.class]) return value;
            if ([value isKindOfClass:NSString.class] && [value length] > 0) {
                return [NSURL fileURLWithPath:(NSString *)value];
            }
        }
    } @catch (__unused NSException *exception) {}
    return nil;
}

static NSString *DSComparablePath(NSString *path) {
    NSString *result = DSTrimmedString(path);
    if (result.length == 0) return nil;
    result = [result stringByStandardizingPath];
    if ([result hasPrefix:@"/private/"]) {
        result = [result substringFromIndex:@"/private".length];
    }
    return result;
}

NSArray *DSInstalledApplicationProxies(void) {
    @synchronized (DSApplicationCacheLock()) {
        if ([gDSInstalledApplicationProxyCache isKindOfClass:NSArray.class]) {
            return gDSInstalledApplicationProxyCache;
        }
    }

    Class wsClass = objc_getClass("LSApplicationWorkspace");
    if (!wsClass) return @[];
    SEL sharedSel = @selector(defaultWorkspace);
    if (![wsClass respondsToSelector:sharedSel]) return @[];
    id ws = ((id (*)(id, SEL))objc_msgSend)(wsClass, sharedSel);
    SEL appsSel = @selector(allInstalledApplications);
    if (!ws || ![ws respondsToSelector:appsSel]) return @[];

    NSArray *applications = nil;
    @try {
        applications = ((id (*)(id, SEL))objc_msgSend)(ws, appsSel);
    } @catch (__unused NSException *exception) {
        applications = nil;
    }
    NSArray *result = [applications isKindOfClass:NSArray.class] ? applications : @[];
    @synchronized (DSApplicationCacheLock()) {
        gDSInstalledApplicationProxyCache = result;
    }
    return result;
}

NSDictionary<NSString *, NSString *> *DSApplicationInfoForProxy(id proxy) {
    NSString *bundleID = DSTrimmedString(DSBundleIdentifierForProxy(proxy));
    if (bundleID.length == 0) return nil;

    NSMutableDictionary<NSString *, NSString *> *info = [NSMutableDictionary dictionaryWithObject:bundleID forKey:kDSApplicationInfoBundleIDKey];
    NSString *name = DSLocalizedNameForProxy(proxy);
    if (name.length > 0) {
        info[kDSApplicationInfoNameKey] = name;
    }
    return [info copy];
}

NSDictionary<NSString *, NSString *> *DSApplicationInfoForBundleID(NSString *bundleID) {
    NSString *normalizedBundleID = DSTrimmedString(bundleID);
    if (normalizedBundleID.length == 0) return nil;

    @synchronized (DSApplicationCacheLock()) {
        NSDictionary<NSString *, NSString *> *cached = gDSApplicationInfoCacheByBundleID[normalizedBundleID];
        if ([cached isKindOfClass:NSDictionary.class]) {
            return cached;
        }
    }

    for (id candidate in DSInstalledApplicationProxies()) {
        NSString *candidateBundleID = DSBundleIdentifierForProxy(candidate) ?: @"";
        if ([candidateBundleID isEqualToString:normalizedBundleID]) {
            NSDictionary<NSString *, NSString *> *info = DSApplicationInfoForProxy(candidate);
            NSDictionary<NSString *, NSString *> *result = info ?: @{kDSApplicationInfoBundleIDKey: normalizedBundleID};
            @synchronized (DSApplicationCacheLock()) {
                NSMutableDictionary *mutableCache = [gDSApplicationInfoCacheByBundleID mutableCopy] ?: [NSMutableDictionary dictionary];
                mutableCache[normalizedBundleID] = result;
                gDSApplicationInfoCacheByBundleID = [mutableCache copy];
            }
            return result;
        }
    }
    NSDictionary<NSString *, NSString *> *result = @{kDSApplicationInfoBundleIDKey: normalizedBundleID};
    @synchronized (DSApplicationCacheLock()) {
        NSMutableDictionary *mutableCache = [gDSApplicationInfoCacheByBundleID mutableCopy] ?: [NSMutableDictionary dictionary];
        mutableCache[normalizedBundleID] = result;
        gDSApplicationInfoCacheByBundleID = [mutableCache copy];
    }
    return result;
}

NSDictionary<NSString *, NSString *> *DSApplicationInfoForBundlePath(NSString *bundlePath) {
    NSString *normalizedBundlePath = DSComparablePath(bundlePath);
    if (normalizedBundlePath.length == 0) return nil;

    for (id candidate in DSInstalledApplicationProxies()) {
        NSString *candidatePath = DSComparablePath(DSBundleURLForProxy(candidate).path);
        if (candidatePath.length > 0 && [candidatePath isEqualToString:normalizedBundlePath]) {
            return DSApplicationInfoForProxy(candidate);
        }
    }
    return nil;
}

static NSString *DSBundlePathFromExecutablePath(NSString *executablePath) {
    NSString *normalizedExecutablePath = DSTrimmedString(executablePath);
    if (normalizedExecutablePath.length == 0) return nil;

    NSRange appRange = [normalizedExecutablePath rangeOfString:@".app/" options:NSCaseInsensitiveSearch];
    if (appRange.location != NSNotFound) {
        return [normalizedExecutablePath substringToIndex:appRange.location + 4];
    }
    if ([[normalizedExecutablePath lowercaseString] hasSuffix:@".app"]) {
        return normalizedExecutablePath;
    }
    return nil;
}

static pid_t DSPIDFromAuditToken(const void *sourceAuditToken) {
    if (!sourceAuditToken) return 0;
    audit_token_t token = *(const audit_token_t *)sourceAuditToken;
    return (pid_t)token.val[5];
}

NSDictionary<NSString *, NSString *> *DSApplicationInfoFromAuditToken(const void *sourceAuditToken) {
    pid_t pid = DSPIDFromAuditToken(sourceAuditToken);
    if (pid <= 0) return nil;

    char executablePathBuffer[PROC_PIDPATHINFO_MAXSIZE] = {0};
    int length = proc_pidpath(pid, executablePathBuffer, sizeof(executablePathBuffer));
    if (length <= 0) return nil;

    NSString *executablePath = [NSString stringWithUTF8String:executablePathBuffer];
    NSString *bundlePath = DSBundlePathFromExecutablePath(executablePath);
    return DSApplicationInfoForBundlePath(bundlePath);
}

static NSDictionary<NSString *, NSString *> *DSApplicationInfoFromAuditTokenObject(id object) {
    audit_token_t token = {0};
    BOOL hasToken = NO;

    if ([object isKindOfClass:NSValue.class]) {
        NSUInteger valueSize = 0;
        NSGetSizeAndAlignment([(NSValue *)object objCType], &valueSize, NULL);
        if (valueSize == sizeof(token)) {
            @try {
                [(NSValue *)object getValue:&token];
                hasToken = YES;
            } @catch (__unused NSException *exception) {}
        }
    } else if ([object isKindOfClass:NSData.class] && [(NSData *)object length] >= sizeof(token)) {
        [(NSData *)object getBytes:&token length:sizeof(token)];
        hasToken = YES;
    }

    return hasToken ? DSApplicationInfoFromAuditToken(&token) : nil;
}

NSDictionary<NSString *, NSString *> *DSApplicationInfoWithBundleIDAndName(NSString *bundleID, NSString *name) {
    NSString *normalizedBundleID = DSTrimmedString(bundleID);
    NSString *normalizedName = DSTrimmedString(name);
    if (normalizedBundleID.length == 0 && normalizedName.length == 0) {
        return nil;
    }

    NSMutableDictionary<NSString *, NSString *> *info = [NSMutableDictionary dictionary];
    if (normalizedBundleID.length > 0) {
        info[kDSApplicationInfoBundleIDKey] = normalizedBundleID;
    }
    if (normalizedName.length > 0) {
        info[kDSApplicationInfoNameKey] = normalizedName;
    }
    return [info copy];
}

NSDictionary<NSString *, NSString *> *DSMergedApplicationInfo(NSDictionary<NSString *, NSString *> *preferred,
                                                                     NSDictionary<NSString *, NSString *> *fallback) {
    NSString *bundleID = DSTrimmedString(preferred[kDSApplicationInfoBundleIDKey]) ?: DSTrimmedString(fallback[kDSApplicationInfoBundleIDKey]);
    NSString *name = DSTrimmedString(preferred[kDSApplicationInfoNameKey]) ?: DSTrimmedString(fallback[kDSApplicationInfoNameKey]);
    return DSApplicationInfoWithBundleIDAndName(bundleID, name);
}

NSDictionary<NSString *, NSString *> *DSCurrentProcessApplicationInfo(void) {
    NSString *processName = NSProcessInfo.processInfo.processName ?: @"";
    if ([processName isEqualToString:@"lsd"] || [processName isEqualToString:@"SpringBoard"]) {
        return nil;
    }

    NSBundle *mainBundle = NSBundle.mainBundle;
    NSString *bundleID = DSTrimmedString(mainBundle.bundleIdentifier);
    if ([bundleID isEqualToString:@"com.apple.springboard"]) {
        return nil;
    }
    NSString *displayName = DSTrimmedString([mainBundle objectForInfoDictionaryKey:@"CFBundleDisplayName"])
        ?: DSTrimmedString([mainBundle objectForInfoDictionaryKey:@"CFBundleName"])
        ?: DSTrimmedString(processName);
    return DSApplicationInfoWithBundleIDAndName(bundleID, displayName);
}

static NSString *DSBundleIdentifierFromObjectInternal(id object, NSUInteger depth) {
    if (!object || depth > 2) return nil;

    NSString *bundleID = DSTrimmedString(DSBundleIdentifierForProxy(object));
    if (bundleID.length > 0) {
        return bundleID;
    }

    for (NSString *key in @[@"bundleIdentifier", @"bundleID", @"applicationBundleIdentifier", @"sourceBundleIdentifier", @"originatingBundleIdentifier", @"bundleId", @"bundleIdentifierForAuditToken", @"callingBundleIdentifier"]) {
        id value = DSSafeValueForKey(object, key);
        if ([value isKindOfClass:NSString.class]) {
            bundleID = DSTrimmedString(value);
            if (bundleID.length > 0) {
                return bundleID;
            }
        }
    }

    NSArray *objects = DSCollectionObjects(object);
    if (objects.count > 0) {
        NSUInteger limit = MIN((NSUInteger)3, objects.count);
        for (NSUInteger idx = 0; idx < limit; idx++) {
            bundleID = DSBundleIdentifierFromObjectInternal(objects[idx], depth + 1);
            if (bundleID.length > 0) {
                return bundleID;
            }
        }
    }

    for (NSString *key in @[@"origin", @"request", @"options", @"application", @"applicationProxy", @"workspace", @"auditToken", @"sourceAuditToken", @"XPCConnection", @"xpcConnection", @"connection", @"client", @"state", @"openState"]) {
        bundleID = DSBundleIdentifierFromObjectInternal(DSSafeValueForKey(object, key), depth + 1);
        if (bundleID.length > 0) {
            return bundleID;
        }
    }

    return nil;
}

NSDictionary<NSString *, NSString *> *DSApplicationInfoFromObjectInternal(id object, NSUInteger depth) {
    if (!object || depth > 2) return nil;

    NSDictionary<NSString *, NSString *> *auditInfo = DSApplicationInfoFromAuditTokenObject(object);
    if (auditInfo) {
        return auditInfo;
    }

    NSDictionary<NSString *, NSString *> *info = DSApplicationInfoForProxy(object);
    if (info) {
        return info;
    }

    NSString *bundleID = DSBundleIdentifierFromObjectInternal(object, depth);
    NSString *name = nil;
    for (NSString *key in @[@"localizedName", @"displayName", @"name", @"sourceName", @"originatingApplicationName"]) {
        id value = DSSafeValueForKey(object, key);
        if ([value isKindOfClass:NSString.class]) {
            name = DSTrimmedString(value);
            if (name.length > 0) {
                break;
            }
        }
    }
    if (bundleID.length > 0 || name.length > 0) {
        return DSMergedApplicationInfo(DSApplicationInfoWithBundleIDAndName(bundleID, name),
                                       bundleID.length > 0 ? DSApplicationInfoForBundleID(bundleID) : nil);
    }

    NSArray *objects = DSCollectionObjects(object);
    if (objects.count > 0) {
        NSUInteger limit = MIN((NSUInteger)3, objects.count);
        for (NSUInteger idx = 0; idx < limit; idx++) {
            info = DSApplicationInfoFromObjectInternal(objects[idx], depth + 1);
            if (info) {
                return info;
            }
        }
    }

    for (NSString *key in @[@"origin", @"request", @"options", @"application", @"applicationProxy", @"workspace", @"auditToken", @"sourceAuditToken", @"XPCConnection", @"xpcConnection", @"connection", @"client", @"state", @"openState"]) {
        info = DSApplicationInfoFromObjectInternal(DSSafeValueForKey(object, key), depth + 1);
        if (info) {
            return info;
        }
    }

    return nil;
}

NSDictionary<NSString *, NSString *> *DSApplicationInfoFromObject(id object) {
    return DSApplicationInfoFromObjectInternal(object, 0);
}

static BOOL DSObjectLooksLikeAppLinkTargetContainer(id object) {
    if (!object) return NO;
    NSString *className = NSStringFromClass([object class]);
    return [className containsString:@"LSAppLink"] || [className containsString:@"AppLinkOpenState"];
}

NSDictionary<NSString *, NSString *> *DSSourceApplicationInfoFromObjectInternal(id object, NSUInteger depth) {
    if (!object || depth > 3) return nil;

    NSDictionary<NSString *, NSString *> *auditInfo = DSApplicationInfoFromAuditTokenObject(object);
    if (auditInfo) {
        return auditInfo;
    }

    if (DSObjectLooksLikeAppLinkTargetContainer(object)) {
        for (NSString *key in @[@"XPCConnection", @"xpcConnection", @"connection", @"client", @"auditToken", @"sourceAuditToken"]) {
            NSDictionary<NSString *, NSString *> *info = DSSourceApplicationInfoFromObjectInternal(DSSafeValueForKey(object, key), depth + 1);
            if (info) {
                return info;
            }
        }
        return nil;
    }

    NSDictionary<NSString *, NSString *> *info = DSApplicationInfoForProxy(object);
    if (info) {
        return info;
    }

    NSString *bundleID = DSBundleIdentifierFromObjectInternal(object, depth);
    NSString *name = nil;
    for (NSString *key in @[@"localizedName", @"displayName", @"name", @"sourceName", @"originatingApplicationName"]) {
        id value = DSSafeValueForKey(object, key);
        if ([value isKindOfClass:NSString.class]) {
            name = DSTrimmedString(value);
            if (name.length > 0) {
                break;
            }
        }
    }
    if (bundleID.length > 0 || name.length > 0) {
        return DSMergedApplicationInfo(DSApplicationInfoWithBundleIDAndName(bundleID, name),
                                       bundleID.length > 0 ? DSApplicationInfoForBundleID(bundleID) : nil);
    }

    for (NSString *key in @[@"origin", @"request", @"options", @"auditToken", @"sourceAuditToken", @"XPCConnection", @"xpcConnection", @"connection", @"client"]) {
        info = DSSourceApplicationInfoFromObjectInternal(DSSafeValueForKey(object, key), depth + 1);
        if (info) {
            return info;
        }
    }

    NSArray *objects = DSCollectionObjects(object);
    if (objects.count > 0) {
        NSUInteger limit = MIN((NSUInteger)3, objects.count);
        for (NSUInteger idx = 0; idx < limit; idx++) {
            info = DSSourceApplicationInfoFromObjectInternal(objects[idx], depth + 1);
            if (info) {
                return info;
            }
        }
    }

    return nil;
}

NSDictionary<NSString *, NSString *> *DSSourceApplicationInfoFromObject(id object) {
    return DSSourceApplicationInfoFromObjectInternal(object, 0);
}

NSDictionary<NSString *, NSString *> *DSMergedApplicationInfoFromObjects(id first,
                                                                                id second,
                                                                                id third,
                                                                                id fourth) {
    NSDictionary<NSString *, NSString *> *info = nil;
    for (id object in @[
        first ?: NSNull.null,
        second ?: NSNull.null,
        third ?: NSNull.null,
        fourth ?: NSNull.null,
    ]) {
        if (object == NSNull.null) {
            continue;
        }
        info = DSMergedApplicationInfo(info, DSApplicationInfoFromObject(object));
    }
    return info;
}

NSDictionary<NSString *, NSString *> *DSSourceApplicationInfoFromObjects(id first,
                                                                                id second,
                                                                                id third,
                                                                                id fourth) {
    NSDictionary<NSString *, NSString *> *info = nil;
    for (id object in @[
        first ?: NSNull.null,
        second ?: NSNull.null,
        third ?: NSNull.null,
        fourth ?: NSNull.null,
    ]) {
        if (object == NSNull.null) {
            continue;
        }
        info = DSMergedApplicationInfo(info, DSSourceApplicationInfoFromObject(object));
    }
    return info;
}
