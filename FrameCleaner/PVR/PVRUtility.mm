//
//  PVRUtility.m
//  Planetscapes
//
//  Created by Rocco Bowling on 11/10/10.
//  Copyright 2010 Chimera Software. All rights reserved.
//

#import "PVRUtility.h"
#include "PVRTexLib.h"

using namespace pvrtexlib;

static NSLock * fileLock = NULL;

@implementation PVRUtility

#pragma mark -

NSInteger RunTask(NSString *launchPath, NSArray *arguments, NSString *workingDirectoryPath, NSDictionary *environment, NSData *stdinData, NSData **stdoutDataPtr, NSData **stderrDataPtr)
{
    if (![[NSFileManager defaultManager] fileExistsAtPath:launchPath]) {
        return -1;
    }
        
    NSTask *task = [[NSTask alloc] init];
    
    [task setLaunchPath:launchPath];
    [task setArguments:arguments];
    
    // Configure the environment
    
    if (environment) {
        NSMutableDictionary *mutableEnv = [environment mutableCopy];
        [mutableEnv setObject:@"true" forKey:@"COPY_EXTENDED_ATTRIBUTES_DISABLE"];
        [task setEnvironment:mutableEnv];
        [mutableEnv release];
    } else {
        // Make sure COPY_EXTENDED_ATTRIBUTES_DISABLE is set in the current environment, which will be inherited by the task
        setenv("COPY_EXTENDED_ATTRIBUTES_DISABLE", "true", 1);
    }
    
    if (workingDirectoryPath) {
        [task setCurrentDirectoryPath:workingDirectoryPath];
    } else {
        [task setCurrentDirectoryPath:@"/tmp"];
    }
    
    NSPipe *stdinPipe = nil;
    NSPipe *stdoutPipe = nil;
    NSPipe *stderrPipe = nil;
    
    if (stdinData) {
        stdinPipe = [[[NSPipe alloc] init] autorelease];
        [task setStandardInput:stdinPipe];
    } else {
        [task setStandardInput:[NSFileHandle fileHandleWithNullDevice]];
    }
	
    if (stdoutDataPtr != NULL) {
        stdoutPipe = [[[NSPipe alloc] init] autorelease];
        [task setStandardOutput:stdoutPipe];
    } else {
        [task setStandardOutput:[NSFileHandle fileHandleWithNullDevice]];
    }
    
    if (stderrDataPtr != NULL) {
        stderrPipe = [[[NSPipe alloc] init] autorelease];
        [task setStandardError:stderrPipe];
    } else {
        [task setStandardError:[NSFileHandle fileHandleWithNullDevice]];
    }
    
    [task launch];
    
    if (stdinPipe) {
        NS_DURING
        if ([stdinData length] > 0) {
            [[stdinPipe fileHandleForWriting] writeData:stdinData];
        }
		[[stdinPipe fileHandleForWriting] closeFile];
        NS_HANDLER
        NS_ENDHANDLER
    }
    
    NSData *stdoutData = nil;
    NSData *stderrData = nil;
	
    if (stdoutPipe) {
        NS_DURING
        stdoutData = [[stdoutPipe fileHandleForReading] readDataToEndOfFile];
        NS_HANDLER
        NS_ENDHANDLER
    }
    
    if (stderrPipe) {
        NS_DURING
        stderrData = [[stderrPipe fileHandleForReading] readDataToEndOfFile];
        NS_HANDLER
        NS_ENDHANDLER
    }
	
    @try
    {
        if([task isRunning])
        {
            [task waitUntilExit];
        }
    }
    @catch(NSException *e)
    {
        
    }
	
    NSInteger status = [task terminationStatus];
	
    [task release];
    task = nil;
	
    if (stdoutDataPtr != NULL) {
        *stdoutDataPtr = stdoutData;
    }
    
    if (stderrDataPtr != NULL) {
        *stderrDataPtr = stderrData;
    }
        
    return status;
}

+ (void) initialize
{
	fileLock = [[NSLock alloc] init];
}

