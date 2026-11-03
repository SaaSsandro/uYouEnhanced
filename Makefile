ifndef SDK_VERSION
SDK_VERSION = 26.5
endif

# Minimum iOS version the package and its subprojects are built for.
MIN_IOS_VERSION ?= 15.0

# Xcode 27 no longer accepts deployment targets below iOS 15, and Alderis'
# project file still declares 12.0, so hand our value to its xcodebuild run.
XCODEFLAGS ?= IPHONEOS_DEPLOYMENT_TARGET=$(MIN_IOS_VERSION)
export XCODEFLAGS

export TARGET = iphone:clang:$(SDK_VERSION):$(MIN_IOS_VERSION)
export SDK_PATH = $(THEOS)/sdks/iPhoneOS$(SDK_VERSION).sdk/
export SYSROOT = $(SDK_PATH)
export ARCHS = arm64

TWEAK_NAME ?= uYouEnhanced
DISPLAY_NAME ?= YouTube
BUNDLE_ID ?= com.google.ios.youtube

ifndef YOUTUBE_VERSION
YOUTUBE_VERSION = 21.20.4
endif
ifndef UYOU_VERSION
UYOU_VERSION = 3.0.4
endif
PACKAGE_NAME = $(TWEAK_NAME)
PACKAGE_VERSION = $(YOUTUBE_VERSION)-$(UYOU_VERSION)

# ---------------------------------------------------------------------------
# Optional tweaks
# ---------------------------------------------------------------------------
# ENABLED_TWEAKS selects which optional tweaks are compiled and injected into
# the final package. It is a space-separated list of ids from TWEAK_REGISTRY.
# Override it on the command line, e.g.
#   make package ENABLED_TWEAKS="YouPiP YTUHD"
DEFAULT_TWEAKS = DontEatMyContent FLEXing Return-YouTube-Dislikes YTABConfig \
	YouGroupSettings YTIcons YouLoop YouMute YouPiP YouQuality YouSlider \
	YouSpeed YouTimeStamp YTHoldForSpeed YTVideoOverlay YTweaks YouTubeLegacy

ENABLED_TWEAKS ?= $(DEFAULT_TWEAKS)

TWEAK_REGISTRY = DontEatMyContent FLEXing Return-YouTube-Dislikes YTABConfig \
	YouGroupSettings YTIcons YouLoop YouMute YouPiP YouQuality YouSlider \
	YouSpeed YouTimeStamp YTHoldForSpeed YTVideoOverlay YTweaks YouTubeLegacy \
	iSponsorBlock YTUHD YTAmbientLight YTClassicVideoQuality IAmYouTube \
	NoYTPremium uYouLocalization uYouUnofficial

