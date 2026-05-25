#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <sys/wait.h>
#import <unistd.h>
#import <xpc/xpc.h>
#if DEFAULTSCHEME_ROOTHIDE
#import <roothide/roothide.h>
#endif
#import "../Shared/DSRoutingConfig.h"

static void LoadLaunchServicesFrameworks(void) {
    dlopen("/System/Library/PrivateFrameworks/MobileCoreServices.framework/MobileCoreServices", RTLD_NOW);
    dlopen("/System/Library/Frameworks/CoreServices.framework/CoreServices", RTLD_NOW);
    dlopen("/System/Library/PrivateFrameworks/SoftLinking.framework/SoftLinking", RTLD_NOW);
    dlopen("/System/Library/PrivateFrameworks/SharedWebCredentials.framework/SharedWebCredentials", RTLD_NOW);
}

static void PrintUsage(void) {
    printf("defaultschemectl usage:\n");
    printf("  defaultschemectl list\n");
    printf("  defaultschemectl sync-route-config-mirror\n");
    printf("  defaultschemectl set-scheme <scheme> <bundle-id>\n");
    printf("  defaultschemectl set-host <host> <bundle-id>\n");
    printf("  defaultschemectl set-link <host> <path-matcher> <bundle-id>\n");
    printf("  defaultschemectl set-link-rich <rule-id> <host> <path-matcher|- > <query-matcher|- > <bundle-id>\n");
    printf("  defaultschemectl del-scheme <scheme>\n");
    printf("  defaultschemectl del-host <host>\n");
    printf("  defaultschemectl del-link <host> <path-matcher>\n");
    printf("  defaultschemectl del-link-rich <rule-id> <host> <path-matcher|- > <query-matcher|- >\n");
    printf("  defaultschemectl probe-url <url>\n");
    printf("  defaultschemectl open-url <url>\n");
    printf("  defaultschemectl perform-open-url <requested-bundle-id> <url>\n");
    printf("  defaultschemectl trace-url <url>\n");
    printf("  defaultschemectl inspect-applink <url>\n");
    printf("  defaultschemectl inspect-swc <url>\n");
    printf("  defaultschemectl inspect-method <class> <selector>\n");
    printf("  defaultschemectl list-methods <class>\n");
    printf("  defaultschemectl list-classes <prefix>\n");
}

static int DSDropElevatedPrivilegesUnlessNeeded(NSString *cmd) {
    if (geteuid() != 0 ||
        getuid() == 0 ||
        [cmd isEqualToString:@"sync-route-config-mirror"]) {
        return 0;
    }
    gid_t gid = getgid();
    uid_t uid = getuid();
    if (setgid(gid) != 0 || setuid(uid) != 0) {
        fprintf(stderr, "failed to drop privileges\n");
        return 1;
    }
    return 0;
}

static NSMutableDictionary *MutableConfig(void) {
    return [[DSRoutingConfig loadConfig] mutableCopy] ?: [NSMutableDictionary dictionary];
}

static NSMutableDictionary *EnsureMutableMap(NSMutableDictionary *root, NSString *key) {
    id map = root[key];
    if ([map isKindOfClass:[NSDictionary class]]) {
        root[key] = [map mutableCopy];
    } else if (![map isKindOfClass:[NSMutableDictionary class]]) {
        root[key] = [NSMutableDictionary dictionary];
    }
    return root[key];
}

static NSMutableArray *EnsureMutableArray(NSMutableDictionary *root, NSString *key) {
    id array = root[key];
    if ([array isKindOfClass:[NSArray class]]) {
        root[key] = [array mutableCopy];
    } else if (![array isKindOfClass:[NSMutableArray class]]) {
        root[key] = [NSMutableArray array];
    }
    return root[key];
}

static int SaveOrPrint(NSDictionary *cfg) {
    NSError *error = nil;
    if (![DSRoutingConfig saveConfig:cfg error:&error]) {
        fprintf(stderr, "save failed: %s\n", error.localizedDescription.UTF8String ?: "unknown error");
        return 1;
    }
    printf("ok\n");
    return 0;
}

static void DSAddUniquePath(NSMutableArray<NSString *> *paths, NSMutableSet<NSString *> *seen, NSString *path) {
    if (path.length == 0 || [seen containsObject:path]) {
        return;
    }
    [seen addObject:path];
    [paths addObject:path];
}

static NSDictionary<NSString *, id> *PersistentMirrorLinkRuleFromValue(id value) {
    NSDictionary<NSString *, id> *rule = [DSRoutingConfig normalizedLinkRuleFromValue:value];
    if (!rule) {
        return nil;
    }

    NSMutableDictionary<NSString *, id> *persistentRule = [NSMutableDictionary dictionary];
    NSArray<NSString *> *stringKeys = @[
        kDSLinkRuleHostKey,
        kDSLinkRulePathKey,
        kDSLinkRuleMatchTypeKey,
        kDSLinkRuleBundleIDKey,
        kDSLinkRuleSourceHintKey,
        kDSLinkRuleRuleIDKey,
        kDSLinkRulePathMatcherKey,
        kDSLinkRuleQueryMatcherKey,
        kDSLinkRuleIdentityVersionKey,
        kDSLinkRuleAssociatedBundleIDKey,
        kDSLinkRulePatternKindKey,
        kDSLinkRuleRawPatternDataKey,
    ];
    for (NSString *key in stringKeys) {
        NSString *stringValue = [rule[key] isKindOfClass:[NSString class]] ? rule[key] : nil;
        if (stringValue.length > 0) {
            persistentRule[key] = stringValue;
        }
    }
    if ([rule[kDSLinkRuleHostWildcardKey] respondsToSelector:@selector(boolValue)]) {
        persistentRule[kDSLinkRuleHostWildcardKey] = @([rule[kDSLinkRuleHostWildcardKey] boolValue]);
    }
    if ([rule[kDSLinkRuleRawOpcodeKey] isKindOfClass:[NSNumber class]]) {
        persistentRule[kDSLinkRuleRawOpcodeKey] = rule[kDSLinkRuleRawOpcodeKey];
    }
    return persistentRule.count > 0 ? persistentRule : nil;
}

static NSDictionary *RouteConfigMirrorPlist(void) {
    NSDictionary *config = [DSRoutingConfig loadConfig] ?: @{};
    NSMutableDictionary *mirror = [NSMutableDictionary dictionary];

    NSDictionary *schemes = [DSRoutingConfig schemeRulesFromConfig:config];
    if (schemes.count > 0) {
        mirror[@"schemes"] = schemes;
    }

    NSDictionary *hosts = [DSRoutingConfig hostRulesFromConfig:config];
    if (hosts.count > 0) {
        mirror[@"hosts"] = hosts;
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *links = [NSMutableArray array];
    for (NSDictionary<NSString *, id> *rule in [DSRoutingConfig linkRulesFromConfig:config]) {
        NSDictionary<NSString *, id> *persistentRule = PersistentMirrorLinkRuleFromValue(rule);
        if (persistentRule) {
            [links addObject:persistentRule];
        }
    }
    if (links.count > 0) {
        mirror[kDSRoutingLinksKey] = [links copy];
    }

    return [mirror copy];
}

static NSArray<NSString *> *RouteConfigMirrorPaths(void) {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];

#if DEFAULTSCHEME_ROOTHIDE
    NSString *jbrootMirrorDirectory = jbroot(@"/Library/MobileSubstrate/DynamicLibraries");
    if (jbrootMirrorDirectory.length > 0) {
        DSAddUniquePath(paths, seen, [jbrootMirrorDirectory stringByAppendingPathComponent:kDSRoutingConfigMirrorFilename]);
    }
#endif
    DSAddUniquePath(paths, seen, [@"/var/jb/Library/MobileSubstrate/DynamicLibraries" stringByAppendingPathComponent:kDSRoutingConfigMirrorFilename]);
    DSAddUniquePath(paths, seen, [@"/var/mobile/Library/pkgmirror/Library/MobileSubstrate/DynamicLibraries" stringByAppendingPathComponent:kDSRoutingConfigMirrorFilename]);

    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSArray<NSString *> *applicationRoots = @[@"/private/var/containers/Bundle/Application", @"/var/containers/Bundle/Application"];
    for (NSString *root in applicationRoots) {
        NSArray<NSString *> *entries = [fileManager contentsOfDirectoryAtPath:root error:nil];
        for (NSString *entry in entries) {
            if (![entry hasPrefix:@".jbroot-"]) {
                continue;
            }
            NSString *tweakInjectDirectory = [[[root stringByAppendingPathComponent:entry] stringByAppendingPathComponent:@"usr/lib"] stringByAppendingPathComponent:@"TweakInject"];
            BOOL isDirectory = NO;
            if ([fileManager fileExistsAtPath:tweakInjectDirectory isDirectory:&isDirectory] && isDirectory) {
                DSAddUniquePath(paths, seen, [tweakInjectDirectory stringByAppendingPathComponent:kDSRoutingConfigMirrorFilename]);
            }
        }
    }

    return [paths copy];
}

static BOOL WritePlistToPaths(NSDictionary *plist, NSArray<NSString *> *paths, NSMutableArray<NSString *> *writtenPaths, NSMutableArray<NSString *> *failedPaths) {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    for (NSString *path in paths) {
        NSString *directory = [path stringByDeletingLastPathComponent];
        BOOL isDirectory = NO;
        if (![fileManager fileExistsAtPath:directory isDirectory:&isDirectory]) {
            NSError *directoryError = nil;
            if (![fileManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&directoryError]) {
                [failedPaths addObject:[NSString stringWithFormat:@"%@: %@", path, directoryError.localizedDescription ?: @"failed to create directory"]];
                continue;
            }
        } else if (!isDirectory) {
            [failedPaths addObject:[NSString stringWithFormat:@"%@: parent path is not a directory", path]];
            continue;
        }

        if ([plist writeToFile:path atomically:YES]) {
            [fileManager setAttributes:@{NSFilePosixPermissions: @0644} ofItemAtPath:path error:nil];
            [writtenPaths addObject:path];
        } else {
            [failedPaths addObject:[NSString stringWithFormat:@"%@: failed to write plist", path]];
        }
    }
    return writtenPaths.count > 0;
}

