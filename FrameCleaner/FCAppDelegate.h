//
//  FCAppDelegate.h
//  FrameCleaner
//
//  Created by Rocco Bowling on 5/6/13.
//  Copyright (c) 2013 Rocco Bowling. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface FCAppDelegate : NSObject <NSApplicationDelegate>
{
    NSView *exportInfo;
    NSMatrix *exportMatrix;
    NSButton *trimImagesBtn;
    NSButton *removeDuplicatesBtn;
    NSButton *compareUsingMD5;
    NSPopUpButton *maxSubregions;
    
    NSOperationQueue * queue;
}

@property (assign) IBOutlet NSView *exportInfo;
@property (assign) IBOutlet NSView *exportMatrix;
@property (assign) IBOutlet NSButton *trimImagesBtn;
@property (assign) IBOutlet NSButton *removeDuplicatesBtn;
@property (assign) IBOutlet NSButton *compareUsingMD5;
@property (assign) IBOutlet NSPopUpButton *maxSubregions;

@end
