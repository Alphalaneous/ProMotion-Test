#include "Geode/loader/Log.hpp"
#include <Geode/Geode.hpp>
#include <Geode/modify/CCApplication.hpp>

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>

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
    Class cls = objc_getClass("CCDirectorCaller");
    if (!cls) return;

    id caller = ((id (*)(id, SEL))objc_msgSend)(
        cls,
        @selector(sharedDirectorCaller)
    );

    if (!caller) return;

    Ivar ivar = class_getInstanceVariable(cls, "displayLink");
    if (!ivar) return;

    auto link = (CADisplayLink*)object_getIvar(caller, ivar);
    if (!link) return;

    if (@available(iOS 10.0, *)) {
        link.preferredFramesPerSecond = 120;
    }

    log::info("duration: {}, refresh rate: {}", (float)link.duration, (long)[UIScreen mainScreen].maximumFramesPerSecond);
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