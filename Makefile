ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CarPlay26
CarPlay26_FILES = Tweak.xm LauncherIcon26.xm OtherFunctions.xm WallpaperProbe.xm WallpaperModelTrace.xm WallpaperBackgroundTrace.xm WallpaperAssets.m SpotifyTemplateProbe.xm SpotifyHomeStyling.xm SpotifyHomeLayout.m SpotifyReference.m SpotifyBrowser.m SpotifyMiniPlayer.m SpotifyNavigation.m SpotifyPlayerScreen.m SpotifyDock.m DashboardGlassPolish.xm CommunicationAppearance.m CommunicationUI.m CommunicationHeaders.m CommunicationLists.m CommunicationHooks.xm InCallAppearance.xm
CarPlay26_CFLAGS = -fobjc-arc
CarPlay26_FRAMEWORKS = Foundation UIKit QuartzCore CarPlay CoreGraphics Vision ImageIO
include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += Prefs
include $(THEOS_MAKE_PATH)/aggregate.mk
