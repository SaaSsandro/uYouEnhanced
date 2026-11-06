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
ifndef YTPLUS_VERSION
YTPLUS_VERSION = 6.0
endif
PACKAGE_NAME = $(TWEAK_NAME)
PACKAGE_VERSION = $(YOUTUBE_VERSION)-$(YTPLUS_VERSION)

# uYouEnhanced is this repo's own aggregate tweak. With INCLUDE_UYOUENHANCED=0 it
# is still compiled - Theos needs the root target - but it is neither injected
# nor embedded, and neither is its settings bundle or the Alderis framework.
INCLUDE_UYOUENHANCED ?= 0

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

# PAYLOAD_TWEAKS are shipped as prebuilt .deb files that the build unpacks and
# injects (the way uYou used to be handled). They have no subproject to compile,
# but they are selectable through ENABLED_TWEAKS like any other tweak.
PAYLOAD_TWEAKS = YTPlus

UNKNOWN_TWEAKS = $(filter-out $(TWEAK_REGISTRY) $(PAYLOAD_TWEAKS),$(ENABLED_TWEAKS))
ifneq ($(UNKNOWN_TWEAKS),)
$(error Unknown tweak(s) in ENABLED_TWEAKS: $(UNKNOWN_TWEAKS). Valid ids: $(TWEAK_REGISTRY) $(PAYLOAD_TWEAKS))
endif

ENABLED_TWEAK_SUBPROJECTS = $(foreach t,$(filter-out $(PAYLOAD_TWEAKS),$(ENABLED_TWEAKS)),$($(t)_SUBPROJECT))
ENABLED_TWEAK_DYLIBS = $(foreach t,$(filter-out $(PAYLOAD_TWEAKS),$(ENABLED_TWEAKS)),$(THEOS_OBJ_DIR)/$($(t)_DYLIB).dylib)

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

$(TWEAK_NAME)_INJECT_DYLIBS = $(ENABLED_TWEAK_DYLIBS)

