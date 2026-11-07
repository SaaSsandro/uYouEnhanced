#import <YouTubeHeader/YTIIcon.h>
#import <YouTubeHeader/YTSettingsGroupData.h>
#import <YouTubeHeader/YTSettingsSectionController.h>
#import <YouTubeHeader/YTSettingsSectionItem.h>
#import <PSHeader/Misc.h>

#define LOC(x) [tweakBundle localizedStringForKey:x value:nil table:nil]

@interface YTSettingsGroupData (YouGroupSettings)
+ (NSMutableArray <NSNumber *> *)tweaks;
@end

// -[YTSettingsSectionController initWithTitle:items:] is what builds the section
// out of the group's items; the header does not declare it.
@interface YTSettingsSectionController (YouGroupSettings)
- (instancetype)initWithTitle:(NSString *)title items:(NSArray *)items;
@end

// Not in the header either, but -[YTSettingsViewController
// createItemFromSectionController:categoryId:] sets it on every item.
@interface YTSettingsSectionItem (YouGroupSettings)
- (NSInteger)categoryId;
@end

static const NSInteger TweakGroup = 'psyt';
static const NSInteger YTIcons = 'ytic';
static const NSInteger YouChooseQuality = 'ycql';
static const NSInteger YTUHD = 'ythd';
static const NSInteger YouSlider = 'ytsl';
static const NSInteger YTweaks = 'ytwk';
static const NSInteger YTFlags = 'ytfl';
static const NSInteger VolumeBoostYT = 'ndyt';
static const NSInteger YouMod = 'ytmo';
static const NSInteger FLEXHelperForYT = 'fhyt';

// YTPlus (YTLite) does not publish its settings category constant, so the tweak
// picks it up from the section YTPlus registers and moves it to the head of the
// group. This is the title that section carries.
static NSString *const YTPlusSectionTitle = @"YouTube Plus";

// ---------------------------------------------------------------------------
// TEMPORARY diagnostic - set to 0 (or delete this block and the #if blocks
// below) once the section order is understood.
//
//   * every grouped section title gets its index in +tweaks prepended, so the
//     on-device order can be compared with the order the tweak asks for
//   * the group header lists which hooks actually fired, which tells us which
//     of the settings code paths are live
// ---------------------------------------------------------------------------
#define YGS_DEBUG_ORDER 1

#if YGS_DEBUG_ORDER
static BOOL ygsSawOrderedGroups = NO;
static BOOL ygsSawTitle = NO;
static BOOL ygsSawOrderedCategories = NO;
static BOOL ygsSawOrderedCategoriesForType = NO;
static BOOL ygsSawSettingsCategoryOrder = NO;
static BOOL ygsSawEnumerate = NO;
static BOOL ygsSawOrganize = NO;
static BOOL ygsSawSetSectionControllers = NO;
static BOOL ygsSawSectionInit = NO;
static BOOL ygsSawItems = NO;
static NSString *ygsItemOrder = nil;

static NSString *YGSHookFlags(void) {
    NSMutableArray <NSString *> *flags = [NSMutableArray array];
    if (ygsSawOrderedGroups) [flags addObject:@"og"];
    if (ygsSawTitle) [flags addObject:@"t"];
    if (ygsSawOrderedCategories) [flags addObject:@"oc"];
    if (ygsSawOrderedCategoriesForType) [flags addObject:@"oct"];
    if (ygsSawSettingsCategoryOrder) [flags addObject:@"sco"];
    if (ygsSawEnumerate) [flags addObject:@"en"];
    if (ygsSawOrganize) [flags addObject:@"gz"];
    if (ygsSawSetSectionControllers) [flags addObject:@"ssc"];
    if (ygsSawSectionInit) [flags addObject:@"si"];
    if (ygsSawItems) [flags addObject:@"it"];
    return [flags componentsJoinedByString:@","];
}
#endif

/// Order of a group's items, expressed as their positions in +tweaks. Items
/// whose category is unknown keep their relative position at the end.
static NSArray *YGSOrderItems(NSArray *items) {
    NSArray <NSNumber *> *order = [%c(YTSettingsGroupData) tweaks];
    return [items sortedArrayUsingComparator:^NSComparisonResult(id lhs, id rhs) {
        NSInteger left = NSNotFound;
        NSInteger right = NSNotFound;
        if ([lhs respondsToSelector:@selector(categoryId)]) left = [order indexOfObject:@([lhs categoryId])];
        if ([rhs respondsToSelector:@selector(categoryId)]) right = [order indexOfObject:@([rhs categoryId])];
        if (left == right) return NSOrderedSame;
        if (left == NSNotFound) return NSOrderedDescending;
        if (right == NSNotFound) return NSOrderedAscending;
        return left < right ? NSOrderedAscending : NSOrderedDescending;
    }];
}