static BOOL SyncRouteConfigMirror(NSMutableArray<NSString *> *writtenPaths, NSMutableArray<NSString *> *failedPaths) {
    return WritePlistToPaths(RouteConfigMirrorPlist(), RouteConfigMirrorPaths(), writtenPaths, failedPaths);
}

static int SyncRouteConfigMirrorCommand(void) {
    NSMutableArray<NSString *> *writtenPaths = [NSMutableArray array];
    NSMutableArray<NSString *> *failedPaths = [NSMutableArray array];
    if (!SyncRouteConfigMirror(writtenPaths, failedPaths)) {
        for (NSString *failure in failedPaths) {
            fprintf(stderr, "%s\n", failure.UTF8String ?: "write failed");
        }
        return 1;
    }

    printf("synced %lu route config mirror plist%s\n", (unsigned long)writtenPaths.count, writtenPaths.count == 1 ? "" : "s");
    for (NSString *failure in failedPaths) {
        fprintf(stderr, "%s\n", failure.UTF8String ?: "write failed");
    }
    return 0;
}

static NSString *NormalizedRuleIdentityString(id value, BOOL lowercase) {
    if (![value isKindOfClass:[NSString class]]) {
        return nil;
    }
    NSString *result = [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (result.length == 0) {
        return nil;
    }
    return lowercase ? result.lowercaseString : result;
}

static BOOL NormalizedRuleIdentityBool(id value) {
    if ([value respondsToSelector:@selector(boolValue)]) {
        return [value boolValue];
    }
    return NO;
}

static BOOL LinkRuleHasSameIdentity(NSDictionary *lhs, NSDictionary *rhs) {
    if (![lhs isKindOfClass:[NSDictionary class]] || ![rhs isKindOfClass:[NSDictionary class]]) {
        return NO;
    }

    NSString *lhsRuleID = NormalizedRuleIdentityString(lhs[kDSLinkRuleRuleIDKey], NO);
    NSString *rhsRuleID = NormalizedRuleIdentityString(rhs[kDSLinkRuleRuleIDKey], NO);
    if (lhsRuleID.length > 0 || rhsRuleID.length > 0) {
        return lhsRuleID.length > 0 && [lhsRuleID isEqualToString:rhsRuleID];
    }

    NSString *lhsHost = NormalizedRuleIdentityString(lhs[kDSLinkRuleHostKey], YES);
    NSString *rhsHost = NormalizedRuleIdentityString(rhs[kDSLinkRuleHostKey], YES);
    if (lhsHost.length == 0 || ![lhsHost isEqualToString:rhsHost]) {
        return NO;
    }

    NSString *lhsPathMatcher = NormalizedRuleIdentityString(lhs[kDSLinkRulePathMatcherKey], NO) ?: [DSRoutingConfig pathMatcherStringForLinkRule:lhs];
    NSString *rhsPathMatcher = NormalizedRuleIdentityString(rhs[kDSLinkRulePathMatcherKey], NO) ?: [DSRoutingConfig pathMatcherStringForLinkRule:rhs];
    NSString *lhsQueryMatcher = NormalizedRuleIdentityString(lhs[kDSLinkRuleQueryMatcherKey], NO);
    NSString *rhsQueryMatcher = NormalizedRuleIdentityString(rhs[kDSLinkRuleQueryMatcherKey], NO);

    BOOL lhsWildcard = NormalizedRuleIdentityBool(lhs[kDSLinkRuleHostWildcardKey]);
    BOOL rhsWildcard = NormalizedRuleIdentityBool(rhs[kDSLinkRuleHostWildcardKey]);

    return ((lhsPathMatcher ?: (id)kCFNull) == (rhsPathMatcher ?: (id)kCFNull) || [lhsPathMatcher isEqualToString:rhsPathMatcher]) &&
           ((lhsQueryMatcher ?: (id)kCFNull) == (rhsQueryMatcher ?: (id)kCFNull) || [lhsQueryMatcher isEqualToString:rhsQueryMatcher]) &&
           lhsWildcard == rhsWildcard;
}

static void RemoveMatchingLinkRules(NSMutableArray *rules, NSDictionary *identity) {
    NSIndexSet *indexes = [rules indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
        NSDictionary *rule = [DSRoutingConfig normalizedLinkRuleFromValue:obj];
        return LinkRuleHasSameIdentity(rule, identity);
    }];
    if (indexes.count > 0) {
        [rules removeObjectsAtIndexes:indexes];
    }
}

typedef struct {
    const void *replacement;
    const void *replacee;
} DSInterposeRecord;

extern int xpc_pipe_routine(xpc_object_t pipe, xpc_object_t message, xpc_object_t *reply);
extern int xpc_pipe_routine_with_flags(xpc_object_t pipe, xpc_object_t message, xpc_object_t *reply, uint64_t flags);

#define DS_INTERPOSE(_replacement, _replacee) \
    __attribute__((used)) static const DSInterposeRecord _interpose_##_replacee \
    __attribute__((section("__DATA,__interpose"))) = { (const void *)(unsigned long)&_replacement, (const void *)(unsigned long)&_replacee };

static BOOL gDSTraceActive = NO;
static NSString *gDSTraceSelector = nil;
static NSMutableArray<NSDictionary *> *gDSTraceEvents = nil;
static void (*gOrigXPCSendMessage)(xpc_connection_t, xpc_object_t) = NULL;
static void (*gOrigXPCSendMessageWithReply)(xpc_connection_t, xpc_object_t, dispatch_queue_t, xpc_handler_t) = NULL;
static xpc_object_t (*gOrigXPCSendMessageWithReplySync)(xpc_connection_t, xpc_object_t) = NULL;
static int (*gOrigXPCPipeRoutine)(xpc_object_t, xpc_object_t, xpc_object_t *) = NULL;
static int (*gOrigXPCPipeRoutineWithFlags)(xpc_object_t, xpc_object_t, xpc_object_t *, uint64_t) = NULL;
static mach_msg_return_t (*gOrigMachMsg)(mach_msg_header_t *, mach_msg_option_t, mach_msg_size_t, mach_msg_size_t, mach_port_name_t, mach_msg_timeout_t, mach_port_name_t) = NULL;
static mach_msg_return_t (*gOrigMachMsgOverwrite)(mach_msg_header_t *, mach_msg_option_t, mach_msg_size_t, mach_msg_size_t, mach_port_name_t, mach_msg_timeout_t, mach_port_name_t, mach_msg_header_t *, mach_msg_size_t) = NULL;
static id (*gOrigLSLocalResolveQueries)(id, SEL, id, id, NSError **) = NULL;
static id (*gOrigLSLocalResolveWhatWeCanLocally)(id, SEL, id, id, NSError **) = NULL;
static void (*gOrigLSLocalEnumerateResolvedResults)(id, SEL, id, id, id) = NULL;
static id (*gOrigLSXPCResolveQueries)(id, SEL, id, id, NSError **) = NULL;
static id (*gOrigLSXPCResolveExpensiveRemoteQueries)(id, SEL, id, id, NSError **) = NULL;
static void (*gOrigLSXPCEnumerateResolvedResults)(id, SEL, id, id, id) = NULL;
static void (*gOrigLSAvailableApplicationsEnumerate)(id, SEL, id, id) = NULL;
static BOOL (*gOrigLSCanOpenURL)(id, SEL, id, BOOL, BOOL, id, NSError **) = NULL;
static BOOL (*gOrigLSInternalCanOpenURL)(id, SEL, id, BOOL, BOOL, id, NSError **) = NULL;

static NSMutableArray<NSDictionary *> *TraceEvents(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gDSTraceEvents = [NSMutableArray array];
    });
    return gDSTraceEvents;
}

static void ResolveXPCSymbols(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *handle = dlopen("/usr/lib/system/libxpc.dylib", RTLD_NOW);
        gOrigXPCSendMessage = (void (*)(xpc_connection_t, xpc_object_t))dlsym(handle ?: RTLD_NEXT, "xpc_connection_send_message");
        gOrigXPCSendMessageWithReply = (void (*)(xpc_connection_t, xpc_object_t, dispatch_queue_t, xpc_handler_t))dlsym(handle ?: RTLD_NEXT, "xpc_connection_send_message_with_reply");
        gOrigXPCSendMessageWithReplySync = (xpc_object_t (*)(xpc_connection_t, xpc_object_t))dlsym(handle ?: RTLD_NEXT, "xpc_connection_send_message_with_reply_sync");
        gOrigXPCPipeRoutine = (int (*)(xpc_object_t, xpc_object_t, xpc_object_t *))dlsym(handle ?: RTLD_NEXT, "xpc_pipe_routine");
        gOrigXPCPipeRoutineWithFlags = (int (*)(xpc_object_t, xpc_object_t, xpc_object_t *, uint64_t))dlsym(handle ?: RTLD_NEXT, "xpc_pipe_routine_with_flags");
        gOrigMachMsg = (mach_msg_return_t (*)(mach_msg_header_t *, mach_msg_option_t, mach_msg_size_t, mach_msg_size_t, mach_port_name_t, mach_msg_timeout_t, mach_port_name_t))dlsym(RTLD_NEXT, "mach_msg");
        gOrigMachMsgOverwrite = (mach_msg_return_t (*)(mach_msg_header_t *, mach_msg_option_t, mach_msg_size_t, mach_msg_size_t, mach_port_name_t, mach_msg_timeout_t, mach_port_name_t, mach_msg_header_t *, mach_msg_size_t))dlsym(RTLD_NEXT, "mach_msg_overwrite");
    });
}

static NSString *XPCDescription(xpc_object_t object) {
    if (!object) {
        return nil;
    }
    char *description = xpc_copy_description(object);
    if (!description) {
        return nil;
    }
    NSString *value = [NSString stringWithUTF8String:description];
    free(description);
    return value;
}

static void TraceRecord(NSString *kind, xpc_object_t message, xpc_object_t reply) {
    if (!gDSTraceActive) {
        return;
    }

    NSMutableDictionary *event = [NSMutableDictionary dictionary];
    event[@"kind"] = kind ?: @"unknown";
    event[@"selector"] = gDSTraceSelector ?: @"";

    NSString *messageDescription = XPCDescription(message);
    if (messageDescription.length > 0) {
        event[@"message"] = messageDescription;
    }

    NSString *replyDescription = XPCDescription(reply);
    if (replyDescription.length > 0) {
        event[@"reply"] = replyDescription;
    }

    NSArray<NSString *> *stack = [NSThread callStackSymbols];
    if (stack.count > 0) {
        NSUInteger limit = MIN((NSUInteger)12, stack.count);
        event[@"stack"] = [stack subarrayWithRange:NSMakeRange(0, limit)];
    }

    [TraceEvents() addObject:event];
}

