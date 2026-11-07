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
// picks it up from the section YTPlus registers. That is what puts YTPlus into
// the group instead of leaving it under "Account".
static NSString *const YTPlusSectionTitle = @"YouTube Plus";

// Note: the order of the rows inside the group is YouTube's own and is not
// reachable from here. Verified against the YouTube build in Payload/: the
// group's category list below only decides membership, the section's items and
// the global category order are never even read, and re-registering the sections
// crashes the settings screen. See the git history if this ever needs revisiting.

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
// bundle, which has no .lproj for most device languages.
static NSString *TweakGroupTitle() {
    NSBundle *tweakBundle = TweakBundle();
    NSString *title = LOC(@"TWEAKS");
    return title.length ? title : @"Tweaks";
}

/// Both setSectionItems: variants share this: adopt YTPlus' category, which it
/// never publishes, so its settings end up in the group.
static void YGSAdoptYTPlusSection(NSInteger category, NSString *title) {
    if (!title.length) return;
    if ([title rangeOfString:YTPlusSectionTitle options:NSCaseInsensitiveSearch].location == NSNotFound) return;

    NSMutableArray <NSNumber *> *tweaks = [%c(YTSettingsGroupData) tweaks];
    if (![tweaks containsObject:@(category)]) {
        [tweaks addObject:@(category)];
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
        tweaks = [NSMutableArray new];
        [tweaks addObjectsFromArray:@[
            @(404), // YTABConfig
            @(FLEXHelperForYT), // FLEXing
            @(YTIcons), // YTIcons
            @(YTweaks), // YTweaks
            @(VolumeBoostYT), // VolumeBoostYT
            @(2002), // Gonerino
            @(YTFlags), // YTFlags
            @(YouMod), // YouMod
            @(517), // DontEatMyContent
            @(1080), // Return YouTube Dislike
            @(YTUHD), // YTUHD
            @(YouChooseQuality), // YouChooseQuality
            @(200), // YouPiP
            @(YouSlider), // YouSlider
            @(2168), // YTHoldForSpeed
            @(1222), // YTVideoOverlay
        ]];
    });
    return tweaks;
}

// The settings screen reads the title property, not titleForSettingGroupType:;
// hooking only the latter left the group header empty.
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
// tweak used to ignore it, so those sections got no gear icon.
- (void)setSectionItems:(NSMutableArray *)sectionItems forCategory:(NSInteger)category title:(NSString *)title titleDescription:(NSString *)titleDescription headerHidden:(BOOL)headerHidden {
    YGSAdoptYTPlusSection(category, title);
    %orig;
}

%end
