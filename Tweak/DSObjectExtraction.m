#import "DSObjectExtraction.h"
#import "DSRouteSupport.h"
#import <objc/message.h>
#import <objc/runtime.h>

NSArray *DSCollectionObjects(id object) {
    if ([object isKindOfClass:NSArray.class]) return object;
    if ([object isKindOfClass:NSSet.class]) return [(NSSet *)object allObjects];
    if ([object isKindOfClass:NSOrderedSet.class]) return [(NSOrderedSet *)object array];
    return nil;
}

NSString *DSTrimmedDescription(id object) {
    if (!object) return @"<nil>";
    NSString *value = [NSString stringWithFormat:@"<%@ %@>", NSStringFromClass([object class]), object];
    if (value.length <= 320) return value;
    return [[value substringToIndex:320] stringByAppendingString:@"..."];
}

NSURL *DSLaunchServicesURLFromObjectInternal(id object, NSUInteger depth);
NSString *DSLaunchServicesSchemeFromObjectInternal(id object, NSUInteger depth);

NSURL *DSLaunchServicesURLFromObjectInternal(id object, NSUInteger depth) {
    if (!object || depth > 2) return nil;

    NSURL *url = DSURLFromContext(object);
    if (url) return url;

    url = DSURLFromDictionaryLikeObject(object);
    if (url) return url;

    NSArray *objects = DSCollectionObjects(object);
    if (objects.count > 0) {
        NSUInteger limit = MIN((NSUInteger)3, objects.count);
        for (NSUInteger idx = 0; idx < limit; idx++) {
            url = DSLaunchServicesURLFromObjectInternal(objects[idx], depth + 1);
            if (url) return url;
        }
    }

    for (NSString *key in @[@"query", @"queries", @"URL", @"url", @"_URL", @"_url", @"resource", @"resourceURL", @"targetURL", @"openConfiguration", @"configuration"]) {
        id value = DSSafeValueForKey(object, key);
        url = DSLaunchServicesURLFromObjectInternal(value, depth + 1);
        if (url) return url;
    }

    return nil;
}

NSString *DSLaunchServicesSchemeFromObjectInternal(id object, NSUInteger depth) {
    NSURL *url = DSLaunchServicesURLFromObjectInternal(object, depth);
    if (url.scheme.length > 0) return url.scheme.lowercaseString;
    if (!object || depth > 2) return nil;

    if ([object isKindOfClass:NSString.class]) {
        NSString *scheme = [(NSString *)object lowercaseString];
        return scheme.length > 0 ? scheme : nil;
    }

    NSArray *objects = DSCollectionObjects(object);
    if (objects.count > 0) {
        NSUInteger limit = MIN((NSUInteger)3, objects.count);
        for (NSUInteger idx = 0; idx < limit; idx++) {
            NSString *scheme = DSLaunchServicesSchemeFromObjectInternal(objects[idx], depth + 1);
            if (scheme.length > 0) return scheme;
        }
    }

    for (NSString *key in @[@"scheme", @"URLScheme", @"_scheme"]) {
        id value = DSSafeValueForKey(object, key);
        if ([value isKindOfClass:NSString.class] && [value length] > 0) {
            return [value lowercaseString];
        }
    }

    return nil;
}

NSURL *DSLaunchServicesURLFromObject(id object) {
    return DSLaunchServicesURLFromObjectInternal(object, 0);
}

NSString *DSLaunchServicesSchemeFromObject(id object) {
    return DSLaunchServicesSchemeFromObjectInternal(object, 0);
}

NSString *DSConfiguredBundleIDForLaunchServicesObject(id object) {
    NSURL *url = DSLaunchServicesURLFromObject(object);
    if (url) return DSConfiguredBundleIDForURL(url);

    NSString *scheme = DSLaunchServicesSchemeFromObject(object);
    if (scheme.length > 0) return DSConfiguredBundleIDForScheme(scheme);

    return nil;
}

