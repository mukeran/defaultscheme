TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = lsd

THEOS_PACKAGE_SCHEME ?= roothide
PACKAGE_BUILDNAME ?=
export CLANG_MODULE_CACHE_PATH ?= $(CURDIR)/.theos/module-cache
.DEFAULT_GOAL := package-roothide
# Keep version stable for the same source version; do not auto-increment build numbers.
PACKAGE_VERSION = $(THEOS_PACKAGE_BASE_VERSION)$(VERSION.EXTRAVERSION)
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
ARCHS = arm64e
else
ARCHS = arm64 arm64e
endif

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = DefaultScheme
DefaultScheme_FILES = \
	App/main.m \
	App/DSAppDelegate.m \
	App/DSRootViewController.m \
	App/DSRuleModels.m \
	App/DSRootUIHelpers.m \
	App/DSAppPickerViewController.m \
	App/DSLinkPathListViewController.m \
	App/DSAppFilterViewController.m \
	App/DSSettingsViewController.m \
	App/DSTestHistoryViewController.m \
	App/DSTestViewController.m \
	App/DSOpenLogListViewController.m \
	App/DSOpenLogDetailViewController.m \
	Shared/DSRoutingConfig.m
DefaultScheme_FRAMEWORKS = UIKit Foundation
DefaultScheme_CFLAGS = -fobjc-arc -IShared -IApp
DefaultScheme_BUNDLE_ID = codes.var.tweak.defaultscheme
DefaultScheme_RESOURCE_FILES = App/Info.plist App/AppIcon20x20@2x.png App/AppIcon20x20@3x.png App/AppIcon29x29@2x.png App/AppIcon29x29@3x.png App/AppIcon40x40@2x.png App/AppIcon40x40@3x.png App/AppIcon60x60@2x.png App/AppIcon60x60@3x.png
DefaultScheme_CODESIGN_FLAGS = -SApp/DefaultScheme.entitlements
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
DefaultScheme_LIBRARIES = roothide
DefaultScheme_CFLAGS += -DDEFAULTSCHEME_ROOTHIDE=1
endif

include $(THEOS_MAKE_PATH)/application.mk

TWEAK_NAME = DefaultSchemeTweak
DefaultSchemeTweak_FILES = \
	Tweak/Tweak.xm \
	Tweak/DSTweakCommon.m \
	Tweak/DSApplicationSupport.m \
	Tweak/DSObjectExtraction.m \
	Tweak/DSOpenActionHandler.m \
	Tweak/DSRouteSupport.m \
	Tweak/DSOpenLogging.m \
	Tweak/DSLSDOpenClientHooks.xm \
	Tweak/DSLSWorkspaceHooks.xm \
	Tweak/DSLSAppLinkHooks.xm \
	Tweak/DSSpringBoardHooks.xm \
	Shared/DSRoutingConfig.m
DefaultSchemeTweak_CFLAGS = -fobjc-arc -IShared -ITweak
DefaultSchemeTweak_FRAMEWORKS = Foundation
DefaultSchemeTweak_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk

TOOL_NAME = defaultschemectl
defaultschemectl_FILES = Helper/main.m Shared/DSRoutingConfig.m
defaultschemectl_CFLAGS = -fobjc-arc -IShared
defaultschemectl_FRAMEWORKS = Foundation
defaultschemectl_INSTALL_PATH = /usr/bin
defaultschemectl_CODESIGN_FLAGS = -SApp/DefaultScheme.entitlements
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
defaultschemectl_LIBRARIES = roothide
defaultschemectl_CFLAGS += -DDEFAULTSCHEME_ROOTHIDE=1
endif

include $(THEOS_MAKE_PATH)/tool.mk

$(THEOS_STAGING_DIR)/DEBIAN/control: control