static void TraceRecordObjectiveC(NSString *kind, id target, SEL selector, NSDictionary *extra) {
    if (!gDSTraceActive) {
        return;
    }

    NSMutableDictionary *event = [NSMutableDictionary dictionary];
    event[@"kind"] = kind ?: @"objc";
    event[@"selector"] = gDSTraceSelector ?: @"";
    event[@"targetClass"] = target ? NSStringFromClass([target class]) : @"<nil>";
    event[@"method"] = selector ? NSStringFromSelector(selector) : @"<nil>";
    if (extra.count > 0) {
        [event addEntriesFromDictionary:extra];
    }

    NSArray<NSString *> *stack = [NSThread callStackSymbols];
    if (stack.count > 0) {
        NSUInteger limit = MIN((NSUInteger)12, stack.count);
        event[@"stack"] = [stack subarrayWithRange:NSMakeRange(0, limit)];
    }

    [TraceEvents() addObject:event];
}

static void TraceRecordMach(NSString *kind,
                            const mach_msg_header_t *message,
                            mach_msg_option_t option,
                            mach_msg_size_t sendSize,
                            mach_msg_size_t receiveSize,
                            mach_port_name_t receiveName,
                            mach_msg_timeout_t timeout,
                            mach_port_name_t notify,
                            mach_msg_return_t returnCode) {
    if (!gDSTraceActive) {
        return;
    }

    NSMutableDictionary *event = [NSMutableDictionary dictionary];
    event[@"kind"] = kind ?: @"mach_msg";
    event[@"selector"] = gDSTraceSelector ?: @"";
    event[@"option"] = @((uint32_t)option);
    event[@"sendSize"] = @((uint32_t)sendSize);
    event[@"receiveSize"] = @((uint32_t)receiveSize);
    event[@"receiveName"] = @((uint32_t)receiveName);
    event[@"timeout"] = @((uint32_t)timeout);
    event[@"notify"] = @((uint32_t)notify);
    event[@"returnCode"] = @((int32_t)returnCode);

    if (message) {
        event[@"msghBits"] = @((uint32_t)message->msgh_bits);
        event[@"msghSize"] = @((uint32_t)message->msgh_size);
        event[@"remotePort"] = @((uint32_t)message->msgh_remote_port);
        event[@"localPort"] = @((uint32_t)message->msgh_local_port);
        event[@"voucherPort"] = @((uint32_t)message->msgh_voucher_port);
        event[@"msghId"] = @((int32_t)message->msgh_id);
    }

    NSArray<NSString *> *stack = [NSThread callStackSymbols];
    if (stack.count > 0) {
        NSUInteger limit = MIN((NSUInteger)12, stack.count);
        event[@"stack"] = [stack subarrayWithRange:NSMakeRange(0, limit)];
    }

    [TraceEvents() addObject:event];
}

static void TraceBegin(NSString *selectorName) {
    [TraceEvents() removeAllObjects];
    gDSTraceSelector = [selectorName copy] ?: @"";
    gDSTraceActive = YES;
}

static NSArray<NSDictionary *> *TraceEnd(void) {
    NSArray<NSDictionary *> *events = [TraceEvents() copy];
    [TraceEvents() removeAllObjects];
    gDSTraceSelector = nil;
    gDSTraceActive = NO;
    return events ?: @[];
}

static void DSXPCSendMessage(xpc_connection_t connection, xpc_object_t message) {
    ResolveXPCSymbols();
    TraceRecord(@"xpc_connection_send_message", message, nil);
    if (gOrigXPCSendMessage) {
        gOrigXPCSendMessage(connection, message);
    }
}
DS_INTERPOSE(DSXPCSendMessage, xpc_connection_send_message)

static void DSXPCSendMessageWithReply(xpc_connection_t connection, xpc_object_t message, dispatch_queue_t replyQueue, xpc_handler_t handler) {
    ResolveXPCSymbols();
    TraceRecord(@"xpc_connection_send_message_with_reply", message, nil);
    if (gOrigXPCSendMessageWithReply) {
        gOrigXPCSendMessageWithReply(connection, message, replyQueue, handler);
    }
}
DS_INTERPOSE(DSXPCSendMessageWithReply, xpc_connection_send_message_with_reply)

static xpc_object_t DSXPCSendMessageWithReplySync(xpc_connection_t connection, xpc_object_t message) {
    ResolveXPCSymbols();
    xpc_object_t reply = gOrigXPCSendMessageWithReplySync ? gOrigXPCSendMessageWithReplySync(connection, message) : nil;
    TraceRecord(@"xpc_connection_send_message_with_reply_sync", message, reply);
    return reply;
}
DS_INTERPOSE(DSXPCSendMessageWithReplySync, xpc_connection_send_message_with_reply_sync)

static int DSXPCPipeRoutine(xpc_object_t pipe, xpc_object_t message, xpc_object_t *reply) {
    ResolveXPCSymbols();
    int status = gOrigXPCPipeRoutine ? gOrigXPCPipeRoutine(pipe, message, reply) : -1;
    TraceRecord(@"xpc_pipe_routine", message, reply ? *reply : nil);
    return status;
}
DS_INTERPOSE(DSXPCPipeRoutine, xpc_pipe_routine)

static int DSXPCPipeRoutineWithFlags(xpc_object_t pipe, xpc_object_t message, xpc_object_t *reply, uint64_t flags) {
    ResolveXPCSymbols();
    int status = gOrigXPCPipeRoutineWithFlags ? gOrigXPCPipeRoutineWithFlags(pipe, message, reply, flags) : -1;
    TraceRecord([NSString stringWithFormat:@"xpc_pipe_routine_with_flags(%llu)", flags], message, reply ? *reply : nil);
    return status;
}
DS_INTERPOSE(DSXPCPipeRoutineWithFlags, xpc_pipe_routine_with_flags)

static mach_msg_return_t DSMachMsg(mach_msg_header_t *message,
                                   mach_msg_option_t option,
                                   mach_msg_size_t sendSize,
                                   mach_msg_size_t receiveSize,
                                   mach_port_name_t receiveName,
                                   mach_msg_timeout_t timeout,
                                   mach_port_name_t notify) {
    ResolveXPCSymbols();

    mach_msg_header_t messageBefore = {0};
    const mach_msg_header_t *before = NULL;
    if (message) {
        messageBefore = *message;
        before = &messageBefore;
    }

    TraceRecordMach(@"mach_msg.before", before, option, sendSize, receiveSize, receiveName, timeout, notify, MACH_MSG_SUCCESS);
    mach_msg_return_t status = gOrigMachMsg ? gOrigMachMsg(message, option, sendSize, receiveSize, receiveName, timeout, notify) : MACH_SEND_INVALID_DEST;
    TraceRecordMach(@"mach_msg.after", message, option, sendSize, receiveSize, receiveName, timeout, notify, status);
    return status;
}
DS_INTERPOSE(DSMachMsg, mach_msg)

static mach_msg_return_t DSMachMsgOverwrite(mach_msg_header_t *message,
                                            mach_msg_option_t option,
                                            mach_msg_size_t sendSize,
                                            mach_msg_size_t receiveSize,
                                            mach_port_name_t receiveName,
                                            mach_msg_timeout_t timeout,
                                            mach_port_name_t notify,
                                            mach_msg_header_t *receiveMessage,
                                            mach_msg_size_t receiveLimit) {
    ResolveXPCSymbols();

    mach_msg_header_t messageBefore = {0};
    const mach_msg_header_t *before = NULL;
    if (message) {
        messageBefore = *message;
        before = &messageBefore;
    }

    TraceRecordMach(@"mach_msg_overwrite.before", before, option, sendSize, receiveSize, receiveName, timeout, notify, MACH_MSG_SUCCESS);
    mach_msg_return_t status = gOrigMachMsgOverwrite ? gOrigMachMsgOverwrite(message, option, sendSize, receiveSize, receiveName, timeout, notify, receiveMessage, receiveLimit) : MACH_SEND_INVALID_DEST;
    TraceRecordMach(@"mach_msg_overwrite.after", receiveMessage ?: message, option, sendSize, receiveLimit, receiveName, timeout, notify, status);
    return status;
}
DS_INTERPOSE(DSMachMsgOverwrite, mach_msg_overwrite)

static id DSTraceLSLocalResolveQueries(id self, SEL _cmd, id queries, id connection, NSError **error) {
    TraceRecordObjectiveC(@"objc.before", self, _cmd, @{
        @"queriesClass": queries ? NSStringFromClass([queries class]) : @"<nil>",
        @"connectionClass": connection ? NSStringFromClass([connection class]) : @"<nil>"
    });
    id result = gOrigLSLocalResolveQueries ? gOrigLSLocalResolveQueries(self, _cmd, queries, connection, error) : nil;
    TraceRecordObjectiveC(@"objc.after", self, _cmd, @{
        @"resultClass": result ? NSStringFromClass([result class]) : @"<nil>",
        @"error": (error && *error && [*error localizedDescription].length > 0) ? [*error localizedDescription] : @""
    });
    return result;
}

static id DSTraceLSLocalResolveWhatWeCanLocally(id self, SEL _cmd, id queries, id connection, NSError **error) {
    TraceRecordObjectiveC(@"objc.before", self, _cmd, @{
        @"queriesClass": queries ? NSStringFromClass([queries class]) : @"<nil>",
        @"connectionClass": connection ? NSStringFromClass([connection class]) : @"<nil>"
    });
    id result = gOrigLSLocalResolveWhatWeCanLocally ? gOrigLSLocalResolveWhatWeCanLocally(self, _cmd, queries, connection, error) : nil;
    TraceRecordObjectiveC(@"objc.after", self, _cmd, @{
        @"resultClass": result ? NSStringFromClass([result class]) : @"<nil>",
        @"error": (error && *error && [*error localizedDescription].length > 0) ? [*error localizedDescription] : @""
    });
    return result;
}

