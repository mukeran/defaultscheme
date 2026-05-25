#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, DSRuleSection) {
    DSRuleSectionSchemes = 0,
    DSRuleSectionHosts = 1,
};

FOUNDATION_EXPORT NSString * _Nonnull const kDSTestHistoryDefaultsKey;

@interface DSAppOption : NSObject
@property (nonatomic, copy) NSString * _Nullable bundleID;
@property (nonatomic, copy) NSString * _Nullable displayName;
@property (nonatomic, copy) NSString * _Nullable bundlePath;
@property (nonatomic, copy) NSString * _Nullable executableName;
@end

@interface DSRuleItem : NSObject
@property (nonatomic, copy) NSString * _Nullable key;
@property (nonatomic, copy) NSString * _Nullable ruleHost;
@property (nonatomic, copy) NSString * _Nullable pathMatcher;
@property (nonatomic, copy) NSString * _Nullable queryMatcher;
@property (nonatomic, copy) NSString * _Nullable ruleID;
@property (nonatomic, copy) NSString * _Nullable associatedBundleID;
@property (nonatomic, copy) NSString * _Nullable patternKind;
@property (nonatomic, copy) NSString * _Nullable sourceHint;
@property (nonatomic, assign) BOOL usesLinkRules;
@property (nonatomic, assign) BOOL hostWildcard;
@property (nonatomic, assign) BOOL stale;
@property (nonatomic, assign) DSRuleSection section;
@property (nonatomic, strong) NSArray<DSAppOption *> * _Nullable candidates;
@property (nonatomic, copy) NSString * _Nullable configuredBundleID;
@property (nonatomic, strong) NSArray<DSRuleItem *> * _Nullable childItems;
@property (nonatomic, strong) DSRuleItem * _Nullable domainDefaultItem;
@property (nonatomic, assign) BOOL domainGroup;
@property (nonatomic, strong) NSArray<DSRuleItem *> * _Nullable representedItems;
@end

@interface DSAppFilterItem : NSObject
@property (nonatomic, copy) NSString * _Nullable bundleID;
@property (nonatomic, copy) NSString * _Nullable displayName;
@property (nonatomic, assign) NSUInteger schemeCount;
@property (nonatomic, assign) NSUInteger hostCount;
@end

typedef void (^DSAppPickerSelectionHandler)(NSString * _Nullable bundleIDOrNil);
typedef void (^DSRuleItemHandler)(DSRuleItem * _Nonnull item);
typedef NSString * _Nullable (^DSRuleItemSubtitleProvider)(DSRuleItem * _Nonnull item);
typedef void (^DSAppFilterSelectionHandler)(DSAppFilterItem * _Nullable itemOrNil);
typedef void (^DSTestHistorySelectionHandler)(NSString * _Nonnull urlString);
