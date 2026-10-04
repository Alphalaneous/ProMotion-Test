#include "Geode/cocos/CCDirector.h"
#include "Geode/cocos/CCScheduler.h"
#include "Geode/loader/Log.hpp"
#include <Geode/Geode.hpp>
#include <Geode/modify/CCApplication.hpp>
#include <Geode/modify/CCScheduler.hpp>

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

static void (*setPaused_o)(id, SEL, BOOL);

static void setPaused_h(id self, SEL sel, BOOL paused) {

}

static BOOL (*isPaused_o)(id, SEL);

static BOOL isPaused_h(id self, SEL sel) {
    return NO;
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
    setupDisplayLink();

    CCDirector::get()->setAnimationInterval(1.f/120.f);
}

class $modify(MyCCScheduler, CCScheduler) {

    void update(float dt) {
        CCScheduler::update(dt);
        log::info("duration: {}, dt: {}", (float)newLink.duration, dt);
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