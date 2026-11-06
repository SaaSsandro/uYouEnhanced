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

NSBundle *TweakBundle() {
    static NSBundle *bundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *tweakBundlePath = [[NSBundle mainBundle] pathForResource:@"YouGroupSettings" ofType:@"bundle"];
        bundle = [NSBundle bundleWithPath:tweakBundlePath ?: PS_ROOT_PATH_NS(@"/Library/Application Support/YouGroupSettings.bundle")];
    });
    return bundle;
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

- (NSString *)titleForSettingGroupType:(NSUInteger)type {
    if (type == TweakGroup) {
        NSBundle *tweakBundle = TweakBundle();
        NSString *title = LOC(@"TWEAKS");
        // The bundle lookup fails when the device language has no .lproj here,
        // which used to leave the group header empty - fall back to the name.
        return title.length ? title : @"Tweaks";
    }
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
    NSMutableArray <NSNumber *> *tweaks = [%c(YTSettingsGroupData) tweaks];

    // YTPlus has no public category constant, so adopt the category of the
    // section it registers. It is inserted at index 0 to stay the first entry.
    if (title.length && [title rangeOfString:YTPlusSectionTitle options:NSCaseInsensitiveSearch].location != NSNotFound
        && ![tweaks containsObject:@(category)]) {
        [tweaks insertObject:@(category) atIndex:0];
    }

    if (icon == nil && [tweaks containsObject:@(category)]) {
        icon = [%c(YTIIcon) new];
        icon.iconType = YT_SETTINGS;
    }
    %orig;
}

%end
