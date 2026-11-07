#import <YouTubeHeader/YTIIcon.h>
#import <YouTubeHeader/YTSettingsGroupData.h>
#import <YouTubeHeader/YTSettingsViewController.h>
#import <PSHeader/Misc.h>

#define LOC(x) [tweakBundle localizedStringForKey:x value:nil table:nil]

@interface YTSettingsGroupData (YouGroupSettings)
+ (NSMutableArray <NSNumber *> *)tweaks;
@end

// Undeclared in the header but present in the binary: unregisters a section,
// which is what reordering our sections needs.
@interface YTSettingsViewController (YouGroupSettings)
- (void)removeSectionControllerForSettingCategory:(NSInteger)category;
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
// below) once the order is settled.
//
//   * every grouped section title gets its position in +tweaks prepended
//   * the group header lists which of the settings code paths are live
// ---------------------------------------------------------------------------
#define YGS_DEBUG_ORDER 1

#if YGS_DEBUG_ORDER
static BOOL ygsSawOrderedGroups = NO;
static BOOL ygsSawTitle = NO;
static BOOL ygsSawOrderedCategories = NO;
static BOOL ygsSawOrderedCategoriesForType = NO;
static BOOL ygsSawOrganize = NO;

static NSString *YGSHookFlags(void) {
    NSMutableArray <NSString *> *flags = [NSMutableArray array];
    if (ygsSawOrderedGroups) [flags addObject:@"og"];
    if (ygsSawTitle) [flags addObject:@"t"];
    if (ygsSawOrderedCategories) [flags addObject:@"oc"];
    if (ygsSawOrderedCategoriesForType) [flags addObject:@"oct"];
    if (ygsSawOrganize) [flags addObject:@"gz"];
    return [flags componentsJoinedByString:@","];
}
#endif

// ---------------------------------------------------------------------------
// Reordering.
//
// Everything the tweak can set on the settings data model turned out not to
// drive the row order: the settings screen never reads a section's -items, the
// global category order path is not even called, and sorting the group's
// category list only changed membership. The order is fixed when a tweak's
// section is registered, i.e. before the group is assembled.
//
// So remember every registration of our sections and, right before YouTube
// builds the groups, unregister and register them again in +tweaks order. Only
// our own categories are touched.
// ---------------------------------------------------------------------------
#define YGS_REORDER_SECTIONS 1

#if YGS_REORDER_SECTIONS
static BOOL ygsReplaying = NO;
static BOOL ygsReordered = NO;
static NSMutableDictionary <NSNumber *, NSArray *> *ygsRegistrations = nil;

static void YGSRememberRegistration(NSInteger category, NSArray *arguments) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ygsRegistrations = [NSMutableDictionary new];
    });
    ygsRegistrations[@(category)] = arguments;
}

static void YGSReorderSections(YTSettingsViewController *controller) {
    if (ygsReordered || ygsRegistrations.count < 2) return;
    ygsReordered = YES;

    NSArray <NSNumber *> *order = [%c(YTSettingsGroupData) tweaks];
    NSMutableArray <NSNumber *> *mine = [NSMutableArray array];
    for (NSNumber *category in order) {
        if (ygsRegistrations[category]) [mine addObject:category];
    }
    if (mine.count < 2) return;

    for (NSNumber *category in mine) {
        [controller removeSectionControllerForSettingCategory:category.integerValue];
    }

    ygsReplaying = YES;
    for (NSNumber *category in mine) {
        NSArray *arguments = ygsRegistrations[category];
        [controller setSectionItems:arguments[0]
                        forCategory:category.integerValue
                              title:arguments[1]
                               icon:arguments[2] == [NSNull null] ? nil : arguments[2]
                   titleDescription:arguments[3] == [NSNull null] ? nil : arguments[3]
                       headerHidden:[arguments[4] boolValue]];
    }
    ygsReplaying = NO;
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

/// Shared handling for both setSectionItems: variants: adopt YTPlus' category
/// and (in the diagnostic build) prefix the title with its position.
static NSString *YGSNoteSection(NSInteger category, NSString *title) {
    NSMutableArray <NSNumber *> *tweaks = [%c(YTSettingsGroupData) tweaks];

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

%hook YTSettingsGroupData

%new(@@:)
+ (NSMutableArray <NSNumber *> *)tweaks {
    static NSMutableArray <NSNumber *> *tweaks = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Order: YTPlus first (inserted by the section hooks when it is
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
// methods; the settings screen reads the properties, but both are hooked so the
// group keeps working if that changes.
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
    if (ygsReplaying) {
        %orig;
        return;
    }

    title = YGSNoteSection(category, title);

    if (icon == nil && [[%c(YTSettingsGroupData) tweaks] containsObject:@(category)]) {
        icon = [%c(YTIIcon) new];
        icon.iconType = YT_SETTINGS;
    }
#if YGS_REORDER_SECTIONS
    if ([[%c(YTSettingsGroupData) tweaks] containsObject:@(category)]) {
        YGSRememberRegistration(category, @[sectionItems, title,
                                           icon ?: [NSNull null],
                                           titleDescription ?: [NSNull null],
                                           @(headerHidden)]);
    }
#endif
    %orig;
}

// The 5-argument variant (no icon) is what e.g. Gonerino registers through; the
// tweak used to ignore it, so those sections never got an index or a gear icon.
- (void)setSectionItems:(NSMutableArray *)sectionItems forCategory:(NSInteger)category title:(NSString *)title titleDescription:(NSString *)titleDescription headerHidden:(BOOL)headerHidden {
    if (ygsReplaying) {
        %orig;
        return;
    }

    title = YGSNoteSection(category, title);
#if YGS_REORDER_SECTIONS
    if ([[%c(YTSettingsGroupData) tweaks] containsObject:@(category)]) {
        YGSRememberRegistration(category, @[sectionItems, title,
                                           [NSNull null],
                                           titleDescription ?: [NSNull null],
                                           @(headerHidden)]);
    }
#endif
    %orig;
}

- (void)organizeSectionControllersInGroups {
#if YGS_DEBUG_ORDER
    ygsSawOrganize = YES;
#endif
#if YGS_REORDER_SECTIONS
    YGSReorderSections(self);
#endif
    %orig;
}

%end
