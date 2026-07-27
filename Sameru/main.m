//
//  main.m
//  Sameru
//
//  Created by Vincent Yang  on 7/27/26.
//

#import <Cocoa/Cocoa.h>

#import "AppDelegate.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // No storyboard and no Dock icon: Sameru lives entirely in the menu bar.
        static AppDelegate *delegate;
        delegate = [[AppDelegate alloc] init];

        NSApplication *application = NSApplication.sharedApplication;
        application.delegate = delegate;
        [application setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [application run];
    }
    return 0;
}