static void DSTraceLSLocalEnumerateResolvedResults(id self, SEL _cmd, id query, id connection, id block) {
    TraceRecordObjectiveC(@"objc.before", self, _cmd, @{
        @"queryClass": query ? NSStringFromClass([query class]) : @"<nil>",
        @"connectionClass": connection ? NSStringFromClass([connection class]) : @"<nil>",
        @"blockClass": block ? NSStringFromClass([block class]) : @"<nil>"
    });
    if (gOrigLSLocalEnumerateResolvedResults) {
        gOrigLSLocalEnumerateResolvedResults(self, _cmd, query, connection, block);
    }
    TraceRecordObjectiveC(@"objc.after", self, _cmd, nil);
}

static id DSTraceLSXPCResolveQueries(id self, SEL _cmd, id queries, id connection, NSError **error) {
    TraceRecordObjectiveC(@"objc.before", self, _cmd, @{
        @"queriesClass": queries ? NSStringFromClass([queries class]) : @"<nil>",
        @"connectionClass": connection ? NSStringFromClass([connection class]) : @"<nil>"
    });
    id result = gOrigLSXPCResolveQueries ? gOrigLSXPCResolveQueries(self, _cmd, queries, connection, error) : nil;
    TraceRecordObjectiveC(@"objc.after", self, _cmd, @{
        @"resultClass": result ? NSStringFromClass([result class]) : @"<nil>",
        @"error": (error && *error && [*error localizedDescription].length > 0) ? [*error localizedDescription] : @""
    });
    return result;
}

static id DSTraceLSXPCResolveExpensiveRemoteQueries(id self, SEL _cmd, id queries, id connection, NSError **error) {
    TraceRecordObjectiveC(@"objc.before", self, _cmd, @{
        @"queriesClass": queries ? NSStringFromClass([queries class]) : @"<nil>",
        @"connectionClass": connection ? NSStringFromClass([connection class]) : @"<nil>"
    });
    id result = gOrigLSXPCResolveExpensiveRemoteQueries ? gOrigLSXPCResolveExpensiveRemoteQueries(self, _cmd, queries, connection, error) : nil;
    TraceRecordObjectiveC(@"objc.after", self, _cmd, @{
        @"resultClass": result ? NSStringFromClass([result class]) : @"<nil>",
        @"error": (error && *error && [*error localizedDescription].length > 0) ? [*error localizedDescription] : @""
    });
    return result;
}

static void DSTraceLSXPCEnumerateResolvedResults(id self, SEL _cmd, id query, id connection, id block) {
    TraceRecordObjectiveC(@"objc.before", self, _cmd, @{
        @"queryClass": query ? NSStringFromClass([query class]) : @"<nil>",
        @"connectionClass": connection ? NSStringFromClass([connection class]) : @"<nil>",
        @"blockClass": block ? NSStringFromClass([block class]) : @"<nil>"
    });
    if (gOrigLSXPCEnumerateResolvedResults) {
        gOrigLSXPCEnumerateResolvedResults(self, _cmd, query, connection, block);
    }
    TraceRecordObjectiveC(@"objc.after", self, _cmd, nil);
}

static void DSTraceLSAvailableApplicationsEnumerate(id self, SEL _cmd, id connection, id block) {
    TraceRecordObjectiveC(@"objc.before", self, _cmd, @{
        @"connectionClass": connection ? NSStringFromClass([connection class]) : @"<nil>",
        @"blockClass": block ? NSStringFromClass([block class]) : @"<nil>"
    });
    if (gOrigLSAvailableApplicationsEnumerate) {
        gOrigLSAvailableApplicationsEnumerate(self, _cmd, connection, block);
    }
    TraceRecordObjectiveC(@"objc.after", self, _cmd, nil);
}

static BOOL DSTraceLSCanOpenURL(id self, SEL _cmd, id url, BOOL publicSchemes, BOOL privateSchemes, id connection, NSError **error) {
    TraceRecordObjectiveC(@"objc.before", self, _cmd, @{
        @"url": [url respondsToSelector:@selector(absoluteString)] ? [url absoluteString] ?: @"" : [NSString stringWithFormat:@"%@", url ?: @""],
        @"publicSchemes": @(publicSchemes),
        @"privateSchemes": @(privateSchemes),
        @"connectionClass": connection ? NSStringFromClass([connection class]) : @"<nil>"
    });
    BOOL result = gOrigLSCanOpenURL ? gOrigLSCanOpenURL(self, _cmd, url, publicSchemes, privateSchemes, connection, error) : NO;
    TraceRecordObjectiveC(@"objc.after", self, _cmd, @{
        @"result": @(result),
        @"error": (error && *error && [*error localizedDescription].length > 0) ? [*error localizedDescription] : @""
    });
    return result;
}

static BOOL DSTraceLSInternalCanOpenURL(id self, SEL _cmd, id url, BOOL publicSchemes, BOOL privateSchemes, id connection, NSError **error) {
    TraceRecordObjectiveC(@"objc.before", self, _cmd, @{
        @"url": [url respondsToSelector:@selector(absoluteString)] ? [url absoluteString] ?: @"" : [NSString stringWithFormat:@"%@", url ?: @""],
        @"publicSchemes": @(publicSchemes),
        @"privateSchemes": @(privateSchemes),
        @"connectionClass": connection ? NSStringFromClass([connection class]) : @"<nil>"
    });
    BOOL result = gOrigLSInternalCanOpenURL ? gOrigLSInternalCanOpenURL(self, _cmd, url, publicSchemes, privateSchemes, connection, error) : NO;
    TraceRecordObjectiveC(@"objc.after", self, _cmd, @{
        @"result": @(result),
        @"error": (error && *error && [*error localizedDescription].length > 0) ? [*error localizedDescription] : @""
    });
    return result;
}

static void InstallObjectiveCMethodTraces(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        struct {
            const char *className;
            const char *selectorName;
            IMP replacement;
            IMP *original;
        } hooks[] = {
            { "_LSLocalQueryResolver", "_resolveQueries:XPCConnection:error:", (IMP)DSTraceLSLocalResolveQueries, (IMP *)&gOrigLSLocalResolveQueries },
            { "_LSLocalQueryResolver", "resolveWhatWeCanLocallyWithQueries:XPCConnection:error:", (IMP)DSTraceLSLocalResolveWhatWeCanLocally, (IMP *)&gOrigLSLocalResolveWhatWeCanLocally },
            { "_LSLocalQueryResolver", "_enumerateResolvedResultsOfQuery:XPCConnection:withBlock:", (IMP)DSTraceLSLocalEnumerateResolvedResults, (IMP *)&gOrigLSLocalEnumerateResolvedResults },
            { "_LSXPCQueryResolver", "_resolveQueries:XPCConnection:error:", (IMP)DSTraceLSXPCResolveQueries, (IMP *)&gOrigLSXPCResolveQueries },
            { "_LSXPCQueryResolver", "resolveExpensiveRemoteQueriesInSet:XPCConnection:error:", (IMP)DSTraceLSXPCResolveExpensiveRemoteQueries, (IMP *)&gOrigLSXPCResolveExpensiveRemoteQueries },
            { "_LSXPCQueryResolver", "_enumerateResolvedResultsOfQuery:XPCConnection:withBlock:", (IMP)DSTraceLSXPCEnumerateResolvedResults, (IMP *)&gOrigLSXPCEnumerateResolvedResults },
            { "_LSAvailableApplicationsForURLQuery", "_enumerateWithXPCConnection:block:", (IMP)DSTraceLSAvailableApplicationsEnumerate, (IMP *)&gOrigLSAvailableApplicationsEnumerate },
            { "_LSCanOpenURLManager", "canOpenURL:publicSchemes:privateSchemes:XPCConnection:error:", (IMP)DSTraceLSCanOpenURL, (IMP *)&gOrigLSCanOpenURL },
            { "_LSCanOpenURLManager", "internalCanOpenURL:publicSchemes:privateSchemes:XPCConnection:error:", (IMP)DSTraceLSInternalCanOpenURL, (IMP *)&gOrigLSInternalCanOpenURL },
        };

        for (NSUInteger idx = 0; idx < sizeof(hooks) / sizeof(hooks[0]); idx++) {
            Class cls = NSClassFromString([NSString stringWithUTF8String:hooks[idx].className]);
            SEL selector = NSSelectorFromString([NSString stringWithUTF8String:hooks[idx].selectorName]);
            if (!cls || !selector) {
                continue;
            }
            Method method = class_getInstanceMethod(cls, selector);
            if (!method) {
                continue;
            }
            IMP previous = method_setImplementation(method, hooks[idx].replacement);
            if (hooks[idx].original) {
                *hooks[idx].original = previous;
            }
        }
    });
}

static id CallID0(id target, SEL selector) {
    return ((id (*)(id, SEL))objc_msgSend)(target, selector);
}

static id CallID1(id target, SEL selector, id arg1) {
    return ((id (*)(id, SEL, id))objc_msgSend)(target, selector, arg1);
}

static id CallID2Error(id target, SEL selector, id arg1, NSError **arg2) {
    return ((id (*)(id, SEL, id, NSError **))objc_msgSend)(target, selector, arg1, arg2);
}

static __unused id CallID3IDError(id target, SEL selector, id arg1, id arg2, NSError **arg3) {
    return ((id (*)(id, SEL, id, id, NSError **))objc_msgSend)(target, selector, arg1, arg2, arg3);
}

static id CallID3CountError(id target, SEL selector, id arg1, NSUInteger arg2, NSError **arg3) {
    return ((id (*)(id, SEL, id, NSUInteger, NSError **))objc_msgSend)(target, selector, arg1, arg2, arg3);
}

static __unused id CallID4IDCountError(id target, SEL selector, id arg1, id arg2, NSUInteger arg3, NSError **arg4) {
    return ((id (*)(id, SEL, id, id, NSUInteger, NSError **))objc_msgSend)(target, selector, arg1, arg2, arg3, arg4);
}

static BOOL CallBOOL2(id target, SEL selector, id arg1, NSError **arg2) {
    return ((BOOL (*)(id, SEL, id, NSError **))objc_msgSend)(target, selector, arg1, arg2);
}

static BOOL CallBOOL3(id target, SEL selector, id arg1, BOOL arg2, NSError **arg3) {
    return ((BOOL (*)(id, SEL, id, BOOL, NSError **))objc_msgSend)(target, selector, arg1, arg2, arg3);
}