before-package:: $(THEOS_STAGING_DIR)/DEBIAN/control
	$(ECHO_NOTHING)mkdir -p "$(THEOS_STAGING_DIR)/DEBIAN"$(ECHO_END)
	$(ECHO_NOTHING)cp "layout/DEBIAN/postinst" "$(THEOS_STAGING_DIR)/DEBIAN/postinst"$(ECHO_END)
	$(ECHO_NOTHING)chmod 0755 "$(THEOS_STAGING_DIR)/DEBIAN/postinst"$(ECHO_END)
	$(ECHO_NOTHING)rm -f "$(THEOS_STAGING_DIR)/Applications/DefaultScheme.app/LaunchScreen.storyboard"$(ECHO_END)
	$(ECHO_NOTHING)if [ -f "$(THEOS_STAGING_DIR)/DEBIAN/control" ]; then \
		sed -i '' -E 's/^(Version:[[:space:]]*).*/\1$(PACKAGE_VERSION)/' "$(THEOS_STAGING_DIR)/DEBIAN/control"; \
	fi$(ECHO_END)
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
	$(ECHO_NOTHING)if [ -f "$(THEOS_STAGING_DIR)/DEBIAN/control" ]; then \
		sed -i '' -E 's/^(Architecture:[[:space:]]*).*/\1iphoneos-arm64e/' "$(THEOS_STAGING_DIR)/DEBIAN/control"; \
	fi$(ECHO_END)
	$(ECHO_NOTHING)ln -sf /usr/lib/DynamicPatches/AutoPatches.dylib "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/DefaultSchemeTweak.dylib.roothidepatch"$(ECHO_END)
	$(ECHO_NOTHING)mkdir -p "$(THEOS_STAGING_DIR)/var/mobile/Library/pkgmirror/Library/MobileSubstrate/DynamicLibraries"$(ECHO_END)
	$(ECHO_NOTHING)cp -f "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/DefaultSchemeTweak.dylib" "$(THEOS_STAGING_DIR)/var/mobile/Library/pkgmirror/Library/MobileSubstrate/DynamicLibraries/DefaultSchemeTweak.dylib"$(ECHO_END)
	$(ECHO_NOTHING)cp -f "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/DefaultSchemeTweak.plist" "$(THEOS_STAGING_DIR)/var/mobile/Library/pkgmirror/Library/MobileSubstrate/DynamicLibraries/DefaultSchemeTweak.plist"$(ECHO_END)
	$(ECHO_NOTHING)ln -sf /usr/lib/DynamicPatches/AutoPatches.dylib "$(THEOS_STAGING_DIR)/var/mobile/Library/pkgmirror/Library/MobileSubstrate/DynamicLibraries/DefaultSchemeTweak.dylib.roothidepatch"$(ECHO_END)
endif

after-install::
	install.exec "killall -9 lsd || true"

.PHONY: rename-package-rootful rename-package-rootless rename-package-roothide

define rename_package_with_scheme
	@pkg=$$(ls -t packages/*.deb 2>/dev/null | head -n 1); \
	if [ -n "$$pkg" ]; then \
		case "$$pkg" in \
			*_$(1)_iphoneos-*.deb) ;; \
			*) \
				new=$$(printf '%s\n' "$$pkg" | sed 's/_iphoneos-/_$(1)_iphoneos-/'); \
				if [ "$$pkg" != "$$new" ]; then \
					mv "$$pkg" "$$new"; \
					echo "$$new" > .theos/last_package; \
					echo "Renamed package: $$new"; \
				fi; \
				;; \
		esac; \
	fi
endef

rename-package-rootful:
	$(call rename_package_with_scheme,rootful)

rename-package-rootless:
	$(call rename_package_with_scheme,rootless)

rename-package-roothide:
	$(call rename_package_with_scheme,roothide)

.PHONY: package-rootful package-rootless package-roothide install-rootful install-rootless install-roothide

package-rootful:
	$(MAKE) clean
	$(MAKE) all package THEOS_PACKAGE_SCHEME=
	$(MAKE) rename-package-rootful

package-rootless:
	$(MAKE) clean
	$(MAKE) all package THEOS_PACKAGE_SCHEME=rootless
	$(MAKE) rename-package-rootless

package-roothide:
	$(MAKE) clean
	$(MAKE) all package THEOS_PACKAGE_SCHEME=roothide THEOS_PACKAGE_INSTALL_PREFIX=
	$(MAKE) rename-package-roothide

install-rootful:
	$(MAKE) clean
	$(MAKE) all install THEOS_PACKAGE_SCHEME=

install-rootless:
	$(MAKE) clean
	$(MAKE) all install THEOS_PACKAGE_SCHEME=rootless

install-roothide:
	$(MAKE) clean
	$(MAKE) all install THEOS_PACKAGE_SCHEME=roothide THEOS_PACKAGE_INSTALL_PREFIX=
