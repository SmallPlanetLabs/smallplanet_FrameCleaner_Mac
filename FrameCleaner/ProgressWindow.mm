//
//  ProgressWindow.mm
//  UI
//
//  Created by Rocco Bowling on 1/25/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//


#import "ProgressWindow.h"
#import "rects.h"

@implementation NSWindow (NSProgressWindowAdditions)

- (ProgressWindow *) sharedProgressWindow
{
	NSArray * children = [self childWindows];
	NSEnumerator * enumerator = [children objectEnumerator];
	ProgressWindow * child_window;
	
	while(child_window = [enumerator nextObject])
	{
		if([child_window isKindOfClass:[ProgressWindow class]])
		{
			return child_window;
		}
	}
	
	return 0;
}

- (void) preloadProgressBar
{
	ProgressWindow * pw = [self sharedProgressWindow];
	
	if(!pw)
	{
		pw = [[ProgressWindow alloc] initWithParent:self];
	}
	
	[pw setMessage:@"SPECIAL_PRELOAD_MESSAGE"];
	
	[pw reposition];
	
	[pw makeKeyAndOrderFront:self];
	
	[pw displayIfNeeded];
}

- (void) startProgressBarWithMessage:(NSString *)message
{
	ProgressWindow * pw = [self sharedProgressWindow];
	
	if(!pw)
	{
		pw = [[ProgressWindow alloc] initWithParent:self];
	}
	
	[pw setMessage:message];
	
	[pw reposition];
	
	[pw makeKeyAndOrderFront:self];
	
	[pw displayIfNeeded];
}

- (void) continueProgressBarMessage:(NSString *)message
						  withValue:(float)value
{
	ProgressWindow * pw = [self sharedProgressWindow];
	
	if(pw)
	{
		if(message)
		{
			[pw setMessage:message];
		}
		[pw setValue:value];
		
		[pw reposition];
		
		[pw makeKeyAndOrderFront:self];
		[pw displayIfNeeded];
	}
}

- (void) stopProgressBarWithMessage:(NSString *)message
{
	ProgressWindow * pw = [self sharedProgressWindow];
	
	if(pw)
	{
		// If we have never displayed a message, close quickly
		if([[pw message] isEqualToString:@"SPECIAL_PRELOAD_MESSAGE"])
		{
			[pw closeNow];
			return;
		}
		
		
		[pw setMessage:message];
		[pw setValue:1.0];
		
		[pw reposition];
		
		[pw makeKeyAndOrderFront:self];
		[pw displayIfNeeded];
		[pw close];
	}
}

@end

@implementation ProgressView

- (void) drawRect: (NSRect) rect
{
    if(![[NSGraphicsContext currentContext] graphicsPort])
        return;
    
	if([message isEqualToString:@"SPECIAL_PRELOAD_MESSAGE"])
	{
		
	}
	else
	{
		NSMutableDictionary * bold12White = [[NSMutableDictionary alloc]init];
		NSRect frame = [self bounds];
		NSSize size;
		CGRect cgrect;
		
		
		[bold12White setObject: [NSFont fontWithName: @"Helvetica" size: 14] forKey: NSFontAttributeName];
		[bold12White setObject: [[NSColor whiteColor] colorWithAlphaComponent:1.0] forKey: NSForegroundColorAttributeName];
		
		size = [message sizeWithAttributes:bold12White];
		
		
		// Render the background...
		cgrect = CGRectMake(frame.origin.x, frame.origin.x, frame.size.width, frame.size.height);
		
		[[NSColor colorWithCalibratedRed:0.0
								   green:0.0
									blue:0.0
								   alpha:0.7] set];
		
		
		fillRoundedRect((CGContext *)[[NSGraphicsContext currentContext] graphicsPort],
						cgrect,
						16, 16);
		
		// Render the progress bar
		cgrect = CGRectInset(cgrect, 16, 16);
		cgrect.size.height = 12;
		cgrect.origin.y = frame.size.height - (24 + 32);
		
		paintRect((CGContext *)[[NSGraphicsContext currentContext] graphicsPort],
				  cgrect);
		
		
		// for message background
		/*
		fillRoundedRect((CGContext *)[[NSGraphicsContext currentContext] graphicsPort],
						CGRectMake(cgrect.origin.x + cgrect.size.width * 0.5 - (size.width+20) * 0.5, frame.size.height - 30, size.width + 20, 18),
						4, 4);
		 */
		
		[[NSColor colorWithCalibratedRed:0.8
								   green:0.8
									blue:0.8
								   alpha:1.0] set];
			
		paintRect((CGContext *)[[NSGraphicsContext currentContext] graphicsPort],
				  CGRectMake(cgrect.origin.x, cgrect.origin.y, cgrect.size.width * progress, cgrect.size.height));
		
		[[NSColor colorWithCalibratedRed:1.0
								   green:1.0
									blue:1.0
								   alpha:1.0] set];
		
		CGContextSetLineWidth((CGContext *)[[NSGraphicsContext currentContext] graphicsPort], 2);
		
		strokeRoundedRect((CGContext *)[[NSGraphicsContext currentContext] graphicsPort],
						  cgrect,
						  4, 4);
		
		// Render the messge...
		[message drawAtPoint:NSMakePoint(frame.size.width * 0.5 - size.width * 0.5, frame.size.height - 30)
			  withAttributes:bold12White];
		
		[bold12White release];
	}
}