static BOOL CallBOOL4(id target, SEL selector, id arg1, id arg2, NSError **arg3) {
    return ((BOOL (*)(id, SEL, id, id, NSError **))objc_msgSend)(target, selector, arg1, arg2, arg3);
}

static NSString *BundleIdentifierForProxy(id proxy) {
    if (!proxy) {
        return nil;
    }
    SEL selector = NSSelectorFromString(@"bundleIdentifier");
    if (![proxy respondsToSelector:selector]) {
        return nil;
    }
    id value = CallID0(proxy, selector);
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

static NSString *TrimmedDescription(id object) {
    if (!object) {
        return @"<nil>";
    }
    NSString *value = [NSString stringWithFormat:@"%@", object];
    if (value.length <= 320) {
        return value;
    }
    return [[value substringToIndex:320] stringByAppendingString:@"..."];
}

static id SafeValueForKey(id object, NSString *key) {
    if (!object || key.length == 0) {
        return nil;
    }
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static id JSONSafeObject(id object, NSUInteger depth);

static NSDictionary *InspectableObjectSnapshot(id object, NSUInteger depth) {
    if (!object) {
        return @{};
    }

    NSMutableDictionary *snapshot = [NSMutableDictionary dictionaryWithDictionary:@{
        @"class": NSStringFromClass([object class]) ?: @"<unknown>",
        @"description": TrimmedDescription(object),
    }];

    NSArray<NSString *> *keys = @[@"URL", @"url", @"bundleIdentifier", @"applicationProxy", @"targetApplicationProxy", @"details", @"paths", @"components", @"domain", @"host", @"path", @"browserState", @"state", @"appLink", @"appLinks", @"userInfo", @"serviceSpecifier", @"applicationIdentifier", @"applicationIdentifiers", @"domainHost", @"rawValue", @"patterns", @"pattern", @"patternList", @"pathPattern", @"requiredEntitlement", @"substitutionVariables", @"defaults", @"isApproved", @"userApprovalState", @"frameworkApprovalState", @"siteApprovalState", @"modeOfOperation", @"serviceType"];
    for (NSString *key in keys) {
        id value = SafeValueForKey(object, key);
        if (value) {
            snapshot[key] = JSONSafeObject(value, depth + 1);
        }
    }

    NSArray<NSString *> *selectors = @[@"URL", @"bundleIdentifier", @"applicationProxy", @"targetApplicationProxy", @"details", @"paths", @"components", @"domain", @"host", @"path", @"browserState", @"state", @"serviceSpecifier", @"applicationIdentifier", @"domainHost", @"rawValue", @"patterns", @"pattern", @"patternList", @"pathPattern", @"requiredEntitlement", @"substitutionVariables", @"defaults"];
    for (NSString *selectorName in selectors) {
        if (snapshot[selectorName] != nil) {
            continue;
        }
        SEL selector = NSSelectorFromString(selectorName);
        if (![object respondsToSelector:selector]) {
            continue;
        }
        id value = CallID0(object, selector);
        if (value) {
            snapshot[selectorName] = JSONSafeObject(value, depth + 1);
        }
    }

    return snapshot;
}

static id JSONSafeObject(id object, NSUInteger depth) {
    if (!object) {
        return [NSNull null];
    }
    if (depth > 3) {
        return TrimmedDescription(object);
    }
    if ([object isKindOfClass:[NSString class]] || [object isKindOfClass:[NSNumber class]] || [object isKindOfClass:[NSNull class]]) {
        return object;
    }
    if ([object isKindOfClass:[NSURL class]]) {
        return [(NSURL *)object absoluteString] ?: @"";
    }
    if ([object isKindOfClass:[NSData class]]) {
        return @{ @"class": NSStringFromClass([object class]) ?: @"NSData", @"length": @([(NSData *)object length]) };
    }
    if ([object isKindOfClass:[NSArray class]] || [object isKindOfClass:[NSSet class]] || [object isKindOfClass:[NSOrderedSet class]]) {
        NSArray *objects = [object isKindOfClass:[NSArray class]] ? object : ([object isKindOfClass:[NSSet class]] ? [(NSSet *)object allObjects] : [(NSOrderedSet *)object array]);
        NSMutableArray *values = [NSMutableArray array];
        NSUInteger limit = MIN((NSUInteger)12, objects.count);
        for (NSUInteger idx = 0; idx < limit; idx++) {
            [values addObject:JSONSafeObject(objects[idx], depth + 1) ?: [NSNull null]];
        }
        if (objects.count > limit) {
            [values addObject:[NSString stringWithFormat:@"... %lu more", (unsigned long)(objects.count - limit)]];
        }
        return values;
    }
    if ([object isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
        __block NSUInteger count = 0;
        [(NSDictionary *)object enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            if (count >= 12) {
                *stop = YES;
                return;
            }
            NSString *stringKey = [key isKindOfClass:[NSString class]] ? key : TrimmedDescription(key);
            dictionary[stringKey] = JSONSafeObject(obj, depth + 1) ?: [NSNull null];
            count++;
        }];
        if ([(NSDictionary *)object count] > count) {
            dictionary[@"..."] = [NSString stringWithFormat:@"%lu more", (unsigned long)([(NSDictionary *)object count] - count)];
        }
        return dictionary;
    }
    return InspectableObjectSnapshot(object, depth);
}

static __unused NSArray *CollectionObjects(id object) {
    if (!object) {
        return @[];
    }
    if ([object isKindOfClass:[NSArray class]]) {
        return object;
    }
    if ([object isKindOfClass:[NSOrderedSet class]]) {
        return [(NSOrderedSet *)object array];
    }
    if ([object isKindOfClass:[NSSet class]]) {
        return [(NSSet *)object allObjects];
    }
    return @[object];
}

static NSString *JSONStringScalar(id value, BOOL lowercase) {
    if (![value isKindOfClass:[NSString class]]) {
        return nil;
    }
    NSString *result = [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (result.length == 0) {
        return nil;
    }
    return lowercase ? result.lowercaseString : result;
}

static NSString *JSONStringFromDate(id value) {
    if (![value isKindOfClass:[NSDate class]]) {
        return nil;
    }
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
    });
    return [formatter stringFromDate:(NSDate *)value];
}

static BOOL URLHostMatchesRuleHost(NSString *urlHost, NSDictionary *rule) {
    NSString *normalizedURLHost = JSONStringScalar(urlHost, YES);
    NSString *ruleHost = JSONStringScalar(rule[kDSLinkRuleHostKey], YES);
    if (normalizedURLHost.length == 0 || ruleHost.length == 0) {
        return NO;
    }
    if ([normalizedURLHost isEqualToString:ruleHost]) {
        return YES;
    }
    if (!NormalizedRuleIdentityBool(rule[kDSLinkRuleHostWildcardKey])) {
        return NO;
    }
    return [normalizedURLHost hasSuffix:[@"." stringByAppendingString:ruleHost]];
}

static NSDictionary *SerializableRuleSummary(NSDictionary *rule, NSURL *url, NSInteger matchScore) {
    if (![rule isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    NSArray<NSString *> *stringKeys = @[
        kDSLinkRuleRuleIDKey,
        kDSLinkRuleHostKey,
        kDSLinkRulePathKey,
        kDSLinkRuleMatchTypeKey,
        kDSLinkRuleBundleIDKey,
        kDSLinkRuleSourceHintKey,
        kDSLinkRulePathMatcherKey,
        kDSLinkRuleQueryMatcherKey,
        kDSLinkRuleIdentityVersionKey,
        kDSLinkRuleAssociatedBundleIDKey,
        kDSLinkRulePatternKindKey,
        kDSLinkRuleRawPatternDataKey,
    ];
    for (NSString *key in stringKeys) {
        NSString *value = JSONStringScalar(rule[key], [key isEqualToString:kDSLinkRuleHostKey]);
        if (value.length > 0) {
            result[key] = value;
        }
    }

    if (![result[kDSLinkRulePathMatcherKey] isKindOfClass:[NSString class]]) {
        NSString *pathMatcher = [DSRoutingConfig pathMatcherStringForLinkRule:rule];
        if (pathMatcher.length > 0) {
            result[kDSLinkRulePathMatcherKey] = pathMatcher;
        }
    }

    if (rule[kDSLinkRuleHostWildcardKey] != nil) {
        result[kDSLinkRuleHostWildcardKey] = @(NormalizedRuleIdentityBool(rule[kDSLinkRuleHostWildcardKey]));
    }
    if ([rule[kDSLinkRuleRawOpcodeKey] isKindOfClass:[NSNumber class]]) {
        result[kDSLinkRuleRawOpcodeKey] = rule[kDSLinkRuleRawOpcodeKey];
    }
    if (url) {
        result[@"matchScore"] = (matchScore == NSNotFound) ? [NSNull null] : @(matchScore);
        result[@"matchesURL"] = @(matchScore != NSNotFound);
    }
    return result;
}

static NSDictionary *SerializableSnapshotSummary(NSDictionary *snapshot, NSUInteger ruleCount) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    NSString *path = JSONStringScalar(snapshot[kDSSWCSnapshotPathKey], NO);
    if (path.length > 0) {
        result[kDSSWCSnapshotPathKey] = path;
    }
    if ([snapshot[kDSSWCSnapshotFileSizeKey] isKindOfClass:[NSNumber class]]) {
        result[kDSSWCSnapshotFileSizeKey] = snapshot[kDSSWCSnapshotFileSizeKey];
    }
    NSString *generatedAt = JSONStringFromDate(snapshot[kDSSWCSnapshotGeneratedAtKey]);
    if (generatedAt.length > 0) {
        result[kDSSWCSnapshotGeneratedAtKey] = generatedAt;
    }
    NSString *fileMTime = JSONStringFromDate(snapshot[kDSSWCSnapshotFileMTimeKey]);
    if (fileMTime.length > 0) {
        result[kDSSWCSnapshotFileMTimeKey] = fileMTime;
    }
    NSString *error = JSONStringScalar(snapshot[kDSSWCSnapshotErrorKey], NO);
    if (error.length > 0) {
        result[kDSSWCSnapshotErrorKey] = error;
    }
    result[@"ruleCount"] = @(ruleCount);
    return result;
}

static int InspectSWC(NSString *rawURL) {
    NSURL *url = [NSURL URLWithString:rawURL ?: @""];
    NSString *host = JSONStringScalar(url.host, YES);
    if (!url || host.length == 0) {
        fprintf(stderr, "invalid url\n");
        return 1;
    }

    NSDictionary<NSString *, id> *snapshot = [DSRoutingConfig sharedWebCredentialsSnapshot];
    NSArray<NSDictionary<NSString *, id> *> *rules = [DSRoutingConfig systemLinkRulesFromSnapshot:snapshot];
    NSDictionary<NSString *, id> *bestRule = [DSRoutingConfig bestSystemLinkRuleForURL:url fromRules:rules];
    NSInteger bestMatchScore = bestRule ? [DSRoutingConfig matchScoreForSystemLinkRule:bestRule URL:url] : NSNotFound;

    NSMutableArray<NSDictionary *> *hostCandidateRules = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *matchedRules = [NSMutableArray array];
    NSUInteger hostCandidateRuleCount = 0;
    NSUInteger matchedRuleCount = 0;
    const NSUInteger ruleDisplayLimit = 64;

    for (NSDictionary<NSString *, id> *rule in rules) {
        if (!URLHostMatchesRuleHost(host, rule)) {
            continue;
        }
        hostCandidateRuleCount += 1;
        NSInteger matchScore = [DSRoutingConfig matchScoreForSystemLinkRule:rule URL:url];
        NSDictionary *summary = SerializableRuleSummary(rule, url, matchScore);
        if (summary && hostCandidateRules.count < ruleDisplayLimit) {
            [hostCandidateRules addObject:summary];
        }
        if (matchScore != NSNotFound) {
            matchedRuleCount += 1;
            if (summary && matchedRules.count < ruleDisplayLimit) {
                [matchedRules addObject:summary];
            }
        }
    }

    NSDictionary *config = [DSRoutingConfig loadConfig];
    NSArray<NSDictionary<NSString *, id> *> *configuredLinkRules = [DSRoutingConfig linkRulesFromConfig:config];
    NSMutableArray<NSDictionary *> *configuredHostRules = [NSMutableArray array];
    NSDictionary *configuredOverrideForBestRule = nil;
    for (NSDictionary<NSString *, id> *rule in configuredLinkRules) {
        if (bestRule && !configuredOverrideForBestRule && LinkRuleHasSameIdentity(rule, bestRule)) {
            configuredOverrideForBestRule = rule;
        }
        if (!URLHostMatchesRuleHost(host, rule)) {
            continue;
        }
        NSDictionary *summary = SerializableRuleSummary(rule, nil, NSNotFound);
        if (summary) {
            [configuredHostRules addObject:summary];
        }
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"url"] = rawURL ?: @"";
    result[@"host"] = host;
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSString *displayPath = components.path.length > 0 ? components.path : (url.path.length > 0 ? url.path : @"/");
    result[@"path"] = displayPath;
    if (url.query.length > 0) {
        result[@"query"] = url.query;
    }
    result[@"swcSnapshot"] = SerializableSnapshotSummary(snapshot, rules.count);
    result[@"hostCandidateRuleCount"] = @(hostCandidateRuleCount);
    result[@"matchedRuleCount"] = @(matchedRuleCount);
    result[@"hostCandidateRules"] = hostCandidateRules;
    result[@"matchedRules"] = matchedRules;
    result[@"configuredHostRules"] = configuredHostRules;
    result[@"configuredOverrideForBestRule"] = configuredOverrideForBestRule ? SerializableRuleSummary(configuredOverrideForBestRule, nil, NSNotFound) : [NSNull null];
    result[@"bestMatch"] = bestRule ? SerializableRuleSummary(bestRule, url, bestMatchScore) : [NSNull null];
    if (hostCandidateRuleCount > hostCandidateRules.count) {
        result[@"hostCandidateRulesTruncated"] = @YES;
    }
    if (matchedRuleCount > matchedRules.count) {
        result[@"matchedRulesTruncated"] = @YES;
    }

    NSError *jsonError = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:&jsonError];
    if (!json) {
        fprintf(stderr, "failed to serialize swc result: %s\n", jsonError.localizedDescription.UTF8String ?: "unknown error");
        return 1;
    }

    printf("%s\n", [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String ?: "{}");
    return 0;
}

static id AppLinksForURL(NSURL *url, NSString **selectorNameUsed, NSError **error) {
    Class cls = NSClassFromString(@"LSAppLink");
    if (!cls || !url) {
        return nil;
    }

    NSArray<NSString *> *selectors = @[@"appLinksWithURL:limit:error:", @"appLinksWithURL:error:", @"appLinkWithURL:error:", @"appLinkForURL:error:"];
    for (NSString *selectorName in selectors) {
        SEL selector = NSSelectorFromString(selectorName);
        if (![cls respondsToSelector:selector]) {
            continue;
        }
        if (selectorNameUsed) {
            *selectorNameUsed = selectorName;
        }
        if ([selectorName isEqualToString:@"appLinksWithURL:limit:error:"]) {
            return CallID3CountError(cls, selector, url, 16, error);
        }
        return CallID2Error(cls, selector, url, error);
    }
    return nil;
}

static int InspectAppLink(NSString *rawURL) {
    LoadLaunchServicesFrameworks();

    NSURL *url = [NSURL URLWithString:rawURL ?: @""];
    if (!url) {
        fprintf(stderr, "invalid url\n");
        return 1;
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"url"] = rawURL ?: @"";

    Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
    SEL defaultWorkspaceSelector = NSSelectorFromString(@"defaultWorkspace");
    if (wsClass && [wsClass respondsToSelector:defaultWorkspaceSelector]) {
        id workspace = CallID0(wsClass, defaultWorkspaceSelector);
        if (workspace) {
            NSMutableDictionary *workspaceResult = [NSMutableDictionary dictionary];

            SEL candidatesSelector = NSSelectorFromString(@"applicationsAvailableForOpeningURL:");
            if ([workspace respondsToSelector:candidatesSelector]) {
                id candidates = CallID1(workspace, candidatesSelector, url);
                workspaceResult[@"applicationsAvailableForOpeningURL"] = JSONSafeObject(candidates, 0);
            }

            SEL overrideSelector = NSSelectorFromString(@"URLOverrideForURL:");
            if ([workspace respondsToSelector:overrideSelector]) {
                id proxy = CallID1(workspace, overrideSelector, url);
                workspaceResult[@"URLOverrideForURL"] = JSONSafeObject(proxy, 0);
            }

            SEL applicationSelector = NSSelectorFromString(@"applicationForOpeningResource:");
            if ([workspace respondsToSelector:applicationSelector]) {
                id proxy = CallID1(workspace, applicationSelector, url);
                workspaceResult[@"applicationForOpeningResource"] = JSONSafeObject(proxy, 0);
            }

            result[@"LSApplicationWorkspace"] = workspaceResult;
        }
    }

    NSMutableDictionary *appLinkResult = [NSMutableDictionary dictionary];
    Class appLinkClass = NSClassFromString(@"LSAppLink");
    appLinkResult[@"classAvailable"] = @(appLinkClass != Nil);
    NSError *error = nil;
    NSString *selectorName = nil;
    id appLinks = AppLinksForURL(url, &selectorName, &error);
    if (selectorName.length > 0) {
        appLinkResult[@"selector"] = selectorName;
    }
    if (appLinks) {
        appLinkResult[@"result"] = JSONSafeObject(appLinks, 0);
    }
    if (error.localizedDescription.length > 0) {
        appLinkResult[@"error"] = error.localizedDescription;
    }
    result[@"LSAppLink"] = appLinkResult;

    NSData *json = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil];
    if (!json) {
        fprintf(stderr, "failed to serialize app-link result\n");
        return 1;
    }

    printf("%s\n", [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String ?: "{}");
    return 0;
}

static int InspectMethod(NSString *className, NSString *selectorName) {
    LoadLaunchServicesFrameworks();

    Class cls = NSClassFromString(className ?: @"");
    SEL selector = NSSelectorFromString(selectorName ?: @"");
    if (!cls || !selector) {
        fprintf(stderr, "class or selector unavailable\n");
        return 1;
    }

    Method instanceMethod = class_getInstanceMethod(cls, selector);
    if (instanceMethod) {
        printf("instance %s\n", method_getTypeEncoding(instanceMethod) ?: "");
        return 0;
    }

    Method classMethod = class_getClassMethod(cls, selector);
    if (classMethod) {
        printf("class %s\n", method_getTypeEncoding(classMethod) ?: "");
        return 0;
    }

    fprintf(stderr, "method not found\n");
    return 1;
}

static int ListMethods(NSString *className) {
    LoadLaunchServicesFrameworks();

    Class cls = NSClassFromString(className ?: @"");
    if (!cls) {
        fprintf(stderr, "class unavailable\n");
        return 1;
    }

    unsigned int instanceCount = 0;
    Method *instanceMethods = class_copyMethodList(cls, &instanceCount);
    for (unsigned int idx = 0; idx < instanceCount; idx++) {
        SEL selector = method_getName(instanceMethods[idx]);
        printf("- %s :: %s\n", sel_getName(selector), method_getTypeEncoding(instanceMethods[idx]) ?: "");
    }
    free(instanceMethods);

    unsigned int classCount = 0;
    Method *classMethods = class_copyMethodList(object_getClass(cls), &classCount);
    for (unsigned int idx = 0; idx < classCount; idx++) {
        SEL selector = method_getName(classMethods[idx]);
        printf("+ %s :: %s\n", sel_getName(selector), method_getTypeEncoding(classMethods[idx]) ?: "");
    }
    free(classMethods);
    return 0;
}

static int ListClasses(NSString *prefix) {
    LoadLaunchServicesFrameworks();

    int classCount = objc_getClassList(NULL, 0);
    if (classCount <= 0) {
        fprintf(stderr, "no classes available\n");
        return 1;
    }

    Class *classes = (__unsafe_unretained Class *)calloc((size_t)classCount, sizeof(Class));
    if (!classes) {
        fprintf(stderr, "allocation failed\n");
        return 1;
    }

    classCount = objc_getClassList(classes, classCount);
    NSMutableArray<NSString *> *matches = [NSMutableArray array];
    NSString *normalizedPrefix = prefix ?: @"";
    for (int idx = 0; idx < classCount; idx++) {
        const char *name = class_getName(classes[idx]);
        if (!name) {
            continue;
        }
        NSString *className = [NSString stringWithUTF8String:name];
        if (normalizedPrefix.length == 0 || [className hasPrefix:normalizedPrefix]) {
            [matches addObject:className];
        }
    }
    free(classes);

    [matches sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    for (NSString *className in matches) {
        printf("%s\n", className.UTF8String ?: "");
    }
    return 0;
}

static int ProbeURL(NSString *rawURL) {
    LoadLaunchServicesFrameworks();

    NSURL *url = [NSURL URLWithString:rawURL ?: @""];
    if (!url) {
        fprintf(stderr, "invalid url\n");
        return 1;
    }

    Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
    SEL defaultWorkspaceSelector = NSSelectorFromString(@"defaultWorkspace");
    if (!wsClass || ![wsClass respondsToSelector:defaultWorkspaceSelector]) {
        fprintf(stderr, "LSApplicationWorkspace unavailable\n");
        return 1;
    }

    id workspace = CallID0(wsClass, defaultWorkspaceSelector);
    if (!workspace) {
        fprintf(stderr, "defaultWorkspace unavailable\n");
        return 1;
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"url"] = rawURL ?: @"";

    SEL candidatesSelector = NSSelectorFromString(@"applicationsAvailableForOpeningURL:");
    if ([workspace respondsToSelector:candidatesSelector]) {
        id candidates = CallID1(workspace, candidatesSelector, url);
        NSMutableArray *bundleIDs = [NSMutableArray array];
        if ([candidates isKindOfClass:[NSArray class]]) {
            for (id proxy in (NSArray *)candidates) {
                NSString *bundleID = BundleIdentifierForProxy(proxy);
                [bundleIDs addObject:bundleID ?: [NSString stringWithFormat:@"%@", proxy] ?: @"<unknown>"];
            }
        }
        result[@"applicationsAvailableForOpeningURL"] = bundleIDs;
    }

    SEL availableSelector = NSSelectorFromString(@"isApplicationAvailableToOpenURL:error:");
    if ([workspace respondsToSelector:availableSelector]) {
        NSError *error = nil;
        BOOL available = CallBOOL2(workspace, availableSelector, url, &error);
        result[@"isApplicationAvailableToOpenURL"] = @(available);
        if (error.localizedDescription.length > 0) {
            result[@"isApplicationAvailableToOpenURLError"] = error.localizedDescription;
        }
    }

    SEL availableCommonSelector = NSSelectorFromString(@"isApplicationAvailableToOpenURLCommon:includePrivateURLSchemes:error:");
    if ([workspace respondsToSelector:availableCommonSelector]) {
        NSError *error = nil;
        BOOL available = CallBOOL3(workspace, availableCommonSelector, url, YES, &error);
        result[@"isApplicationAvailableToOpenURLCommon"] = @(available);
        if (error.localizedDescription.length > 0) {
            result[@"isApplicationAvailableToOpenURLCommonError"] = error.localizedDescription;
        }
    }

    SEL overrideSelector = NSSelectorFromString(@"URLOverrideForURL:");
    if ([workspace respondsToSelector:overrideSelector]) {
        id proxy = CallID1(workspace, overrideSelector, url);
        NSString *bundleID = BundleIdentifierForProxy(proxy);
        result[@"URLOverrideForURL"] = bundleID ?: [NSNull null];
    }

    SEL applicationSelector = NSSelectorFromString(@"applicationForOpeningResource:");
    if ([workspace respondsToSelector:applicationSelector]) {
        id proxy = CallID1(workspace, applicationSelector, url);
        NSString *bundleID = BundleIdentifierForProxy(proxy);
        result[@"applicationForOpeningResource"] = bundleID ?: [NSNull null];
    }

    NSData *json = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil];
    if (!json) {
        fprintf(stderr, "failed to serialize probe result\n");
        return 1;
    }

    printf("%s\n", [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String ?: "{}");
    return 0;
}

static int OpenURL(NSString *rawURL) {
    LoadLaunchServicesFrameworks();

    NSURL *url = [NSURL URLWithString:rawURL ?: @""];
    if (!url) {
        fprintf(stderr, "invalid url\n");
        return 1;
    }

    Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
    SEL defaultWorkspaceSelector = NSSelectorFromString(@"defaultWorkspace");
    if (!wsClass || ![wsClass respondsToSelector:defaultWorkspaceSelector]) {
        fprintf(stderr, "LSApplicationWorkspace unavailable\n");
        return 1;
    }

    id workspace = CallID0(wsClass, defaultWorkspaceSelector);
    if (!workspace) {
        fprintf(stderr, "defaultWorkspace unavailable\n");
        return 1;
    }

    SEL openSelector = NSSelectorFromString(@"openURL:withOptions:error:");
    if (![workspace respondsToSelector:openSelector]) {
        fprintf(stderr, "openURL:withOptions:error: unavailable\n");
        return 1;
    }

    NSError *error = nil;
    BOOL opened = CallBOOL4(workspace, openSelector, url, nil, &error);

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"url"] = rawURL ?: @"";
    result[@"opened"] = @(opened);
    if (error.localizedDescription.length > 0) {
        result[@"error"] = error.localizedDescription;
    }

    NSData *json = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil];
    if (!json) {
        fprintf(stderr, "failed to serialize open result\n");
        return 1;
    }

    printf("%s\n", [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String ?: "{}");
    return opened ? 0 : 1;
}

static int PerformOpenURL(NSString *requestedBundleID, NSString *rawURL) {
    LoadLaunchServicesFrameworks();

    NSURL *url = [NSURL URLWithString:rawURL ?: @""];
    if (!url) {
        fprintf(stderr, "invalid url\n");
        return 1;
    }
    if (requestedBundleID.length == 0) {
        fprintf(stderr, "invalid bundle id\n");
        return 1;
    }

    Class clientClass = NSClassFromString(@"_LSDOpenClient");
    if (!clientClass) {
        fprintf(stderr, "_LSDOpenClient unavailable\n");
        return 1;
    }

    id client = ((id (*)(id, SEL))objc_msgSend)((id)clientClass, @selector(new));
    if (!client) {
        fprintf(stderr, "_LSDOpenClient init failed\n");
        return 1;
    }

    SEL selector = NSSelectorFromString(@"performOpenOperationWithURL:bundleIdentifier:documentIdentifier:isContentManaged:sourceAuditToken:userInfo:options:delegate:completionHandler:");
    if (![client respondsToSelector:selector]) {
        fprintf(stderr, "performOpenOperationWithURL unavailable\n");
        return 1;
    }

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block BOOL completionCalled = NO;
    __block BOOL opened = NO;
    __block NSString *errorMessage = nil;

    void (^completion)(BOOL, NSError *) = ^(BOOL didOpen, NSError *error) {
        completionCalled = YES;
        opened = didOpen;
        errorMessage = error.localizedDescription;
        dispatch_semaphore_signal(semaphore);
    };

    ((void (*)(id, SEL, NSURL *, NSString *, id, BOOL, const void *, id, id, id, id))objc_msgSend)(client,
                                                                                                      selector,
                                                                                                      url,
                                                                                                      requestedBundleID,
                                                                                                      nil,
                                                                                                      NO,
                                                                                                      NULL,
                                                                                                      nil,
                                                                                                      nil,
                                                                                                      nil,
                                                                                                      completion);

    BOOL timedOut = dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) != 0;

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"url"] = rawURL ?: @"";
    result[@"requestedBundleID"] = requestedBundleID ?: @"";
    result[@"completionCalled"] = @(completionCalled);
    result[@"timedOut"] = @(timedOut);
    if (completionCalled) {
        result[@"opened"] = @(opened);
    }
    if (errorMessage.length > 0) {
        result[@"error"] = errorMessage;
    }

    NSData *json = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil];
    if (!json) {
        fprintf(stderr, "failed to serialize perform-open result\n");
        return 1;
    }

    printf("%s\n", [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String ?: "{}");
    return (!timedOut && completionCalled && opened) ? 0 : 1;
}

