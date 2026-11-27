ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk
LIBRARY_NAME = T9CarPlaySupport
T9CarPlaySupport_FILES = T9CarPlaySupport.m
T9CarPlaySupport_CFLAGS = -fobjc-arc -fvisibility=hidden
T9CarPlaySupport_FRAMEWORKS = UIKit Foundation CydiaSubstrate
T9CarPlaySupport_LIBRARY_EXTENSION = -
T9CarPlaySupport_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries
include $(THEOS_MAKE_PATH)/library.mk