+ (NSData *) DecompressPVRData:(NSData *)data
{
	PVRTRY
	{
		// get the utilities instance
		//PVRTextureUtilities *PVRU = PVRTextureUtilities::getPointer();
		PVRTextureUtilities PVRU = PVRTextureUtilities();
		
		// open and reads a pvr texture from the file location specified by strFilePath
		CPVRTexture sOriginalTexture((const uint8* const )[data bytes]);
		
		
		if(sOriginalTexture.getPixelType() == OGL_RGBA_4444 ||
		   sOriginalTexture.getPixelType() == OGL_RGBA_8888)
		{
			CPVRTextureData& uncompressedData = sOriginalTexture.getData();
			return [NSData dataWithBytes:uncompressedData.getData() length:uncompressedData.getDataSize()];
		}
		
		// declare an empty texture to decompress into
		CPVRTexture sDecompressedTexture;
		
		// decompress the compressed texture into this texture
		PVRU.DecompressPVR(sOriginalTexture, sDecompressedTexture);
		
		CPVRTextureData& uncompressedData = sDecompressedTexture.getData();
		
		return [NSData dataWithBytes:uncompressedData.getData() length:uncompressedData.getDataSize()];
		
	} PVRCATCH(myException) {
		// handle any exceptions here
		printf("Exception in example 1: %s \n",myException.what());
	}
	
	return NULL;
}

+ (NSData *) CompressDataLossy:(NSData *)data
						OfSize:(NSSize)size
                   AltTileSize:(int*)altTileSize
                 WithWeighting:(NSString *)weighting
                   WithSamples:(int)samplesPerPixel
{
	NSString * fileName = [NSString stringWithFormat:@"/tmp/tmp%0x8", (int)data];
	NSString * pngName = [fileName stringByAppendingString:@".png"];
    NSString * pow2Name = [fileName stringByAppendingString:@".pow2"];
	NSString * pvrName = [fileName stringByAppendingString:@".pvr"];
	
	NSBitmapImageRep * bitmap_rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
																			pixelsWide:size.width
																			pixelsHigh:size.height
																		 bitsPerSample:8
																	   samplesPerPixel:samplesPerPixel
																			  hasAlpha:(samplesPerPixel == 4)
																			  isPlanar:NO
																		colorSpaceName:NSDeviceRGBColorSpace
																		  bitmapFormat:NSAlphaNonpremultipliedBitmapFormat
																		   bytesPerRow:size.width * samplesPerPixel
																		  bitsPerPixel:samplesPerPixel * 8];
	
	memcpy([bitmap_rep bitmapData], [data bytes], [data length]);
	
	[[bitmap_rep representationUsingType:NSPNGFileType
							  properties:[NSDictionary dictionary]] writeToFile:pngName
                                atomically:NO];
    
    // Convert that PNG to a power of two size...
    int pow2Width = 2048, pow2Height = 2048;
	while((size.width*2) < pow2Width)
	{
		pow2Width /= 2;
	}
	while((size.height*2) < pow2Height)
	{
		pow2Height /= 2;
	}
    if(pow2Width > pow2Height)
        pow2Height = pow2Width;
    if(pow2Height > pow2Width)
        pow2Width = pow2Height;
    	    
    RunTask(@"/usr/bin/sips",
            [NSArray arrayWithObjects:@"--resampleHeightWidth", [NSString stringWithFormat:@"%d", pow2Height], [NSString stringWithFormat:@"%d", pow2Width], @"--out", pow2Name, pngName, NULL],
            NULL, NULL, NULL, NULL, NULL);
    
    *altTileSize = pow2Height;
    
	// Convert to PVR
	NSString * launchPath = [NSString stringWithFormat:@"%@/texturetool", [[NSBundle mainBundle] resourcePath]];
	NSArray * arguments = [NSArray arrayWithObjects:
						   @"-e", @"PVRTC", @"--bits-per-pixel-2", weighting, @"--alpha-is-opacity", @"-f", @"PVR",
						   pow2Name, @"-o", pvrName, 
						   NULL];
	
	RunTask(launchPath, arguments, NULL, NULL, NULL, NULL, NULL);
	
	[bitmap_rep release];
	
	NSData * compressedData = [NSData dataWithContentsOfFile:pvrName];
	
	[[NSFileManager defaultManager] removeItemAtPath:pngName error:NULL];
    [[NSFileManager defaultManager] removeItemAtPath:pow2Name error:NULL];
	[[NSFileManager defaultManager] removeItemAtPath:pvrName error:NULL];
	
	return compressedData;
}

@end
