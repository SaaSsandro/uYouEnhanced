# Tweaks added by hand through the app (.github/workflows/add-tweak.yml).
#
# The workflow only ever appends to this file - one block per tweak:
#
#   TWEAK_REGISTRY += <id>
#   CUSTOM_TWEAKS += <id>
#   <id>_SUBPROJECT = Tweaks/<id>
#   <id>_DYLIB = <dylib>
#
# The Makefile includes it before TWEAK_REGISTRY is validated, so a tweak listed
# here behaves exactly like one wired up by hand.

# added by add-tweak.yml: PoomSmart/YTUnShorts
TWEAK_REGISTRY += YTUnShorts
CUSTOM_TWEAKS += YTUnShorts
YTUnShorts_SUBPROJECT = Tweaks/YTUnShorts
YTUnShorts_DYLIB = YTUnShorts