/// True when this section holds our group's items.
static BOOL YGSIsTweakSection(NSArray *items) {
    NSArray <NSNumber *> *order = [%c(YTSettingsGroupData) tweaks];
    for (id item in items) {
        if ([item respondsToSelector:@selector(categoryId)] && [order containsObject:@([item categoryId])]) {
            return YES;
        }
    }
    return NO;
}

#if YGS_DEBUG_ORDER
static NSString *YGSItemOrderDescription(NSArray *items) {
    NSArray <NSNumber *> *order = [%c(YTSettingsGroupData) tweaks];
    NSMutableArray <NSString *> *parts = [NSMutableArray array];
    for (id item in items) {
        NSInteger index = NSNotFound;
        if ([item respondsToSelector:@selector(categoryId)]) index = [order indexOfObject:@([item categoryId])];
        [parts addObject:index == NSNotFound ? @"?" : [NSString stringWithFormat:@"%ld", (long)index]];
    }
    return [parts componentsJoinedByString:@","];
}
#endif

/// Shared handling for both setSectionItems: variants: adopt YTPlus' category
/// and (in the diagnostic build) prefix the title with its position.
static NSString *YGSNoteSection(NSInteger category, NSString *title) {
    NSMutableArray <NSNumber *> *tweaks = [%c(YTSettingsGroupData) tweaks];

    // YTPlus has no public category constant, so adopt the category of the
    // section it registers. It is inserted at index 0 to stay the first entry.
    if (title.length && [title rangeOfString:YTPlusSectionTitle options:NSCaseInsensitiveSearch].location != NSNotFound
        && ![tweaks containsObject:@(category)]) {
        [tweaks insertObject:@(category) atIndex:0];
    }

#if YGS_DEBUG_ORDER
    NSInteger index = [tweaks indexOfObject:@(category)];
    if (index != NSNotFound) {
        return [NSString stringWithFormat:@"%ld · %@", (long)index, title];
    }
#endif
    return title;
}

NSBundle *TweakBundle() {
    static NSBundle *bundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *tweakBundlePath = [[NSBundle mainBundle] pathForResource:@"YouGroupSettings" ofType:@"bundle"];
        bundle = [NSBundle bundleWithPath:tweakBundlePath ?: PS_ROOT_PATH_NS(@"/Library/Application Support/YouGroupSettings.bundle")];
    });
    return bundle;
}

// The group header used to come out empty: the string lives in the settings
// bundle, which has no .lproj for most device languages. Fall back to the name.
static NSString *TweakGroupTitle() {
    NSBundle *tweakBundle = TweakBundle();
    NSString *title = LOC(@"TWEAKS");
    if (!title.length) title = @"Tweaks";
#if YGS_DEBUG_ORDER
    title = [title stringByAppendingFormat:@" ⟨%@⟩", YGSHookFlags()];
    if (ygsItemOrder.length) {
        title = [title stringByAppendingFormat:@" #%@", ygsItemOrder];
    }
#endif
    return title;
}

%hook YTAppSettingsGroupPresentationData

+ (NSArray <YTSettingsGroupData *> *)orderedGroups {
#if YGS_DEBUG_ORDER
    ygsSawOrderedGroups = YES;
#endif
    NSArray <YTSettingsGroupData *> *groups = %orig;
    NSMutableArray <YTSettingsGroupData *> *mutableGroups = [groups mutableCopy];
    YTSettingsGroupData *tweakGroup = [[%c(YTSettingsGroupData) alloc] initWithGroupType:TweakGroup];
    [mutableGroups insertObject:tweakGroup atIndex:0];
    return mutableGroups;
}

%end

%hook YTAppSettingsPresentationData

// The settings screen does not lay the sections out in the group's
// orderedCategories: -[YTSettingsViewController
// enumerateSectionControllersWithBlock:] walks this global order instead, which
// is why sorting the group's array never changed anything. Move the tweak
// categories to the front - YTPlus first, the rest in the order
// +[YTSettingsGroupData tweaks] defines - and leave YouTube's own order intact.
+ (NSArray <NSNumber *> *)settingsCategoryOrder {
#if YGS_DEBUG_ORDER
    ygsSawSettingsCategoryOrder = YES;
#endif
    NSArray <NSNumber *> *order = %orig;
    NSMutableArray <NSNumber *> *result = [NSMutableArray arrayWithCapacity:order.count];

    for (NSNumber *category in [%c(YTSettingsGroupData) tweaks]) {
        if ([order containsObject:category] && ![result containsObject:category]) {
            [result addObject:category];
        }
    }
    for (NSNumber *category in order) {
        if (![result containsObject:category]) {
            [result addObject:category];
        }
    }
    return result;
}

%end

%hook YTSettingsGroupData