- (void) setMessage:(NSString *)msg
{
	[message release];
	message = [msg retain];
	
	[self setNeedsDisplay:YES];
}

- (NSString *) message
{
	return message;
}

- (void) setValue:(float) p
{
	progress = p;
		
	[self setNeedsDisplay:YES];
}

- (void) dealloc
{
	[message release];
	[super dealloc];
}

@end



@implementation ProgressWindow

- (id) initWithParent:(NSWindow *)parentWindow;
{
	NSRect bounds = NSMakeRect(0, 0, 260, 72);
	NSRect frame = bounds;
	NSRect parentWindowFrame = [parentWindow frame];
	
	// Position myself to the center of the parent window...
	frame.origin.x = parentWindowFrame.origin.x + parentWindowFrame.size.width * 0.5 - frame.size.width * 0.5;
	frame.origin.y = parentWindowFrame.origin.y + parentWindowFrame.size.height * 0.5 - frame.size.height * 0.5;
	
	self = [super initWithContentRect:frame
							styleMask:NSBorderlessWindowMask
							  backing:NSBackingStoreBuffered
								defer:YES];
	
	if(self)
	{
		ProgressView * content_view;
				
		// Make me invisible
		[self setBackgroundColor:[NSColor clearColor]];
		[self setOpaque:NO];
		
		// Make my content view
		content_view = [[ProgressView alloc] initWithFrame:bounds];
		[self setContentView:content_view];
		
		// Attach me to my parent window
		if(parentWindow)
		{
			[parentWindow addChildWindow:self
								 ordered:NSWindowAbove];
						
			[[NSNotificationCenter defaultCenter]
				addObserver:self
				   selector:@selector(parentViewChanged:)
					   name:NSViewFrameDidChangeNotification
					 object:[parentWindow contentView]];
		}
		
	}
	
	
    return self;
}

- (void) setMessage:(NSString *)msg
{
	[[self contentView] setMessage:msg];
}

- (NSString *) message
{
	return [[self contentView] message];
}

- (void) setValue:(float) p
{
	[(ProgressView*)[self contentView] setValue:p];
}

- (void) reposition
{
	NSWindow * parentWindow;
	NSRect parentWindowFrame;
	NSRect frame = NSMakeRect(0, 0, 260, 72);
	
	parentWindow = [self parentWindow];
	parentWindowFrame = [parentWindow frame];
	
	// Position myself to the center of the parent window...
	frame.origin.x = parentWindowFrame.origin.x + parentWindowFrame.size.width * 0.5 - frame.size.width * 0.5;
	frame.origin.y = parentWindowFrame.origin.y + parentWindowFrame.size.height * 0.5 - frame.size.height * 0.5;
		
	[self setFrame:frame display:YES];
    
    [self setAlphaValue:[parentWindow alphaValue]];
}

- (void)parentViewChanged:(NSNotification *)notification
{
	[self reposition];
}

- (BOOL) canBecomeKeyWindow
{
    return NO;
}

- (BOOL) canBecomeMainWindow
{
    return NO;
}

- (void) dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self
													name:NSViewFrameDidChangeNotification
												  object:[[self parentWindow] contentView]];
	
	[super dealloc];
}

- (void) close
{
	NSDate * date = [NSDate date];
    NSWindow * parentWindow = [self parentWindow];
	
	[self display];
	
	alpha = 1.0;
	
	while(1)
	{
		alpha = 1.0 - (-1.0 * [date timeIntervalSinceNow]);
		
        [self setAlphaValue:alpha*[parentWindow alphaValue]];
		
		if(alpha < 0.0)
		{
			[[self parentWindow] removeChildWindow:self];
			
			[super close];
			
			return;
		}
	}
}

- (void) closeNow
{
	[[self parentWindow] removeChildWindow:self];
	
	[super close];
}

@end