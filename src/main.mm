#include "Geode/cocos/CCDirector.h"
#include "Geode/cocos/CCScheduler.h"
#include "Geode/loader/Log.hpp"
#include <Geode/Geode.hpp>
#include <Geode/modify/CCApplication.hpp>
#include <Geode/modify/CCScheduler.hpp>
#include <Geode/modify/CCDirector.hpp>

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>

using namespace geode::prelude;

static NSDictionary* (*infoDictionary_o)(id, SEL);

static NSDictionary* infoDictionary_h(id self, SEL sel) {
    auto original = infoDictionary_o(self, sel);

    if (!original) return nil;

    auto dict = [original mutableCopy];
    dict[@"CADisableMinimumFrameDurationOnPhone"] = @YES;

    return dict;
}

static void (*setPaused_o)(id, SEL, BOOL);

static void setPaused_h(id self, SEL sel, BOOL paused) {

}

static BOOL (*isPaused_o)(id, SEL);

static BOOL isPaused_h(id self, SEL sel) {
    return NO;
}

static void (*setHighFrameRateReasons_o)(id, SEL, const unsigned*, unsigned long long);

static void setHighFrameRateReasons_h(id self, SEL sel, const unsigned* reasons, unsigned long long count) {
    log::info(
        "HFR reasons={}, count={}",
        reinterpret_cast<uintptr_t>(reasons),
        count
    );

    setHighFrameRateReasons_o(
        self,
        sel,
        reasons,
        count
    );
}

static void (*setPreferredFrameRateRange_o)(id, SEL, CAFrameRateRange range);

static void setPreferredFrameRateRange_h(id self, SEL sel, CAFrameRateRange range) {
    range.minimum = 120;
    range.preferred = 120;
    range.maximum = 120;
    setPreferredFrameRateRange_o(self, sel, range);
}

static void (*CADisplayLink_setHighFrameRateReasons_o)(id, SEL, const unsigned*, unsigned long long);

static void CADisplayLink_setHighFrameRateReasons_h(id self, SEL sel, const unsigned* reasons, unsigned long long count) {
    log::info(
        "CADisplayLink HFR reasons={}, count={}",
        reinterpret_cast<uintptr_t>(reasons),
        count
    );

    CADisplayLink_setHighFrameRateReasons_o(
        self,
        sel,
        reasons,
        count
    );
}

static void swizzleNSBundle() {
    auto cls = [NSBundle class];

    auto method = class_getInstanceMethod(cls, @selector(infoDictionary));
    infoDictionary_o = (NSDictionary* (*)(id, SEL))method_getImplementation(method);
    method_setImplementation(method, (IMP)infoDictionary_h);
}

static void swizzleCADynamicFrameRateSource() {
    auto cls = objc_getClass("CADynamicFrameRateSource");

    auto method = class_getInstanceMethod(cls, @selector(setPaused:));
    setPaused_o = (void (*)(id, SEL, BOOL))method_getImplementation(method);
    method_setImplementation(method, (IMP)setPaused_h);

    auto method2 = class_getInstanceMethod(cls, @selector(isPaused));
    isPaused_o = (BOOL (*)(id, SEL))method_getImplementation(method2);
    method_setImplementation(method2, (IMP)isPaused_h);

    auto method3 = class_getInstanceMethod(cls, @selector(setHighFrameRateReasons:count:));
    setHighFrameRateReasons_o = (void (*)(id, SEL, const unsigned*, unsigned long long))method_getImplementation(method3);
    method_setImplementation(method3, (IMP)setHighFrameRateReasons_h);

    auto method4 = class_getInstanceMethod(cls, @selector(setPreferredFrameRateRange:range:));
    setPreferredFrameRateRange_o = (void (*)(id, SEL, CAFrameRateRange))method_getImplementation(method4);
    method_setImplementation(method4, (IMP)setPreferredFrameRateRange_h);
}

static void swizzleCADisplayLink() {
    auto cls = objc_getClass("CADisplayLink");

    auto method = class_getInstanceMethod(cls, @selector(setHighFrameRateReasons:count:));
    CADisplayLink_setHighFrameRateReasons_o = (void (*)(id, SEL, const unsigned*, unsigned long long))method_getImplementation(method);
    method_setImplementation(method, (IMP)CADisplayLink_setHighFrameRateReasons_h);
}

static CADisplayLink* newLink = nullptr;

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

    auto oldLink = (CADisplayLink*)object_getIvar(caller, ivar);
    if (!oldLink) return;

    [oldLink invalidate];

    Class displayLinkClass = objc_getClass("CADisplayLink");

    newLink = (CADisplayLink*)((id (*)(id, SEL, id, SEL))objc_msgSend)(
        displayLinkClass,
        @selector(displayLinkWithTarget:selector:),
        caller,
        @selector(doCaller:)
    );
    if (!newLink) return;

    if (@available(iOS 15.0, *)) {
        newLink.preferredFrameRateRange = CAFrameRateRange{
            .minimum = 120.0,
            .maximum = 120.0,
            .preferred = 120.0,
        };
    }

    if (@available(iOS 10.0, *)) {
        newLink.preferredFramesPerSecond = 120;
    }

    object_setIvar(caller, ivar, newLink);

    [newLink addToRunLoop:[NSRunLoop currentRunLoop]
                  forMode:NSRunLoopCommonModes];

    log::info("duration: {}", (float)newLink.duration);
}


$execute {
    swizzleNSBundle();
    swizzleCADynamicFrameRateSource();
    swizzleCADisplayLink();
    setupDisplayLink();

    auto cls = objc_getClass("CADynamicFrameRateSource");

    unsigned count = 0;
    auto methods = class_copyMethodList(cls, &count);

    for (unsigned i = 0; i < count; ++i) {
        auto sel = method_getName(methods[i]);
        log::info("CADynamicFrameRateSource: {}", sel_getName(sel));
    }

    free(methods);
}

class $modify(MyCCScheduler, CCScheduler) {

    void update(float dt) {
        CCScheduler::update(dt);
        log::info("duration: {}, dt: {}", (float)newLink.duration, dt);
    }

};

class $modify(MyCCDirector, CCDirector) {
    bool init() {
        if (!CCDirector::init()) return false;
        setAnimationInterval(1.f/120.f);
        return true;
    }
};

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