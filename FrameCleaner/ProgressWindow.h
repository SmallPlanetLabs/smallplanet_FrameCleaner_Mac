//
//  ProgressWindow.h
//  UI
//
//  Created by Rocco Bowling on 1/25/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface NSWindow (NSProgressWindowAdditions)

- (void) preloadProgressBar;
- (void) startProgressBarWithMessage:(NSString *)message;
- (void) continueProgressBarMessage:(NSString *)message
						  withValue:(float)value;
- (void) stopProgressBarWithMessage:(NSString *)message;

@end

@interface ProgressView : NSView
{
	NSString * message;
	float progress;
}

- (void) setMessage:(NSString *)msg;
- (NSString *) message;
- (void) setValue:(float) p;

@end

@interface ProgressWindow : NSWindow
{
	float alpha;
}

- (id) initWithParent:(NSWindow *)window;
- (void) setMessage:(NSString *)msg;
- (NSString *) message;
- (void) setValue:(float) p;

- (void) reposition;

- (void) closeNow;

@end