# <id>_SUBPROJECT is the Theos subproject directory, <id>_DYLIB is the dylib
# it produces and that gets injected into YouTube.
DontEatMyContent_SUBPROJECT = Tweaks/DontEatMyContent
DontEatMyContent_DYLIB = DontEatMyContent
FLEXing_SUBPROJECT = Tweaks/FLEXing/libflex
FLEXing_DYLIB = libFLEX
Return-YouTube-Dislikes_SUBPROJECT = Tweaks/Return-YouTube-Dislikes
Return-YouTube-Dislikes_DYLIB = YouTubeDislikesReturn
YTABConfig_SUBPROJECT = Tweaks/YTABConfig
YTABConfig_DYLIB = YTABConfig
YouGroupSettings_SUBPROJECT = Tweaks/YouGroupSettings
YouGroupSettings_DYLIB = YouGroupSettings
YTIcons_SUBPROJECT = Tweaks/YTIcons
YTIcons_DYLIB = YTIcons
YouLoop_SUBPROJECT = Tweaks/YouLoop
YouLoop_DYLIB = YouLoop
YouMute_SUBPROJECT = Tweaks/YouMute
YouMute_DYLIB = YouMute
YouPiP_SUBPROJECT = Tweaks/YouPiP
YouPiP_DYLIB = YouPiP
YouQuality_SUBPROJECT = Tweaks/YouQuality
YouQuality_DYLIB = YouQuality
YouSlider_SUBPROJECT = Tweaks/YouSlider
YouSlider_DYLIB = YouSlider
YouSpeed_SUBPROJECT = Tweaks/YouSpeed
YouSpeed_DYLIB = YouSpeed
YouTimeStamp_SUBPROJECT = Tweaks/YouTimeStamp
YouTimeStamp_DYLIB = YouTimeStamp
YTHoldForSpeed_SUBPROJECT = Tweaks/YTHoldForSpeed
YTHoldForSpeed_DYLIB = YTHoldForSpeed
YTVideoOverlay_SUBPROJECT = Tweaks/YTVideoOverlay
YTVideoOverlay_DYLIB = YTVideoOverlay
YTweaks_SUBPROJECT = Tweaks/YTweaks
YTweaks_DYLIB = YTweaks
YouTubeLegacy_SUBPROJECT = Tweaks/YouTubeLegacy
YouTubeLegacy_DYLIB = YouTubeLegacy
iSponsorBlock_SUBPROJECT = Tweaks/iSponsorBlock
iSponsorBlock_DYLIB = iSponsorBlock
YTUHD_SUBPROJECT = Tweaks/YTUHD
YTUHD_DYLIB = YTUHD
YTAmbientLight_SUBPROJECT = Tweaks/YTAmbientLight
YTAmbientLight_DYLIB = YTAmbientLight
YTClassicVideoQuality_SUBPROJECT = Tweaks/YTClassicVideoQuality
YTClassicVideoQuality_DYLIB = YTClassicVideoQuality
IAmYouTube_SUBPROJECT = Tweaks/IAmYouTube
IAmYouTube_DYLIB = IAmYouTube
NoYTPremium_SUBPROJECT = Tweaks/NoYTPremium
NoYTPremium_DYLIB = NoYTPremium
uYouLocalization_SUBPROJECT = Tweaks/uYouLocalization
uYouLocalization_DYLIB = uYouLocalization
uYouUnofficial_SUBPROJECT = Tweaks/uYouUnofficial
uYouUnofficial_DYLIB = uYouUnofficial

UNKNOWN_TWEAKS = $(filter-out $(TWEAK_REGISTRY),$(ENABLED_TWEAKS))
ifneq ($(UNKNOWN_TWEAKS),)
$(error Unknown tweak(s) in ENABLED_TWEAKS: $(UNKNOWN_TWEAKS). Valid ids: $(TWEAK_REGISTRY))
endif

ENABLED_TWEAK_SUBPROJECTS = $(foreach t,$(ENABLED_TWEAKS),$($(t)_SUBPROJECT))
ENABLED_TWEAK_DYLIBS = $(foreach t,$(ENABLED_TWEAKS),$(THEOS_OBJ_DIR)/$($(t)_DYLIB).dylib)