$(TWEAK_NAME)_EMBED_LIBRARIES = $(THEOS_OBJ_DIR)/libcolorpicker.dylib
$(TWEAK_NAME)_EMBED_BUNDLES = $(wildcard Bundles/*.bundle)
$(TWEAK_NAME)_EMBED_EXTENSIONS = $(wildcard Extensions/*.appex)

ifeq ($(INCLUDE_UYOUENHANCED),1)
$(TWEAK_NAME)_EMBED_FRAMEWORKS = $(_THEOS_LOCAL_DATA_DIR)/$(THEOS_OBJ_DIR_NAME)/install_Alderis.xcarchive/Products/var/jb/Library/Frameworks/Alderis.framework
else
# uYouEnhanced is the only consumer of the Alderis framework and of its own
# settings bundle; libcolorpicker still comes from Alderis' lcpshim subproject.
$(TWEAK_NAME)_EMBED_BUNDLES := $(filter-out Bundles/uYouPlus.bundle,$($(TWEAK_NAME)_EMBED_BUNDLES))
endif

INSTALL_TARGET_PROCESSES = YouTube
REMOVE_EXTENSIONS = 1
CODESIGN_IPA = 0
FINALPACKAGE = 1

# YTPlus (formerly YTLite) ships as a prebuilt package, so its paths are
# constants rather than build outputs. If upstream renames the library or the
# bundle, adjust these lines - the extraction step fails loudly if they change.
YTPlus_DYLIB = YTLite
YTPlus_BUNDLE = YTLite
YTPLUS_URL = https://repo.ballermc.com/tubevault/%5BROOTLESS%5Dcom.dvntm.ytlite_$(YTPLUS_VERSION)_iphoneos-arm64_patched_SpyG.deb
YTPLUS_PATH = Tweaks/YTPlus
YTPLUS_DEB = $(YTPLUS_PATH)/ytplus_$(YTPLUS_VERSION).deb
YTPLUS_LIBRARY = $(YTPLUS_PATH)/var/jb/Library
YTPLUS_DYLIB = $(YTPLUS_LIBRARY)/MobileSubstrate/DynamicLibraries/$(YTPlus_DYLIB).dylib
# The bundle ships under "Application Support", but theos-jailed reads
# EMBED_BUNDLES by word splitting, and a backslash-escaped space does not
# survive that - the extraction below moves the bundle to a path without spaces.
YTPLUS_BUNDLE = $(YTPLUS_PATH)/$(YTPlus_BUNDLE).bundle

ifneq ($(filter YTPlus,$(ENABLED_TWEAKS)),)
$(TWEAK_NAME)_INJECT_DYLIBS += $(YTPLUS_DYLIB)
$(TWEAK_NAME)_EMBED_BUNDLES += $(YTPLUS_BUNDLE)
endif

ifeq ($(INCLUDE_UYOUENHANCED),0)
# Drops the root dylib from theos-jailed's inject list. Upstream builds that list
# as inject_files=("$DYLIB" $INJECT_DYLIBS), so an empty value would become an
# empty argument - and rsync before 3.2.3 reads an empty source arg as "." and
# copies the whole build directory into the app (a ~700 MB IPA). The workflow
# unquotes the variable in the installed ipa.sh and fails the build if it cannot,
# so an empty DYLIB contributes no entry at all.
export DYLIB :=
endif

# Name the packed IPA after the payload it mostly carries.
export OUTPUT_NAME := YTPlus_$(PACKAGE_VERSION).ipa

include $(THEOS)/makefiles/common.mk

ifneq ($(JAILBROKEN),1)
SUBPROJECTS += Tweaks/Alderis $(ENABLED_TWEAK_SUBPROJECTS)
include $(THEOS_MAKE_PATH)/aggregate.mk
endif

include $(THEOS_MAKE_PATH)/tweak.mk

.PHONY: internal-clean before-all before-package
internal-clean::
	@rm -rf $(YTPLUS_PATH)

ifneq ($(JAILBROKEN),1)
ifneq ($(filter YTPlus,$(ENABLED_TWEAKS)),)
before-all::
	@if [[ ! -f $(YTPLUS_DEB) ]]; then \
		mkdir -p $(YTPLUS_PATH); \
		$(PRINT_FORMAT_BLUE) "Downloading YTPlus"; \
		curl -s -L "$(YTPLUS_URL)" -o $(YTPLUS_DEB); \
	fi; \
	if [[ ! -f $(YTPLUS_DYLIB) ]]; then \
		$(PRINT_FORMAT_BLUE) "Extracting YTPlus"; \
		tar -xf $(YTPLUS_DEB) -C $(YTPLUS_PATH); \
		tar -xf $(YTPLUS_PATH)/data.tar.* -C $(YTPLUS_PATH); \
	fi; \
	if [[ ! -d $(YTPLUS_BUNDLE) && -d "$(YTPLUS_LIBRARY)/Application Support/$(YTPlus_BUNDLE).bundle" ]]; then \
		mv "$(YTPLUS_LIBRARY)/Application Support/$(YTPlus_BUNDLE).bundle" $(YTPLUS_BUNDLE); \
	fi; \
	if [[ ! -f $(YTPLUS_DYLIB) || ! -d $(YTPLUS_BUNDLE) ]]; then \
		$(PRINT_FORMAT_ERROR) "Failed to extract YTPlus - expected $(YTPLUS_DYLIB) and $(YTPLUS_BUNDLE)"; exit 1; \
	fi; \
	$(PRINT_FORMAT_BLUE) "YTPlus ready";
endif

before-package::
	@bash tools/stage-ffmpeg.sh "$(THEOS_PROJECT_DIR)/Bundles"

else
before-package::
	@mkdir -p $(THEOS_STAGING_DIR)/Library/Application\ Support; cp -r Localizations/uYouPlus.bundle $(THEOS_STAGING_DIR)/Library/Application\ Support/
endif
after-stage::
	@bash tools/stage-ffmpeg.sh "$(THEOS_STAGING_DIR)"

