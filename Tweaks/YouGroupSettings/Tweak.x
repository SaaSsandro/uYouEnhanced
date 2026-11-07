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
// The row order inside the group is YouTube's own and cannot be set from here.
//
// Everything below was verified by disassembling the settings screen of the
// YouTube build in Payload/ and by hooking each candidate on the device:
//
//   * +[YTAppSettingsGroupPresentationData orderedGroups] and the group's
//     orderedCategories decide membership and the header - that is why a tweak
//     shows up in the group at all, and why the array here only controls
//     membership, not order
//   * +[YTAppSettingsPresentationData settingsCategoryOrder],
//     -[YTSettingsViewController enumerateSectionControllersWithBlock:],
//     -setSectionControllers and a section's -items are never called, so none of
//     them can be the source either
//   * -[YTSettingsSectionController initWithTitle:items:] is called, but
//     reordering its items changes nothing, and the screen never reads the
//     section's items back
//   * unregistering our sections with removeSectionControllerForSettingCategory:
//     and registering them again inside organizeSectionControllersInGroups (the
//     one lever that reaches far enough) crashes the settings screen
//
// So the order is fixed before any of this runs, inside YouTube's own settings
// model. The tweak keeps the parts that do work: the group, its header, the gear
// icons and the membership.
// ---------------------------------------------------------------------------

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
    return title.length ? title : @"Tweaks";
}

/// Both setSectionItems: variants share this: adopt YTPlus' category, which it
/// never publishes, so its settings end up in the group instead of "Account".
static void YGSAdoptYTPlusSection(NSInteger category, NSString *title) {
    if (!title.length) return;
    if ([title rangeOfString:YTPlusSectionTitle options:NSCaseInsensitiveSearch].location == NSNotFound) return;

    NSMutableArray <NSNumber *> *tweaks = [%c(YTSettingsGroupData) tweaks];
    if (![tweaks containsObject:@(category)]) {
        [tweaks insertObject:@(category) atIndex:0];
    }
}

%hook YTAppSettingsGroupPresentationData

+ (NSArray <YTSettingsGroupData *> *)orderedGroups {
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
        // Membership only - the display order is YouTube's (see the note above).
        // YTPlus is prepended at runtime once its section registers.
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
    if (self.type == TweakGroup)
        return TweakGroupTitle();
    return %orig;
}

- (NSArray <NSNumber *> *)orderedCategories {
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
    if (type == TweakGroup)
        return [[self class] tweaks];
    return %orig;
}

%end

%hook YTSettingsViewController

- (void)setSectionItems:(NSMutableArray *)sectionItems forCategory:(NSInteger)category title:(NSString *)title icon:(YTIIcon *)icon titleDescription:(NSString *)titleDescription headerHidden:(BOOL)headerHidden {
    YGSAdoptYTPlusSection(category, title);

    if (icon == nil && [[%c(YTSettingsGroupData) tweaks] containsObject:@(category)]) {
        icon = [%c(YTIIcon) new];
        icon.iconType = YT_SETTINGS;
    }
    %orig;
}

// The 5-argument variant (no icon) is what e.g. Gonerino registers through; the
// tweak used to ignore it, so those sections never got a gear icon.
- (void)setSectionItems:(NSMutableArray *)sectionItems forCategory:(NSInteger)category title:(NSString *)title titleDescription:(NSString *)titleDescription headerHidden:(BOOL)headerHidden {
    YGSAdoptYTPlusSection(category, title);
    %orig;
}

%end