NSURL *DSURLFromContext(id context) {
    if (!context) return nil;
    if ([context isKindOfClass:NSURL.class]) return context;
    if ([context isKindOfClass:NSString.class]) {
        NSURL *url = [NSURL URLWithString:(NSString *)context];
        if (url.scheme.length > 0) return url;
    }
    @try {
        if ([context respondsToSelector:@selector(URL)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id value = [context performSelector:@selector(URL)];
#pragma clang diagnostic pop
            if ([value isKindOfClass:NSURL.class]) return value;
        }
        if ([context respondsToSelector:@selector(url)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id value = [context performSelector:@selector(url)];
#pragma clang diagnostic pop
            if ([value isKindOfClass:NSURL.class]) return value;
        }
    } @catch (__unused NSException *exception) {}
    return nil;
}

id DSSafeValueForKey(id object, NSString *key) {
    if (!object || key.length == 0) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

NSURL *DSURLFromDictionaryLikeObject(id object) {
    if (![object isKindOfClass:[NSDictionary class]]) return nil;
    NSDictionary *dict = (NSDictionary *)object;
    for (NSString *key in @[@"url", @"URL", @"_url", @"_URL", @"resourceURL", @"requestURL", @"targetURL"]) {
        id value = dict[key];
        if ([value isKindOfClass:NSURL.class]) return value;
        if ([value isKindOfClass:NSString.class]) {
            NSURL *url = [NSURL URLWithString:(NSString *)value];
            if (url.scheme.length > 0) return url;
        }
        NSURL *nestedURL = DSURLFromContext(value);
        if (nestedURL) return nestedURL;
    }
    return nil;
}

NSURL *DSExtractURLFromOpenApplicationRequest(id request, id options, id origin) {
    NSURL *url = DSURLFromContext(request);
    if (url) return url;

    url = DSURLFromDictionaryLikeObject(request);
    if (url) return url;

    for (NSString *key in @[@"applicationContext", @"context", @"payload", @"request", @"openRequest", @"item", @"userInfo", @"configuration", @"openConfiguration", @"resource", @"resourceURL", @"targetURL", @"URL", @"url"]) {
        id value = DSSafeValueForKey(request, key);
        url = DSURLFromContext(value);
        if (url) return url;
        url = DSURLFromDictionaryLikeObject(value);
        if (url) return url;
    }

    url = DSURLFromContext(options);
    if (url) return url;
    url = DSURLFromDictionaryLikeObject(options);
    if (url) return url;

    url = DSURLFromContext(origin);
    if (url) return url;
    url = DSURLFromDictionaryLikeObject(origin);
    if (url) return url;

    return nil;
}

// Try multiple ways to get URL from an LSAppLink object
NSURL *DSExtractURLFromAppLink(id appLink) {
    if (!appLink) return nil;

    SEL urlSel = @selector(URL);
    if ([appLink respondsToSelector:urlSel]) {
        NSURL *url = ((NSURL *(*)(id, SEL))objc_msgSend)(appLink, urlSel);
        if ([url isKindOfClass:NSURL.class]) return url;
    }

    Ivar ivar = class_getInstanceVariable([appLink class], "_URL");
    if (ivar) {
        id url = object_getIvar(appLink, ivar);
        if ([url isKindOfClass:NSURL.class]) return url;
    }

    ivar = class_getInstanceVariable([appLink class], "_url");
    if (ivar) {
        id url = object_getIvar(appLink, ivar);
        if ([url isKindOfClass:NSURL.class]) return url;
    }

    @try {
        id url = [appLink valueForKey:@"URL"];
        if ([url isKindOfClass:NSURL.class]) return url;
    } @catch (__unused NSException *e) {}
    @try {
        id url = [appLink valueForKey:@"url"];
        if ([url isKindOfClass:NSURL.class]) return url;
    } @catch (__unused NSException *e) {}

    return nil;
}