$(TWEAK_NAME)_FILES := $(wildcard Sources/*.xm) $(wildcard Sources/*.x) $(wildcard Sources/*.m)
$(TWEAK_NAME)_FRAMEWORKS = UIKit Foundation AVFoundation AVKit Photos Accelerate CoreMotion GameController VideoToolbox Security MediaPlayer JavaScriptCore
$(TWEAK_NAME)_LIBRARIES = bz2 c++ iconv z sqlite3
$(TWEAK_NAME)_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-but-set-variable -Wno-nullability-completeness -DTWEAK_VERSION=\"$(PACKAGE_VERSION)\"

export libcolorpicker_ARCHS = arm64
export libFLEX_ARCHS = arm64
export Alderis_XCODEOPTS = LD_DYLIB_INSTALL_NAME=@rpath/Alderis.framework/Alderis
export Alderis_XCODEFLAGS = DYLIB_INSTALL_NAME_BASE=/Library/Frameworks BUILD_LIBRARY_FOR_DISTRIBUTION=YES ARCHS="$(ARCHS)"
export libcolorpicker_LDFLAGS = -F$(TARGET_PRIVATE_FRAMEWORK_PATH) -install_name @rpath/libcolorpicker.dylib
# libc++ in the iOS 27 SDK warns ("The selected platform is no longer supported")
# for deployment targets below iOS 15, and Theos builds with -Werror. Subprojects
# such as iSponsorBlock still pin 13.0, so demote that warning instead of failing.
export ADDITIONAL_CFLAGS = -I$(THEOS_PROJECT_DIR)/Tweaks/RemoteLog -I$(THEOS_PROJECT_DIR)/Tweaks -Wno-error=\#warnings

ifneq ($(JAILBROKEN),1)
export DEBUGFLAG = -ggdb -Wno-unused-command-line-argument -L$(THEOS_OBJ_DIR) -F$(_THEOS_LOCAL_DATA_DIR)/$(THEOS_OBJ_DIR_NAME)/install/Library/Frameworks
MODULES = jailed
endif

$(TWEAK_NAME)_INJECT_DYLIBS = \
	Tweaks/uYou/Library/MobileSubstrate/DynamicLibraries/uYou.dylib \
	$(ENABLED_TWEAK_DYLIBS)

$(TWEAK_NAME)_EMBED_LIBRARIES = $(THEOS_OBJ_DIR)/libcolorpicker.dylib
$(TWEAK_NAME)_EMBED_FRAMEWORKS = $(_THEOS_LOCAL_DATA_DIR)/$(THEOS_OBJ_DIR_NAME)/install_Alderis.xcarchive/Products/var/jb/Library/Frameworks/Alderis.framework
$(TWEAK_NAME)_EMBED_BUNDLES = $(wildcard Bundles/*.bundle)
$(TWEAK_NAME)_EMBED_EXTENSIONS = $(wildcard Extensions/*.appex)

INSTALL_TARGET_PROCESSES = YouTube
REMOVE_EXTENSIONS = 1
CODESIGN_IPA = 0
FINALPACKAGE = 1

UYOU_PATH = Tweaks/uYou
UYOU_DEB = $(UYOU_PATH)/com.miro.uyou_$(UYOU_VERSION)_iphoneos-arm.deb
UYOU_DYLIB = $(UYOU_PATH)/Library/MobileSubstrate/DynamicLibraries/uYou.dylib
UYOU_BUNDLE = $(UYOU_PATH)/Library/Application\ Support/uYouBundle.bundle

include $(THEOS)/makefiles/common.mk

ifneq ($(JAILBROKEN),1)
SUBPROJECTS += Tweaks/Alderis $(ENABLED_TWEAK_SUBPROJECTS)
include $(THEOS_MAKE_PATH)/aggregate.mk
endif

include $(THEOS_MAKE_PATH)/tweak.mk

.PHONY: internal-clean before-all before-package
internal-clean::
	@rm -rf $(UYOU_PATH)/*

ifneq ($(JAILBROKEN),1)
before-all::
	@if [[ ! -f $(UYOU_DEB) ]]; then \
		rm -rf $(UYOU_PATH)/*; \
		$(PRINT_FORMAT_BLUE) "Downloading uYou"; \
	fi
before-all::
	@if [[ ! -f $(UYOU_DEB) ]]; then \
 		curl -s -L "https://www.dropbox.com/scl/fi/01vvu5lm8nkkicrznku9v/com.miro.uyou_$(UYOU_VERSION)_iphoneos-arm.deb?rlkey=efgz7po8kqqvha8doplk1s3ky&dl=1" -o $(UYOU_DEB); \
 	fi; \
	if [[ ! -f $(UYOU_DYLIB) || ! -d $(UYOU_BUNDLE) ]]; then \
		tar -xf Tweaks/uYou/com.miro.uyou_$(UYOU_VERSION)_iphoneos-arm.deb -C Tweaks/uYou; tar -xf Tweaks/uYou/data.tar* -C Tweaks/uYou; \
		if [[ ! -f $(UYOU_DYLIB) || ! -d $(UYOU_BUNDLE) ]]; then \
			$(PRINT_FORMAT_ERROR) "Failed to extract uYou"; exit 1; \
		fi; \
	fi; \
	perl -pi -e 's/3\.0\.4/3.0.5/g' $(UYOU_DYLIB); \
	$(PRINT_FORMAT_BLUE) "uYou rebranded to 3.0.5 (Unofficial Build)";

before-package::
	@bash tools/stage-ffmpeg.sh "$(THEOS_PROJECT_DIR)/Bundles"

else
before-package::
	@mkdir -p $(THEOS_STAGING_DIR)/Library/Application\ Support; cp -r Localizations/uYouPlus.bundle $(THEOS_STAGING_DIR)/Library/Application\ Support/
endif
after-stage::
	@bash tools/stage-ffmpeg.sh "$(THEOS_STAGING_DIR)"

