#import "DSOpenLogging.h"
#import "DSApplicationSupport.h"
#import "DSTweakCommon.h"
#import "../Shared/DSRoutingConfig.h"
#import <arpa/inet.h>
#import <dispatch/dispatch.h>
#import <errno.h>
#import <fcntl.h>
#import <netinet/in.h>
#import <sys/socket.h>
#import <unistd.h>

static const in_port_t kDSOpenLogRelayPort = 27631;
static NSString *const kDSOpenLogRelayMagicKey = @"magic";
static NSString *const kDSOpenLogRelayMagicValue = @"codes.var.tweak.defaultscheme.openlog.v1";
static NSString *const kDSOpenLogRelayEntryKey = @"entry";
static dispatch_source_t DSOpenLogRelaySource;
static dispatch_queue_t DSOpenLogWriteQueue;
static BOOL gDSOpenLogMatchedOnly = NO;
static BOOL gDSOpenLogMatchedOnlyInitialized = NO;

static void DSOpenLogConfigChangedCallback(CFNotificationCenterRef center,
                                           void *observer,
                                           CFStringRef name,
                                           const void *object,
                                           CFDictionaryRef userInfo) {
    gDSOpenLogMatchedOnlyInitialized = NO;
}

static void DSRegisterOpenLogConfigInvalidation(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        DSOpenLogConfigChangedCallback,
                                        (__bridge CFStringRef)kDSRoutingConfigChangedNotification,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    });
}

static BOOL DSCurrentProcessCanPersistOpenLogs(void) {
    NSString *processName = NSProcessInfo.processInfo.processName ?: @"";
    if ([processName isEqualToString:@"lsd"] || [processName isEqualToString:@"SpringBoard"]) {
        return YES;
    }
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"codes.var.tweak.defaultscheme"];
}

BOOL DSShouldRecordMatchedOpensOnly(void) {
    DSRegisterOpenLogConfigInvalidation();
    if (gDSOpenLogMatchedOnlyInitialized) {
        return gDSOpenLogMatchedOnly;
    }
    NSDictionary *config = [DSRoutingConfig loadConfig] ?: @{};
    gDSOpenLogMatchedOnly = [DSRoutingConfig openLogRecordsMatchedOnlyFromConfig:config];
    gDSOpenLogMatchedOnlyInitialized = YES;
    return gDSOpenLogMatchedOnly;
}

static NSDictionary<NSString *, id> *DSOpenLogRelayPayload(NSDictionary<NSString *, id> *entry) {
    if (![entry isKindOfClass:NSDictionary.class]) return nil;
    return @{
        kDSOpenLogRelayMagicKey: kDSOpenLogRelayMagicValue,
        kDSOpenLogRelayEntryKey: entry,
    };
}

static NSDictionary<NSString *, id> *DSEnrichedOpenLogEntryForPersistence(NSDictionary<NSString *, id> *entry);

static dispatch_queue_t DSOpenLogPersistenceQueue(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        DSOpenLogWriteQueue = dispatch_queue_create("codes.var.tweak.defaultscheme.openlog-write", DISPATCH_QUEUE_SERIAL);
    });
    return DSOpenLogWriteQueue;
}

static void DSSendOpenLogEntryToRelay(NSDictionary<NSString *, id> *entry, NSString *source) {
    NSDictionary<NSString *, id> *payload = DSOpenLogRelayPayload(entry);
    if (!payload) return;

    NSError *serializationError = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:payload
                                                              format:NSPropertyListBinaryFormat_v1_0
                                                             options:0
                                                               error:&serializationError];
    if (data.length == 0) {
        DSLog(@"%@ failed to serialize relay open log error=%@", source ?: @"open", serializationError.localizedDescription ?: @"unknown");
        return;
    }

    int fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (fd < 0) {
        DSLog(@"%@ failed to create relay socket errno=%d", source ?: @"open", errno);
        return;
    }

    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_port = htons(kDSOpenLogRelayPort);
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    ssize_t sent = sendto(fd, data.bytes, data.length, 0, (const struct sockaddr *)&address, sizeof(address));
    if (sent < 0 || (NSUInteger)sent != data.length) {
        DSLog(@"%@ failed to relay open log bytes=%lu sent=%zd errno=%d",
              source ?: @"open",
              (unsigned long)data.length,
              sent,
              errno);
    } else {
        DSLog(@"%@ relayed open log bytes=%lu", source ?: @"open", (unsigned long)data.length);
    }
    close(fd);
}