%new(@@:)
+ (NSMutableArray <NSNumber *> *)tweaks {
    static NSMutableArray <NSNumber *> *tweaks = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Order: YTPlus first (inserted by the section hook below when it is
        // installed), then every other supported tweak alphabetically by name.
        tweaks = [NSMutableArray new];
        [tweaks addObjectsFromArray:@[
            @(517), // DontEatMyContent
            @(FLEXHelperForYT), // FLEXing
            @(2002), // Gonerino
            @(1080), // Return YouTube Dislike
            @(VolumeBoostYT), // VolumeBoostYT
            @(YouChooseQuality), // YouChooseQuality
            @(YouMod), // YouMod
            @(200), // YouPiP
            @(YouSlider), // YouSlider
            @(404), // YTABConfig
            @(YTFlags), // YTFlags
            @(2168), // YTHoldForSpeed
            @(YTIcons), // YTIcons
            @(YTUHD), // YTUHD
            @(1222), // YTVideoOverlay
            @(YTweaks), // YTweaks
        ]];
    });
    return tweaks;
}

- (NSString *)title {
#if YGS_DEBUG_ORDER
    ygsSawTitle = YES;
#endif
    if (self.type == TweakGroup)
        return TweakGroupTitle();
    return %orig;
}

- (NSArray <NSNumber *> *)orderedCategories {
#if YGS_DEBUG_ORDER
    ygsSawOrderedCategories = YES;
#endif
    if (self.type == TweakGroup)
        return [[self class] tweaks];
    return %orig;
}

// YTSettingsGroupData declares both the properties above and these per-type
// methods; it is not documented which pair the settings screen reads, so both
// are hooked. Without the property hooks the header stayed empty and the
// sections kept YouTube's own order even though the array was sorted.
- (NSString *)titleForSettingGroupType:(NSUInteger)type {
    if (type == TweakGroup)
        return TweakGroupTitle();
    return %orig;
}

- (NSArray <NSNumber *> *)orderedCategoriesForGroupType:(NSUInteger)type {
#if YGS_DEBUG_ORDER
    ygsSawOrderedCategoriesForType = YES;
#endif
    if (type == TweakGroup)
        return [[self class] tweaks];
    return %orig;
}

%end

%hook YTSettingsSectionController

// Sorting the group's categories had no visible effect, and the group's items
// already arrive in category order, so the section must be the last place the
// order can be set. Our group is the one whose title we return from
// YTSettingsGroupData; reorder its items by their position in +tweaks.
- (instancetype)initWithTitle:(NSString *)title items:(NSArray *)items {
#if YGS_DEBUG_ORDER
    ygsSawSectionInit = YES;
#endif
    if ([title hasPrefix:@"Tweaks"] && items.count > 1) {
        items = YGSOrderItems(items);
    }
    return %orig;
}

// The section exposes its rows through this getter, so this is the last point
// that can decide what the settings screen shows. Record the order YouTube asks
// for (diagnostic) and hand back the sorted one.
- (NSArray <YTSettingsSectionItem *> *)items {
    NSArray <YTSettingsSectionItem *> *items = %orig;
    if (items.count > 1 && YGSIsTweakSection(items)) {
#if YGS_DEBUG_ORDER
        ygsSawItems = YES;
        ygsItemOrder = YGSItemOrderDescription(items);
#endif
        items = YGSOrderItems(items);
    }
    return items;
}

%end

%hook YTSettingsViewController

- (void)setSectionItems:(NSMutableArray *)sectionItems forCategory:(NSInteger)category title:(NSString *)title icon:(YTIIcon *)icon titleDescription:(NSString *)titleDescription headerHidden:(BOOL)headerHidden {
    title = YGSNoteSection(category, title);

    if (icon == nil && [[%c(YTSettingsGroupData) tweaks] containsObject:@(category)]) {
        icon = [%c(YTIIcon) new];
        icon.iconType = YT_SETTINGS;
    }
    %orig;
}

// The 5-argument variant (no icon) is what e.g. Gonerino registers through; the
// tweak used to ignore it, so those sections never got an index or a gear icon.
- (void)setSectionItems:(NSMutableArray *)sectionItems forCategory:(NSInteger)category title:(NSString *)title titleDescription:(NSString *)titleDescription headerHidden:(BOOL)headerHidden {
    title = YGSNoteSection(category, title);
    %orig;
}

#if YGS_DEBUG_ORDER

- (void)enumerateSectionControllersWithBlock:(id)block {
    ygsSawEnumerate = YES;
    %orig;
}

- (void)organizeSectionControllersInGroups {
    ygsSawOrganize = YES;
    %orig;
}

- (void)setSectionControllers:(id)controllers {
    ygsSawSetSectionControllers = YES;
    %orig;
}

#endif

%end
