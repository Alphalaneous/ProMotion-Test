#include <Geode/Geode.hpp>
#include <Geode/cocos/platform/ios/CCDirectorCaller.h>
#include <Geode/modify/CCApplication.hpp>

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

using namespace geode::prelude;

static NSDictionary* (*infoDictionary_o)(id, SEL);

static NSDictionary* infoDictionary_h(id self, SEL _cmd) {
    auto original = infoDictionary_o(self, _cmd);

    if (!original) return nil;

    auto dict = [original mutableCopy];
    dict[@"CADisableMinimumFrameDurationOnPhone"] = @YES;

    return dict;
}

$execute {
    auto cls = [NSBundle class];
    auto sel = @selector(infoDictionary);
    auto method = class_getInstanceMethod(cls, sel);

    infoDictionary_o = (NSDictionary* (*)(id, SEL))method_getImplementation(method);

    method_setImplementation(method, (IMP)infoDictionary_h);
}

static void setupDisplayLink() {
    auto caller = (CCDirectorCaller*)[CCDirectorCaller sharedDirectorCaller];
    Ivar ivar = class_getInstanceVariable(
        [CCDirectorCaller class],
        "displayLink"
    );

    auto link = object_getIvar(caller, ivar);
    
    if (!link) return;

    if (@available(iOS 15.0, *)) {
        link.preferredFrameRateRange = CAFrameRateRangeMake(120.0, 120.0, 120.0);
    }
}

class $modify(MyCCApplication, CCApplication) {

    int run() {
        queueInMainThread([] {
            setupDisplayLink();
        });

        return CCApplication::run();
    }

    void setAnimationInterval(double interval) {
        CCApplication::setAnimationInterval(interval);

        setupDisplayLink();
    }
};