static void DSHandleOpenLogRelayData(NSData *data) {
    if (data.length == 0) return;

    NSError *parseError = nil;
    id plist = [NSPropertyListSerialization propertyListWithData:data
                                                         options:NSPropertyListImmutable
                                                          format:nil
                                                           error:&parseError];
    if (![plist isKindOfClass:NSDictionary.class]) {
        DSLog(@"open log relay ignored invalid payload error=%@", parseError.localizedDescription ?: @"unknown");
        return;
    }

    NSDictionary *payload = (NSDictionary *)plist;
    if (![payload[kDSOpenLogRelayMagicKey] isEqual:kDSOpenLogRelayMagicValue]) {
        return;
    }

    NSDictionary<NSString *, id> *entry = DSEnrichedOpenLogEntryForPersistence(payload[kDSOpenLogRelayEntryKey]);
    if (![entry isKindOfClass:NSDictionary.class]) {
        return;
    }

    NSError *error = nil;
    if (![DSRoutingConfig appendOpenLogEntry:entry limit:0 error:&error]) {
        DSLog(@"open log relay failed to persist error=%@", error.localizedDescription ?: @"unknown");
        return;
    }
    DSLog(@"open log relay persisted %@ -> %@ source=%@",
          entry[kDSOpenLogURLKey] ?: @"",
          entry[kDSOpenLogTargetBundleIDKey] ?: @"",
          entry[kDSOpenLogSourceBundleIDKey] ?: @"");
}

void DSStartOpenLogRelayServerIfNeeded(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        int fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
        if (fd < 0) {
            DSLog(@"open log relay failed to create socket errno=%d", errno);
            return;
        }

        int enabled = 1;
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &enabled, sizeof(enabled));

        int flags = fcntl(fd, F_GETFL, 0);
        if (flags >= 0) {
            fcntl(fd, F_SETFL, flags | O_NONBLOCK);
        }

        struct sockaddr_in address;
        memset(&address, 0, sizeof(address));
        address.sin_len = sizeof(address);
        address.sin_family = AF_INET;
        address.sin_port = htons(kDSOpenLogRelayPort);
        address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

        if (bind(fd, (const struct sockaddr *)&address, sizeof(address)) < 0) {
            DSLog(@"open log relay failed to bind port=%u errno=%d", (unsigned int)kDSOpenLogRelayPort, errno);
            close(fd);
            return;
        }

        dispatch_queue_t queue = dispatch_queue_create("codes.var.tweak.defaultscheme.openlog-relay", DISPATCH_QUEUE_SERIAL);
        DSOpenLogRelaySource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, fd, 0, queue);
        if (!DSOpenLogRelaySource) {
            close(fd);
            return;
        }

        dispatch_source_set_event_handler(DSOpenLogRelaySource, ^{
            while (YES) {
                uint8_t buffer[65535];
                struct sockaddr_in peer;
                socklen_t peerLength = sizeof(peer);
                ssize_t received = recvfrom(fd, buffer, sizeof(buffer), 0, (struct sockaddr *)&peer, &peerLength);
                if (received < 0) {
                    if (errno != EAGAIN && errno != EWOULDBLOCK) {
                        DSLog(@"open log relay recv failed errno=%d", errno);
                    }
                    break;
                }
                if (peer.sin_family != AF_INET || peer.sin_addr.s_addr != htonl(INADDR_LOOPBACK)) {
                    continue;
                }
                DSHandleOpenLogRelayData([NSData dataWithBytes:buffer length:(NSUInteger)received]);
            }
        });
        dispatch_source_set_cancel_handler(DSOpenLogRelaySource, ^{
            close(fd);
        });
        dispatch_resume(DSOpenLogRelaySource);
        DSLog(@"open log relay listening on 127.0.0.1:%u", (unsigned int)kDSOpenLogRelayPort);
    });
}

NSString *DSOpenLogTypeForURL(NSURL *url) {
    NSString *scheme = url.scheme.lowercaseString;
    if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) {
        return @"universalLink";
    }
    return @"scheme";
}

static NSDictionary<NSString *, id> *DSOpenLogEntry(NSURL *url,
                                                        NSString *targetBundleID,
                                                        NSDictionary<NSString *, NSString *> *sourceInfo,
                                                        NSString *hookSource,
                                                        BOOL includeInstalledApplicationNames) {
    NSString *urlString = url.absoluteString;
    if (urlString.length == 0 || targetBundleID.length == 0) {
        return nil;
    }

    NSMutableDictionary<NSString *, id> *entry = [NSMutableDictionary dictionaryWithDictionary:@{
        kDSOpenLogTimestampKey: @(NSDate.date.timeIntervalSince1970),
        kDSOpenLogURLKey: urlString,
        kDSOpenLogTypeKey: DSOpenLogTypeForURL(url),
        kDSOpenLogTargetBundleIDKey: targetBundleID,
    }];

    NSString *sourceBundleID = DSTrimmedString(sourceInfo[kDSApplicationInfoBundleIDKey]);
    NSDictionary<NSString *, NSString *> *sourceBundleInfo = nil;
    if (sourceBundleID.length > 0) {
        entry[kDSOpenLogSourceBundleIDKey] = sourceBundleID;
    }
    NSString *sourceName = DSTrimmedString(sourceInfo[kDSApplicationInfoNameKey]) ?: DSTrimmedString(sourceBundleInfo[kDSApplicationInfoNameKey]);
    if (sourceName.length > 0) {
        entry[kDSOpenLogSourceNameKey] = sourceName;
    }

    NSString *normalizedHookSource = DSTrimmedString(hookSource);
    if (normalizedHookSource.length > 0) {
        entry[kDSOpenLogHookSourceKey] = normalizedHookSource;
    }

    return [entry copy];
}

