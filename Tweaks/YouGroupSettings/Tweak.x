#import <YouTubeHeader/YTIIcon.h>
#import <YouTubeHeader/YTSettingsGroupData.h>
#import <PSHeader/Misc.h>

#define LOC(x) [tweakBundle localizedStringForKey:x value:nil table:nil]

@interface YTSettingsGroupData (YouGroupSettings)
+ (NSMutableArray <NSNumber *> *)tweaks;
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
    return [flags componentsJoinedByString:@","];
}
#endif

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

%hook YTSettingsViewController

- (void)setSectionItems:(NSMutableArray *)sectionItems forCategory:(NSInteger)category title:(NSString *)title icon:(YTIIcon *)icon titleDescription:(NSString *)titleDescription headerHidden:(BOOL)headerHidden {
    NSMutableArray <NSNumber *> *tweaks = [%c(YTSettingsGroupData) tweaks];

    // YTPlus has no public category constant, so adopt the category of the
    // section it registers. It is inserted at index 0 to stay the first entry.
    if (title.length && [title rangeOfString:YTPlusSectionTitle options:NSCaseInsensitiveSearch].location != NSNotFound
        && ![tweaks containsObject:@(category)]) {
        [tweaks insertObject:@(category) atIndex:0];
    }

#if YGS_DEBUG_ORDER
    // Show which slot the tweak assigns to this section, so the rendered order
    // can be compared against it.
    NSInteger index = [tweaks indexOfObject:@(category)];
    if (index != NSNotFound) {
        title = [NSString stringWithFormat:@"%ld · %@", (long)index, title];
    }
#endif

    if (icon == nil && [tweaks containsObject:@(category)]) {
        icon = [%c(YTIIcon) new];
        icon.iconType = YT_SETTINGS;
    }
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