static int TraceURL(NSString *rawURL) {
    LoadLaunchServicesFrameworks();
    InstallObjectiveCMethodTraces();

    NSURL *url = [NSURL URLWithString:rawURL ?: @""];
    if (!url) {
        fprintf(stderr, "invalid url\n");
        return 1;
    }

    Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
    SEL defaultWorkspaceSelector = NSSelectorFromString(@"defaultWorkspace");
    if (!wsClass || ![wsClass respondsToSelector:defaultWorkspaceSelector]) {
        fprintf(stderr, "LSApplicationWorkspace unavailable\n");
        return 1;
    }

    id workspace = CallID0(wsClass, defaultWorkspaceSelector);
    if (!workspace) {
        fprintf(stderr, "defaultWorkspace unavailable\n");
        return 1;
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"url"] = rawURL ?: @"";

    SEL candidatesSelector = NSSelectorFromString(@"applicationsAvailableForOpeningURL:");
    if ([workspace respondsToSelector:candidatesSelector]) {
        TraceBegin(@"applicationsAvailableForOpeningURL:");
        id candidates = CallID1(workspace, candidatesSelector, url);
        NSArray *events = TraceEnd();
        NSMutableArray *bundleIDs = [NSMutableArray array];
        if ([candidates isKindOfClass:[NSArray class]]) {
            for (id proxy in (NSArray *)candidates) {
                NSString *bundleID = BundleIdentifierForProxy(proxy);
                [bundleIDs addObject:bundleID ?: [NSString stringWithFormat:@"%@", proxy] ?: @"<unknown>"];
            }
        }
        result[@"applicationsAvailableForOpeningURL"] = @{
            @"result": bundleIDs,
            @"xpcEvents": events,
            @"xpcEventCount": @(events.count)
        };
    }

    SEL overrideSelector = NSSelectorFromString(@"URLOverrideForURL:");
    if ([workspace respondsToSelector:overrideSelector]) {
        TraceBegin(@"URLOverrideForURL:");
        id proxy = CallID1(workspace, overrideSelector, url);
        NSArray *events = TraceEnd();
        NSString *bundleID = BundleIdentifierForProxy(proxy);
        result[@"URLOverrideForURL"] = @{
            @"result": bundleID ?: [NSNull null],
            @"xpcEvents": events,
            @"xpcEventCount": @(events.count)
        };
    }

    SEL applicationSelector = NSSelectorFromString(@"applicationForOpeningResource:");
    if ([workspace respondsToSelector:applicationSelector]) {
        TraceBegin(@"applicationForOpeningResource:");
        id proxy = CallID1(workspace, applicationSelector, url);
        NSArray *events = TraceEnd();
        NSString *bundleID = BundleIdentifierForProxy(proxy);
        result[@"applicationForOpeningResource"] = @{
            @"result": bundleID ?: [NSNull null],
            @"xpcEvents": events,
            @"xpcEventCount": @(events.count)
        };
    }

    SEL availableSelector = NSSelectorFromString(@"isApplicationAvailableToOpenURL:error:");
    if ([workspace respondsToSelector:availableSelector]) {
        NSError *error = nil;
        TraceBegin(@"isApplicationAvailableToOpenURL:error:");
        BOOL available = CallBOOL2(workspace, availableSelector, url, &error);
        NSArray *events = TraceEnd();
        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        entry[@"result"] = @(available);
        entry[@"xpcEvents"] = events;
        entry[@"xpcEventCount"] = @(events.count);
        if (error.localizedDescription.length > 0) {
            entry[@"error"] = error.localizedDescription;
        }
        result[@"isApplicationAvailableToOpenURL"] = entry;
    }

    SEL openSelector = NSSelectorFromString(@"openURL:withOptions:error:");
    if ([workspace respondsToSelector:openSelector]) {
        NSError *error = nil;
        TraceBegin(@"openURL:withOptions:error:");
        BOOL opened = CallBOOL4(workspace, openSelector, url, nil, &error);
        NSArray *events = TraceEnd();
        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        entry[@"result"] = @(opened);
        entry[@"xpcEvents"] = events;
        entry[@"xpcEventCount"] = @(events.count);
        if (error.localizedDescription.length > 0) {
            entry[@"error"] = error.localizedDescription;
        }
        result[@"openURL:withOptions:error:"] = entry;
    }

    NSData *json = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil];
    if (!json) {
        fprintf(stderr, "failed to serialize trace result\n");
        return 1;
    }

    printf("%s\n", [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String ?: "{}");
    return 0;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            PrintUsage();
            return 1;
        }

        NSString *cmd = [NSString stringWithUTF8String:argv[1] ?: ""];
        if (DSDropElevatedPrivilegesUnlessNeeded(cmd) != 0) {
            return 1;
        }

        if ([cmd isEqualToString:@"list"]) {
            NSDictionary *cfg = [DSRoutingConfig loadConfig];
            NSData *json = [NSJSONSerialization dataWithJSONObject:cfg options:NSJSONWritingPrettyPrinted error:nil];
            if (json) {
                printf("%s\n", [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String ?: "{}");
            } else {
                printf("{}\n");
            }
            return 0;
        }

        if ([cmd isEqualToString:@"sync-route-config-mirror"]) {
            return SyncRouteConfigMirrorCommand();
        }

        if ([cmd isEqualToString:@"set-scheme"] && argc == 4) {
            NSString *scheme = [[NSString stringWithUTF8String:argv[2]] lowercaseString];
            NSString *bundleID = [NSString stringWithUTF8String:argv[3]];
            NSMutableDictionary *cfg = MutableConfig();
            NSMutableDictionary *schemes = EnsureMutableMap(cfg, @"schemes");
            schemes[scheme] = bundleID;
            return SaveOrPrint(cfg);
        }

        if ([cmd isEqualToString:@"set-host"] && argc == 4) {
            NSString *host = [[NSString stringWithUTF8String:argv[2]] lowercaseString];
            NSString *bundleID = [NSString stringWithUTF8String:argv[3]];
            NSMutableDictionary *cfg = MutableConfig();
            NSMutableDictionary *hosts = EnsureMutableMap(cfg, @"hosts");
            hosts[host] = bundleID;
            return SaveOrPrint(cfg);
        }

        if ([cmd isEqualToString:@"set-link"] && argc == 5) {
            NSString *host = [NSString stringWithUTF8String:argv[2]];
            NSString *pathMatcher = [NSString stringWithUTF8String:argv[3]];
            NSString *bundleID = [NSString stringWithUTF8String:argv[4]];
            NSDictionary *rule = [DSRoutingConfig normalizedLinkRuleWithHost:host pathMatcher:pathMatcher bundleID:bundleID sourceHint:nil];
            if (!rule) {
                fprintf(stderr, "invalid link rule\n");
                return 1;
            }
            NSMutableDictionary *cfg = MutableConfig();
            NSMutableArray *links = EnsureMutableArray(cfg, kDSRoutingLinksKey);
            RemoveMatchingLinkRules(links, rule);
            [links addObject:rule];
            return SaveOrPrint(cfg);
        }

        if ([cmd isEqualToString:@"set-link-rich"] && argc == 7) {
            NSString *ruleID = [NSString stringWithUTF8String:argv[2]];
            NSString *host = [NSString stringWithUTF8String:argv[3]];
            NSString *pathMatcher = [NSString stringWithUTF8String:argv[4]];
            if ([pathMatcher isEqualToString:@"-"]) {
                pathMatcher = nil;
            }
            NSString *queryMatcher = [NSString stringWithUTF8String:argv[5]];
            if ([queryMatcher isEqualToString:@"-"]) {
                queryMatcher = nil;
            }
            NSString *bundleID = [NSString stringWithUTF8String:argv[6]];
            NSDictionary *rule = [DSRoutingConfig normalizedLinkRuleWithRuleID:ruleID
                                                                          host:host
                                                                   pathMatcher:pathMatcher
                                                                  queryMatcher:queryMatcher
                                                                      bundleID:bundleID
                                                                  hostWildcard:NO
                                                                    sourceHint:@"configured"];
            if (!rule) {
                fprintf(stderr, "invalid rich link rule\n");
                return 1;
            }
            NSMutableDictionary *cfg = MutableConfig();
            NSMutableArray *links = EnsureMutableArray(cfg, kDSRoutingLinksKey);
            RemoveMatchingLinkRules(links, rule);
            [links addObject:rule];
            return SaveOrPrint(cfg);
        }

        if ([cmd isEqualToString:@"del-scheme"] && argc == 3) {
            NSString *scheme = [[NSString stringWithUTF8String:argv[2]] lowercaseString];
            NSMutableDictionary *cfg = MutableConfig();
            NSMutableDictionary *schemes = EnsureMutableMap(cfg, @"schemes");
            [schemes removeObjectForKey:scheme];
            return SaveOrPrint(cfg);
        }

        if ([cmd isEqualToString:@"del-host"] && argc == 3) {
            NSString *host = [[NSString stringWithUTF8String:argv[2]] lowercaseString];
            NSMutableDictionary *cfg = MutableConfig();
            NSMutableDictionary *hosts = EnsureMutableMap(cfg, @"hosts");
            [hosts removeObjectForKey:host];
            return SaveOrPrint(cfg);
        }

        if ([cmd isEqualToString:@"del-link"] && argc == 4) {
            NSString *host = [NSString stringWithUTF8String:argv[2]];
            NSString *pathMatcher = [NSString stringWithUTF8String:argv[3]];
            NSDictionary *identity = [DSRoutingConfig normalizedLinkRuleWithHost:host pathMatcher:pathMatcher bundleID:kDSNoAppBundleSentinel sourceHint:nil];
            if (!identity) {
                fprintf(stderr, "invalid link rule\n");
                return 1;
            }
            NSMutableDictionary *cfg = MutableConfig();
            NSMutableArray *links = EnsureMutableArray(cfg, kDSRoutingLinksKey);
            RemoveMatchingLinkRules(links, identity);
            return SaveOrPrint(cfg);
        }

        if ([cmd isEqualToString:@"del-link-rich"] && argc == 6) {
            NSString *ruleID = [NSString stringWithUTF8String:argv[2]];
            NSString *host = [NSString stringWithUTF8String:argv[3]];
            NSString *pathMatcher = [NSString stringWithUTF8String:argv[4]];
            if ([pathMatcher isEqualToString:@"-"]) {
                pathMatcher = nil;
            }
            NSString *queryMatcher = [NSString stringWithUTF8String:argv[5]];
            if ([queryMatcher isEqualToString:@"-"]) {
                queryMatcher = nil;
            }
            NSDictionary *identity = [DSRoutingConfig normalizedLinkRuleWithRuleID:ruleID
                                                                              host:host
                                                                       pathMatcher:pathMatcher
                                                                      queryMatcher:queryMatcher
                                                                          bundleID:kDSNoAppBundleSentinel
                                                                      hostWildcard:NO
                                                                        sourceHint:nil];
            if (!identity) {
                fprintf(stderr, "invalid rich link rule\n");
                return 1;
            }
            NSMutableDictionary *cfg = MutableConfig();
            NSMutableArray *links = EnsureMutableArray(cfg, kDSRoutingLinksKey);
            RemoveMatchingLinkRules(links, identity);
            return SaveOrPrint(cfg);
        }

        if ([cmd isEqualToString:@"probe-url"] && argc == 3) {
            return ProbeURL([NSString stringWithUTF8String:argv[2]]);
        }

        if ([cmd isEqualToString:@"open-url"] && argc == 3) {
            return OpenURL([NSString stringWithUTF8String:argv[2]]);
        }

        if ([cmd isEqualToString:@"perform-open-url"] && argc == 4) {
            return PerformOpenURL([NSString stringWithUTF8String:argv[2]], [NSString stringWithUTF8String:argv[3]]);
        }

        if ([cmd isEqualToString:@"trace-url"] && argc == 3) {
            return TraceURL([NSString stringWithUTF8String:argv[2]]);
        }

        if ([cmd isEqualToString:@"inspect-applink"] && argc == 3) {
            return InspectAppLink([NSString stringWithUTF8String:argv[2]]);
        }

        if ([cmd isEqualToString:@"inspect-swc"] && argc == 3) {
            return InspectSWC([NSString stringWithUTF8String:argv[2]]);
        }

        if ([cmd isEqualToString:@"inspect-method"] && argc == 4) {
            return InspectMethod([NSString stringWithUTF8String:argv[2]], [NSString stringWithUTF8String:argv[3]]);
        }

        if ([cmd isEqualToString:@"list-methods"] && argc == 3) {
            return ListMethods([NSString stringWithUTF8String:argv[2]]);
        }

        if ([cmd isEqualToString:@"list-classes"] && argc == 3) {
            return ListClasses([NSString stringWithUTF8String:argv[2]]);
        }

        PrintUsage();
        return 1;
    }
}