static NSDictionary<NSString *, id> *DSEnrichedOpenLogEntryForPersistence(NSDictionary<NSString *, id> *entry) {
    if (![entry isKindOfClass:NSDictionary.class]) return nil;

    NSURL *url = [entry[kDSOpenLogURLKey] isKindOfClass:NSString.class] ? [NSURL URLWithString:entry[kDSOpenLogURLKey]] : nil;
    NSString *targetBundleID = DSTrimmedString(entry[kDSOpenLogTargetBundleIDKey]);
    NSDictionary<NSString *, NSString *> *sourceInfo = DSApplicationInfoWithBundleIDAndName(entry[kDSOpenLogSourceBundleIDKey], entry[kDSOpenLogSourceNameKey]);
    NSDictionary<NSString *, id> *rebuiltEntry = DSOpenLogEntry(url, targetBundleID, sourceInfo, entry[kDSOpenLogHookSourceKey], NO);
    if (!rebuiltEntry) return entry;

    NSMutableDictionary<NSString *, id> *result = [entry mutableCopy];
    [rebuiltEntry enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        if (!result[key] && value) {
            result[key] = value;
        }
    }];
    return [result copy];
}

void DSAppendOpenLogEntry(NSString *source,
                                 NSURL *url,
                                 NSString *bundleID,
                                 NSDictionary<NSString *, NSString *> *sourceInfo) {
    NSString *targetBundleID = DSTrimmedString(bundleID);
    if (url.absoluteString.length == 0 || targetBundleID.length == 0) {
        return;
    }

    BOOL canPersist = DSCurrentProcessCanPersistOpenLogs();
    NSDictionary<NSString *, NSString *> *resolvedSourceInfo = DSMergedApplicationInfo(sourceInfo, DSCurrentProcessApplicationInfo());
    NSDictionary<NSString *, id> *entry = DSOpenLogEntry(url, targetBundleID, resolvedSourceInfo, source, NO);
    if (!entry) return;

    dispatch_async(DSOpenLogPersistenceQueue(), ^{
        if (!canPersist) {
            DSSendOpenLogEntryToRelay(entry, source);
            return;
        }

        NSError *error = nil;
        if (![DSRoutingConfig appendOpenLogEntry:entry limit:0 error:&error]) {
            DSLog(@"%@ failed to persist open log %@ -> %@ source=%@ error=%@",
                  source ?: @"open",
                  url.absoluteString ?: @"",
                  targetBundleID,
                  DSTrimmedString(resolvedSourceInfo[kDSApplicationInfoBundleIDKey]) ?: @"",
                  error.localizedDescription ?: @"unknown");
        }
    });
}

void DSAppendObservedOpenLogEntry(NSString *source,
                                         NSURL *url,
                                         NSString *bundleID,
                                         NSDictionary<NSString *, NSString *> *sourceInfo,
                                         BOOL matchedRule) {
    if (DSShouldRecordMatchedOpensOnly() && !matchedRule) {
        return;
    }
    DSAppendOpenLogEntry(source, url, bundleID, sourceInfo);
}

void DSLogDeferredURLPreservingOpenWithSourceInfo(NSString *source,
                                                         NSURL *url,
                                                         NSString *bundleID,
                                                         NSDictionary<NSString *, NSString *> *sourceInfo) {
    if (bundleID.length == 0 || DSIsNoAppRule(bundleID)) return;
    DSAppendObservedOpenLogEntry(source, url, bundleID, sourceInfo, YES);
    DSLog(@"%@ preserving URL %@ -> %@ source=%@ via original open path",
          source ?: @"open",
          url.absoluteString ?: @"",
          bundleID,
          DSTrimmedString(sourceInfo[kDSApplicationInfoBundleIDKey]) ?: DSTrimmedString(DSCurrentProcessApplicationInfo()[kDSApplicationInfoBundleIDKey]) ?: @"");
}

void DSLogDeferredURLPreservingOpen(NSString *source, NSURL *url, NSString *bundleID) {
    DSLogDeferredURLPreservingOpenWithSourceInfo(source, url, bundleID, nil);
}
