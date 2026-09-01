#import "DSForwardingSupport.h"
#include <dlfcn.h>

static void DSForwardingSupportCall(const char *symbol, NSString *bundleID) {
    void (*function)(NSString *) = (void (*)(NSString *))dlsym(RTLD_DEFAULT, symbol);
    if (function) {
        function(bundleID ?: @"");
    }
}

void DSForwardingSupportCallWorkspaceBegin(NSString *bundleID) {
    DSForwardingSupportCall("_Z38DSLSWorkspaceBeginForwardingToBundleIDP8NSString", bundleID);
}

void DSForwardingSupportCallWorkspaceEnd(NSString *bundleID) {
    DSForwardingSupportCall("_Z36DSLSWorkspaceEndForwardingToBundleIDP8NSString", bundleID);
}

BOOL DSForwardingSupportIsAvailable(void) {
    return dlsym(RTLD_DEFAULT, "_Z38DSLSWorkspaceBeginForwardingToBundleIDP8NSString") != NULL &&
           dlsym(RTLD_DEFAULT, "_Z36DSLSWorkspaceEndForwardingToBundleIDP8NSString") != NULL;
}

void DSForwardingSupportSetTargetBundleID(NSString *bundleID) {
    if (bundleID.length == 0) {
        DSForwardingSupportCall("_Z34DSLSAppLinkEndForwardingToBundleIDP8NSString", @"");
        return;
    }
    DSForwardingSupportCall("_Z36DSLSAppLinkBeginForwardingToBundleIDP8NSString", bundleID);
}
