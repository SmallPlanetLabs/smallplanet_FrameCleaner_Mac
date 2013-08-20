//
//  FCAppDelegate.m
//  FrameCleaner
//
//  Created by Rocco Bowling on 5/6/13.
//  Copyright (c) 2013 Rocco Bowling. All rights reserved.
//

#import "FCAppDelegate.h"
#import "NSDataAdditions.h"
#import "PVRUtility.h"
#import "ProgressWindow.h"
#import "png.h"
#import <CoreGraphics/CoreGraphics.h>

static BOOL gShouldTrimImages = NO;
static BOOL gShouldRemoveDuplicates = NO;
static BOOL gCompareUsingMD5 = NO;
static CGPoint globalMin, globalMax;

#define kSampleSize 1024*1024
#define kSampleSeed kSampleSize
#define SHOULD_SAMPLE() (pixelsWide*pixelsHigh*samplesPerPixel > kSampleSize)

extern NSInteger RunTask(NSString *launchPath, NSArray *arguments, NSString *workingDirectoryPath, NSDictionary *environment, NSData *stdinData, NSData **stdoutDataPtr, NSData **stderrDataPtr);

@interface FCImage : NSObject
{
    NSString * sourceFile;
    NSString * destinationFile;
    NSInteger index;
    
    NSInteger pixelsWide;
    NSInteger pixelsHigh;
    NSInteger samplesPerPixel;
    
    NSData * storePixelData;
    
    NSString * md5;
    
    unsigned char sampleSet[kSampleSize+12];
}

@property (nonatomic, retain) NSString * sourceFile;
@property (nonatomic, retain) NSString * destinationFile;
@property (nonatomic, retain) NSString * md5;
@property (nonatomic, assign) NSInteger index;

- (NSData *) subtract:(FCImage*)other;
- (CGSize) size;
+ (void) dumpData:(NSData*)data size:(CGSize)size;
- (BOOL) compare:(FCImage*)other pixelsWithMin:(CGPoint)min andMax:(CGPoint)max;

@end

@implementation FCImage

@synthesize sourceFile, destinationFile, index, md5;

#define SKIPPIX 4
+ (void) dumpData:(NSData*)data size:(CGSize)size
{
    unsigned char * ptr = (unsigned char*)[data bytes];
    for (int i=0;i<size.height;i+=SKIPPIX)
    {
        for (int j=0;j<size.width;j+=SKIPPIX)
        {
            printf("%s", (*ptr+*(ptr+1)+*(ptr+2) > 0 ? "*" : " "));
            ptr+=3*SKIPPIX;
        }
        int increment = 3*size.width*(SKIPPIX-1);
        ptr+=increment;
        printf("\n");
    }
    printf("\n");
}

- (id) initWithSource:(NSString *)sourcePath
{
    self = [super init];
    if(self)
    {
        self.sourceFile = sourcePath;
        
        NSData * stdoutData = NULL;
        
        RunTask(@"/sbin/md5",
                [NSArray arrayWithObjects:@"-q", sourcePath, NULL],
                NULL, NULL, NULL, &stdoutData, NULL);
        
        self.md5 = [[[NSString alloc] initWithData:stdoutData encoding:NSUTF8StringEncoding] autorelease];
        
    }
    
    return self;
}

#pragma mark -

- (void) exportLZ4To:(NSString *)exportPath
           withQueue:(NSOperationQueue *)queue
{
    // We want to prepend the width and height to the pixel data, unsigned shorts for each
    unsigned short width = 0;
    unsigned short height = 0;
    NSData * pixels = NULL;
    
    if(gShouldTrimImages)
    {
        width = globalMax.x-globalMin.x;
        height = globalMax.y-globalMin.y;
        pixels = [self croppedPixelsWithMin:globalMin
                                     andMax:globalMax];
    }
    else
    {
        pixels = [self pixelData];
        width = pixelsWide;
        height = pixelsHigh;
    }
    
    [queue addOperationWithBlock:^{
        NSString * ePath = [exportPath stringByAppendingPathExtension:@"lz4"];
        
        @autoreleasepool {
            NSMutableData * data = [NSMutableData data];
            
            [data appendBytes:&width length:2];
            [data appendBytes:&height length:2];
            [data appendData:pixels];
            
            [[data lz4Deflate] writeToFile:ePath atomically:NO];
        }
    }];
}

- (void) exportPNGTo:(NSString *)exportPath
           withQueue:(NSOperationQueue *)queue
{
    // We want to prepend the width and height to the pixel data, unsigned shorts for each
    unsigned short width = 0;
    unsigned short height = 0;
    NSData * pixels = NULL;
    
    if(gShouldTrimImages)
    {
        width = globalMax.x-globalMin.x;
        height = globalMax.y-globalMin.y;
        pixels = [self croppedPixelsWithMin:globalMin
                                     andMax:globalMax];
    }
    else
    {
        pixels = [self pixelData];
        width = pixelsWide;
        height = pixelsHigh;
    }
    
    [queue addOperationWithBlock:^{
        NSString * ePath = [exportPath stringByAppendingPathExtension:@"png"];
        
        @autoreleasepool {
            
            unsigned char * bufferPtr = (unsigned char *)[pixels bytes];
            BOOL hasAlpha = ((width * height * 4) == [pixels length]);
            int samples = hasAlpha ? 4 : 3;
            
            NSBitmapImageRep * bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:&bufferPtr
                                                                                pixelsWide:width
                                                                                pixelsHigh:height
                                                                             bitsPerSample:8
                                                                           samplesPerPixel:samples
                                                                                  hasAlpha:hasAlpha
                                                                                  isPlanar:NO
                                                                            colorSpaceName:NSDeviceRGBColorSpace
                                                                              bitmapFormat:NSAlphaNonpremultipliedBitmapFormat
                                                                               bytesPerRow:width*samples
                                                                              bitsPerPixel:8*samples];
            
            NSData * pngData = [bitmap representationUsingType:NSPNGFileType properties:[NSDictionary dictionary]];
            
            [bitmap release];
            
            NSString * tempPath = [ePath stringByAppendingPathExtension:@"orig"];

            [pngData writeToFile:tempPath atomically:NO];
            
            // Run through PNG crush...
            NSString * launchPath = [NSString stringWithFormat:@"%@/pngcrush", [[NSBundle mainBundle] resourcePath]];
            NSArray * arguments = [NSArray arrayWithObjects:
                                   @"-q", @"-iphone", @"-f", @"0",
                                   tempPath, ePath,
                                   NULL];
            
            RunTask(launchPath, arguments, NULL, NULL, NULL, NULL, NULL);
            
            [[NSFileManager defaultManager] removeItemAtPath:tempPath error:NULL];

        }
    }];
}

- (void) exportPNGQuantTo:(NSString *)exportPath
                withQueue:(NSOperationQueue *)queue
            withTableSize:(int)tableSize
{
    // We want to prepend the width and height to the pixel data, unsigned shorts for each
    unsigned short width = 0;
    unsigned short height = 0;
    NSData * pixels = NULL;
    
    if(gShouldTrimImages)
    {
        width = globalMax.x-globalMin.x;
        height = globalMax.y-globalMin.y;
        pixels = [self croppedPixelsWithMin:globalMin
                                     andMax:globalMax];
    }
    else
    {
        pixels = [self pixelData];
        width = pixelsWide;
        height = pixelsHigh;
    }
    
    [queue addOperationWithBlock:^{
        NSString * ePath = [exportPath stringByAppendingPathExtension:@"png"];
        
        @autoreleasepool {
            
            unsigned char * bufferPtr = (unsigned char *)[pixels bytes];
            BOOL hasAlpha = ((width * height * 4) == [pixels length]);
            int samples = hasAlpha ? 4 : 3;
            
            NSBitmapImageRep * bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:&bufferPtr
                                                                                pixelsWide:width
                                                                                pixelsHigh:height
                                                                             bitsPerSample:8
                                                                           samplesPerPixel:samples
                                                                                  hasAlpha:hasAlpha
                                                                                  isPlanar:NO
                                                                            colorSpaceName:NSDeviceRGBColorSpace
                                                                              bitmapFormat:NSAlphaNonpremultipliedBitmapFormat
                                                                               bytesPerRow:width*samples
                                                                              bitsPerPixel:8*samples];
            
            NSData * pngData = [bitmap representationUsingType:NSPNGFileType properties:[NSDictionary dictionary]];
            
            [bitmap release];
            
            [pngData writeToFile:ePath atomically:NO];
            
            // Run through PNG crush...
            NSString * launchPath = [NSString stringWithFormat:@"%@/pngnq", [[NSBundle mainBundle] resourcePath]];
            NSArray * arguments = [NSArray arrayWithObjects:
                                   @"-s", @"1", @"-n", [NSString stringWithFormat:@"%d", tableSize],
                                   ePath, NULL];
            
            RunTask(launchPath, arguments, NULL, NULL, NULL, NULL, NULL);
            
            
            [[NSFileManager defaultManager] removeItemAtPath:ePath error:NULL];
            
            NSString * exportedPath = [NSString stringWithFormat:@"%@-nq8.png", [ePath stringByDeletingPathExtension]];
            [[NSFileManager defaultManager] moveItemAtPath:exportedPath toPath:ePath error:NULL];
            
        }
    }];
}

- (void) exportPVRGradientTo:(NSString *)exportPath
                   withQueue:(NSOperationQueue *)queue
{
    // We want to prepend the width and height to the pixel data, unsigned shorts for each
    unsigned short width = 0;
    unsigned short height = 0;
    NSData * pixels = NULL;
    
    if(gShouldTrimImages)
    {
        width = globalMax.x-globalMin.x;
        height = globalMax.y-globalMin.y;
        pixels = [self croppedPixelsWithMin:globalMin
                                     andMax:globalMax];
    }
    else
    {
        pixels = [self pixelData];
        width = pixelsWide;
        height = pixelsHigh;
    }
    
    [queue addOperationWithBlock:^{
        NSString * ePath = [exportPath stringByAppendingPathExtension:@"pvr"];
        
        @autoreleasepool {
            int altSize;
            NSData * pvrData = [PVRUtility CompressDataLossy:pixels
                                                      OfSize:NSMakeSize(width, height)
                                                 AltTileSize:&altSize
                                               WithWeighting:@"--channel-weighting-linear"
                                                 WithSamples:samplesPerPixel];
            
            [pvrData writeToFile:ePath atomically:NO];
        }
    }];
}

- (void) exportPVRPhotoTo:(NSString *)exportPath
                withQueue:(NSOperationQueue *)queue
{
    // We want to prepend the width and height to the pixel data, unsigned shorts for each
    unsigned short width = 0;
    unsigned short height = 0;
    NSData * pixels = NULL;
    
    if(gShouldTrimImages)
    {
        width = globalMax.x-globalMin.x;
        height = globalMax.y-globalMin.y;
        pixels = [self croppedPixelsWithMin:globalMin
                                     andMax:globalMax];
    }
    else
    {
        pixels = [self pixelData];
        width = pixelsWide;
        height = pixelsHigh;
    }
    
    [queue addOperationWithBlock:^{
        NSString * ePath = [exportPath stringByAppendingPathExtension:@"pvr"];
        
        @autoreleasepool {
            int altSize;
            NSData * pvrData = [PVRUtility CompressDataLossy:pixels
                                                      OfSize:NSMakeSize(width, height)
                                                 AltTileSize:&altSize
                                               WithWeighting:@"--channel-weighting-perceptual"
                                                 WithSamples:samplesPerPixel];
            
            [pvrData writeToFile:ePath atomically:NO];
        }
    }];
}

- (void) exportSP1To:(NSString *)exportPath
           withQueue:(NSOperationQueue *)queue
       withTableSize:(int)tableSize
{
    // SP1: a format which uses paletted image coloring (1 byte pixels) and is rendered with
    // a custom fragment shader with the color palette embedded it in (so the in memory
    // texture is still the 1 byte per pixel format). This allows for super-fast loading
    // (no decompression required) and fast rendering
    //
    // To do this, we run pngnq on our source image, read in the quantized image, extract
    // the color palette and 1 byte image array from that, and output the image.sp1 and
    // image.fsh
    unsigned short width = 0;
    unsigned short height = 0;
    NSData * pixels = NULL;
    
    if(gShouldTrimImages)
    {
        width = globalMax.x-globalMin.x;
        height = globalMax.y-globalMin.y;
        pixels = [self croppedPixelsWithMin:globalMin
                                     andMax:globalMax];
    }
    else
    {
        pixels = [self pixelData];
        width = pixelsWide;
        height = pixelsHigh;
    }
    
    [queue addOperationWithBlock:^{
        NSString * ePath = [exportPath stringByAppendingPathExtension:@"png"];
        
        @autoreleasepool {
            
            unsigned char * bufferPtr = (unsigned char *)[pixels bytes];
            BOOL hasAlpha = ((width * height * 4) == [pixels length]);
            int samples = hasAlpha ? 4 : 3;
            
            NSBitmapImageRep * bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:&bufferPtr
                                                                                pixelsWide:width
                                                                                pixelsHigh:height
                                                                             bitsPerSample:8
                                                                           samplesPerPixel:samples
                                                                                  hasAlpha:hasAlpha
                                                                                  isPlanar:NO
                                                                            colorSpaceName:NSDeviceRGBColorSpace
                                                                              bitmapFormat:NSAlphaNonpremultipliedBitmapFormat
                                                                               bytesPerRow:width*samples
                                                                              bitsPerPixel:8*samples];
            
            NSData * pngData = [bitmap representationUsingType:NSPNGFileType properties:[NSDictionary dictionary]];
            
            [bitmap release];
            
            NSString * tempPath = [ePath stringByAppendingPathExtension:@"orig"];
            
            [pngData writeToFile:tempPath atomically:NO];
            
            // Run through PNG crush...
            NSString * launchPath = [NSString stringWithFormat:@"%@/pngnq", [[NSBundle mainBundle] resourcePath]];
            NSArray * arguments = [NSArray arrayWithObjects:
                                   @"-s", @"1", @"-n", [NSString stringWithFormat:@"%d", tableSize],
                                   tempPath, ePath, NULL];
            
            RunTask(launchPath, arguments, NULL, NULL, NULL, NULL, NULL);
            
            [[NSFileManager defaultManager] removeItemAtPath:tempPath error:NULL];
            
            
            // The file we want to process is at ePath; get a source RGBA bytes from the file.
            
            
        }
    }];
}

#pragma mark -

- (unsigned char *) sampleSet
{
    return sampleSet;
}

- (BOOL) compare:(FCImage*)other
{
    if([md5 isEqualToString:[other md5]])
    {
        return YES;
    }
    
    if(gCompareUsingMD5)
    {
        return NO;
    }
    
    @autoreleasepool {
        
        NSData * pixelDataA = [self pixelData];
        
        // quick sample check; is they are not the same return NO
        if(SHOULD_SAMPLE())
        {
            unsigned char * ptr1 = [self sampleSet];
            unsigned char * ptr2 = [other sampleSet];
            
            for(int i = 0; i < kSampleSize; i++)
            {
                if(abs(ptr1[i] - ptr2[i]) > 20)
                    return NO;
            }
        }
                
        NSData * pixelDataB = [other pixelData];
        
        if([pixelDataA length] != [pixelDataB length])
            return NO;
        
        // run through all pixels and look for equivalence
        const unsigned char * ptrA = (const unsigned char *)[pixelDataA bytes];
        const unsigned char * ptrB = (const unsigned char *)[pixelDataB bytes];
        NSUInteger length = [pixelDataA length];
        
        for(NSUInteger i = 0; i < length; i++)
        {
            if(abs(*ptrA - *ptrB) > 20)
                return NO;
            ptrA++;
            ptrB++;
        }
        
        return YES;
    }
    
    return NO;
}

- (BOOL) compare:(FCImage*)other pixelsWithMin:(CGPoint)min andMax:(CGPoint)max
{
    if([md5 isEqualToString:[other md5]])
    {
        return YES;
    }
    
    int newWidth = max.x-min.x;
    int newHeight = max.y-min.y;
    
    const unsigned char * basePtr = (const unsigned char *)[[self pixelData] bytes];
    const unsigned char * basePtr2 = (const unsigned char *)[[other pixelData] bytes];
    const unsigned char * ptr;
    const unsigned char * ptr2;
    
    for(int y = min.y; y < min.y+newHeight; y++)
    {
        for(int x = min.x; x < min.x+newWidth; x++)
        {
            ptr = basePtr + (y * pixelsWide * samplesPerPixel) + (x * samplesPerPixel);
            ptr2 = basePtr2 + (y * pixelsWide * samplesPerPixel) + (x * samplesPerPixel);
            for (int i = 0; i < samplesPerPixel; i++)
            {
                if(abs(ptr[i] - ptr2[i]) > 20) return NO;
            }
        }
    }

    return YES;
}

- (NSData *) subtract:(FCImage*)other
{
    NSData * pixelData1 = [self pixelData];
    NSData * pixelData2 = [other pixelData];
    unsigned char * ptr1 = (unsigned char*)[pixelData1 bytes];
    unsigned char * ptr2 = (unsigned char*)[pixelData2 bytes];
    
    unsigned char * newBasePtr = (unsigned char *)malloc([pixelData1 length]);
    unsigned char * newPtr = newBasePtr;
    
    for(int i=0; i<[pixelData1 length]; i++)
    {
        *newPtr = abs(*ptr1 - *ptr2);
        ptr1++;
        ptr2++;
        newPtr++;
    }
    
    return [NSData dataWithBytesNoCopy:newBasePtr length:[pixelData1 length] freeWhenDone:true];
}

- (NSData *) croppedPixelsWithMin:(CGPoint)min
                           andMax:(CGPoint)max
{
    // Nab the pixel data, crop it, save it as a png, store the new image path
    NSData * pixelDataA = [self pixelData];
    
    // new pixel data
    int newWidth = max.x-min.x;
    int newHeight = max.y-min.y;
    
    unsigned char * newBasePtr = (unsigned char *)malloc(newWidth*newHeight*4);
    unsigned char * newPtr;
    
    const unsigned char * basePtr = (const unsigned char *)[pixelDataA bytes];
    const unsigned char * ptr;
    
    for(int y = min.y; y < min.y+newHeight; y++)
    {
        for(int x = min.x; x < min.x+newWidth; x++)
        {
            ptr = basePtr + (y * pixelsWide * samplesPerPixel) + (x * samplesPerPixel);
            newPtr = newBasePtr + ((y-(int)min.y) * newWidth * samplesPerPixel) + ((x-(int)min.x) * samplesPerPixel);
            
            newPtr[0] = ptr[0];
            newPtr[1] = ptr[1];
            newPtr[2] = ptr[2];
            newPtr[3] = ptr[3];
        }
    }
    
    return [NSData dataWithBytesNoCopy:newBasePtr length:(newWidth*newHeight*samplesPerPixel) freeWhenDone:YES];
}

- (void) trimmedValuesWithMin:(CGPoint*)min
                       andMax:(CGPoint*)max
{
    @autoreleasepool
    {
        NSData * pixelDataA = [self pixelData];
        const unsigned char * basePtr = (const unsigned char *)[pixelDataA bytes];
        const unsigned char * ptr;
        min->x = 9999999999;
        min->y = 9999999999;
        max->x = 0;
        max->y = 0;
        
        // Find the minimum y
        for(int y = 0; y < pixelsHigh; y++)
        {
            for(int x = 0; x < pixelsWide; x++)
            {
                ptr = basePtr + (y * pixelsWide * samplesPerPixel) + (x * samplesPerPixel);

                if(ptr[3] != 0)
                {
                    min->y = y;
                    y = pixelsHigh;
                    break;
                }
            }
        }
        
        // Find the maximum y
        for(int y = pixelsHigh-1; y >= 0; y--)
        {
            for(int x = 0; x < pixelsWide; x++)
            {
                ptr = basePtr + (y * pixelsWide * samplesPerPixel) + (x * samplesPerPixel);
                
                if(ptr[3] != 0)
                {
                    max->y = y;
                    y = -1;
                    break;
                }
            }
        }
        
        // Find the minimum x
        for(int x = 0; x < pixelsWide; x++)
        {
            for(int y = 0; y < pixelsHigh; y++)
            {
                ptr = basePtr + (y * pixelsWide * samplesPerPixel) + (x * samplesPerPixel);
                
                if(ptr[3] != 0)
                {
                    min->x = x;
                    x = pixelsWide;
                    break;
                }
            }
        }
        
        // Find the maximum x
        for(int x = pixelsWide-1; x >= 0; x--)
        {
            for(int y = 0; y < pixelsHigh; y++)
            {
                ptr = basePtr + (y * pixelsWide * samplesPerPixel) + (x * samplesPerPixel);
                
                if(ptr[3] != 0)
                {
                    max->x = x;
                    x = -1;
                    break;
                }
            }
        }
        
        [self dropMemory];
    }
}



typedef struct
{
    unsigned char* data;
    int size;
    int offset;
}tImageSource;

static void pngReadCallback(png_structp png_ptr, png_bytep data, png_size_t length)
{
    tImageSource* isource = (tImageSource*)png_get_io_ptr(png_ptr);
    
    if((int)(isource->offset + length) <= isource->size)
    {
        memcpy(data, isource->data+isource->offset, length);
        isource->offset += length;
    }
    else
    {
        png_error(png_ptr, "pngReaderCallback failed");
    }
}

- (void) dropMemory
{
    [storePixelData release];
    storePixelData = NULL;
}

- (CGSize) size
{
    return CGSizeMake(pixelsWide, pixelsHigh);
}

- (void) makeTransparentRect:(CGRect)rect
{
    NSData *data = [self pixelData];
    unsigned char *ptr = (unsigned char*)[data bytes];
    long rowSize = pixelsWide * 4;
    for (int x=rect.origin.x; x<rect.origin.x+rect.size.width; x++)
    {
        for (int y=pixelsHigh-rect.origin.y-rect.size.height; y<pixelsHigh-rect.origin.y; y++)
        {
            *(ptr + y*rowSize + x*4 + 3) = 0;
//            *(ptr + y*rowSize + x*4 + 3) = 128;
//            *(ptr + y*rowSize + x*4 + 0) = 255;
        }
    }
}

- (NSData *) pixelData
{
    if(storePixelData)
        return storePixelData;
    
    
    
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
    
    // NSImage sucks in regards to premultiplication of alpha.  So, lets save this out to PNG
    // then load using libpng, and read the raw bytes that way
    NSData * pngData = [NSData dataWithContentsOfFile:sourceFile];
    
    const void * pData = [pngData bytes];
    int nDatalen = [pngData length];
        
    //bool CCImage::_initWithPngData(void * pData, int nDatalen)
    {
        // length of bytes to check if it is a valid png file
#define PNGSIGSIZE  8
        bool bRet = false;
        png_byte        header[PNGSIGSIZE]   = {0};
        png_structp     png_ptr     =   0;
        png_infop       info_ptr    = 0;
        
        int m_nWidth;
        int m_nHeight;
        int m_nBitsPerComponent;
        int m_bHasAlpha;
        int m_nChannels;
        unsigned char * m_pData = NULL;
        
        do
        {
            // png header len is 8 bytes
            if(nDatalen < PNGSIGSIZE)
                break;
            
            // check the data is png or not
            memcpy(header, pData, PNGSIGSIZE);
            if(png_sig_cmp(header, 0, PNGSIGSIZE))
                break;
            
            // init png_struct
            png_ptr = png_create_read_struct(PNG_LIBPNG_VER_STRING, 0, 0, 0);
            if(! png_ptr)
                break;
            
            // init png_info
            info_ptr = png_create_info_struct(png_ptr);
            if(!info_ptr)
                break;
            
            // set the read call back function
            tImageSource imageSource;
            imageSource.data    = (unsigned char*)pData;
            imageSource.size    = nDatalen;
            imageSource.offset  = 0;
            png_set_read_fn(png_ptr, &imageSource, pngReadCallback);
            
            // read png header info
            
            // read png file info
            png_read_info(png_ptr, info_ptr);
            
            m_nWidth = png_get_image_width(png_ptr, info_ptr);
            m_nHeight = png_get_image_height(png_ptr, info_ptr);
            m_nBitsPerComponent = png_get_bit_depth(png_ptr, info_ptr);
            png_uint_32 channels = png_get_channels(png_ptr, info_ptr);
            png_uint_32 color_type = png_get_color_type(png_ptr, info_ptr);
            
            // only support color type: PNG_COLOR_TYPE_RGB, PNG_COLOR_TYPE_RGB_ALPHA PNG_COLOR_TYPE_PALETTE
            // and expand bit depth to 8
            if(color_type == PNG_COLOR_TYPE_RGB ||
               color_type == PNG_COLOR_TYPE_RGB_ALPHA)
            {
                
                
                if (m_nBitsPerComponent == 16)
                {
                    png_set_strip_16(png_ptr);
                    m_nBitsPerComponent = 8;
                }
                
                m_nChannels = 3;
                m_bHasAlpha = (color_type & PNG_COLOR_MASK_ALPHA) ? true : false;
                if (m_bHasAlpha)
                {
                    m_nChannels = channels = 4;
                }
                
                // read png data
                // m_nBitsPerComponent will always be 8
                m_pData = (unsigned char *)malloc(m_nWidth * m_nHeight * channels);
                memset(m_pData, 255, m_nWidth * m_nHeight * channels);
                
                png_bytep* row_pointers = (png_bytep*)malloc(sizeof(png_bytep)*m_nHeight);
                if (row_pointers)
                {
                    const unsigned int stride = m_nWidth * channels;
                    for (unsigned short i = 0; i < m_nHeight; ++i)
                    {
                        png_uint_32 q = i * stride;
                        row_pointers[i] = (png_bytep)m_pData + q;
                    }
                    png_read_image(png_ptr, row_pointers);
                    
                    free(row_pointers);
                    bRet = true;
                }
            }
        } while (0);
        
        if(m_pData)
        {
            pixelsWide = m_nWidth;
            pixelsHigh = m_nHeight;
            samplesPerPixel = m_nChannels;
            
            // create a sample set for quick analysis...
            if(SHOULD_SAMPLE())
            {
                srand(kSampleSeed);
                int totalSize = (m_nWidth * m_nHeight * m_nChannels);
                for(int i = 0; i < kSampleSize; i++)
                {
                    int k = rand() % totalSize;
                    sampleSet[i] = m_pData[k];
                }
            }
            
            @autoreleasepool
            {
                storePixelData = [[NSData dataWithBytesNoCopy:m_pData length:(m_nWidth * m_nHeight * m_nChannels) freeWhenDone:YES] retain];
            }
        }
    }
    
    [pool release];
    
    
    return storePixelData;
}

@end

@interface NSMutableArray (ArchUtils_Shuffle)
- (void)shuffle;
@end

// Chooses a random integer below n without bias.
// Computes m, a power of two slightly above n, and takes random() modulo m,
// then throws away the random number if it's between n and m.
// (More naive techniques, like taking random() modulo n, introduce a bias
// towards smaller numbers in the range.)
static NSUInteger random_below(NSUInteger n) {
    NSUInteger m = 1;
    
    // Compute smallest power of two greater than n.
    // There's probably a faster solution than this loop, but bit-twiddling
    // isn't my specialty.
    do {
        m <<= 1;
    } while(m < n);
    
    NSUInteger ret;
    
    do {
        ret = random() % m;
    } while(ret >= n);
    
    return ret;
}

@implementation NSMutableArray (ArchUtils_Shuffle)

- (void)shuffle {
    // http://en.wikipedia.org/wiki/Knuth_shuffle
    
    for(NSUInteger i = [self count]; i > 1; i--) {
        NSUInteger j = random_below(i);
        [self exchangeObjectAtIndex:i-1 withObjectAtIndex:j];
    }
}

@end

@interface FCRegion : NSObject {
    CGRect bounds;
    NSInteger numberOfPoints;
}
- (CGRect) bounds;
- (CGRect) unionWithBounds:(CGRect)rect;
- (CGFloat) unionAreaWithBounds:(CGRect)rect;
- (BOOL) containsPoint:(CGPoint)point withInset:(CGFloat)inset;
- (CGFloat) areaWithPoint:(CGPoint)point;
- (CGFloat) area;
- (CGFloat) maxSideWithPoint:(CGPoint)point;
- (void) setBounds:(CGRect)_bounds;
- (void) mergeWithRegion:(FCRegion *)region;
- (void) reduceIfOverlaps:(FCRegion *)region;
- (void) expandBoundsBy:(CGFloat)pixels toMaxSize:(CGSize)size;
@end

@implementation FCRegion

- (id) init
{
    self = [super init];
    if(self)
    {
        bounds = CGRectNull;
        numberOfPoints = 0;
    }
    return self;
}

- (BOOL) containsPoint:(CGPoint)point withInset:(CGFloat)inset
{
    return (CGRectContainsPoint(CGRectInset(bounds,inset,inset), point));
}

- (CGFloat) area
{
    return bounds.size.width * bounds.size.height;
}

- (CGFloat) areaWithPoint:(CGPoint)point
{
    CGRect pointRect = CGRectZero;
    pointRect.origin = point;
    pointRect.size = CGSizeMake(1.f,1.f);

    CGRect newBounds = (CGRectIsNull(bounds) ? pointRect : CGRectUnion(bounds, pointRect));
    return newBounds.size.width * newBounds.size.height;
}

- (CGFloat) maxSideWithPoint:(CGPoint)point
{
    CGRect pointRect = CGRectZero;
    pointRect.origin = point;
    pointRect.size = CGSizeMake(1.f,1.f);
    
    CGRect newBounds = (CGRectIsNull(bounds) ? pointRect : CGRectUnion(bounds, pointRect));
    return (newBounds.size.width > newBounds.size.height ? newBounds.size.width : newBounds.size.height);
}

- (void) addPoint:(CGPoint)point
{
    CGRect pointRect = CGRectZero;
    pointRect.origin = point;
    pointRect.size = CGSizeMake(1.f,1.f);

    bounds = (CGRectIsNull(bounds) ? pointRect : CGRectUnion(bounds, pointRect));
    numberOfPoints++;
}

- (NSString *) description
{
    return [NSString stringWithFormat:@"Region bounds {%f,%f; %f,%f} contains %d points", bounds.origin.x,bounds.origin.y,bounds.size.width,bounds.size.height, numberOfPoints];
}

- (CGRect) bounds
{
    return bounds;
}

- (void) expandBoundsBy:(CGFloat)pixels toMaxSize:(CGSize)size
{
    bounds.origin.x -= pixels;
    bounds.origin.x = (bounds.origin.x < 0.f ? 0.f: bounds.origin.x);
    bounds.origin.y -= pixels;
    bounds.origin.y = (bounds.origin.y < 0.f ? 0.f: bounds.origin.y);
    bounds.size.width += 2.f*pixels;
    bounds.size.width = (bounds.size.width > size.width ? size.width : bounds.size.width);
    bounds.size.height += 2.f*pixels;
    bounds.size.height = (bounds.size.height > size.height ? size.height : bounds.size.height);
}

- (void) setBounds:(CGRect)_bounds;
{
    bounds = _bounds;
}

- (NSInteger) numberOfPoints
{
    return numberOfPoints;
}

- (CGRect) unionWithBounds:(CGRect)rect
{
    return CGRectUnion(bounds, bounds);
}

- (CGFloat) unionAreaWithBounds:(CGRect)rect
{
    CGRect total = CGRectUnion(bounds, rect);
    return total.size.width * total.size.height;
}

- (void) mergeWithRegion:(FCRegion *)region
{
    bounds = CGRectUnion(bounds, [region bounds]);
    numberOfPoints += [region numberOfPoints];
}

- (BOOL) overlaps:(FCRegion *)region
{
    CGPoint p1 = CGPointMake(bounds.origin.x, bounds.origin.y);
    CGPoint p2 = CGPointMake(bounds.origin.x, bounds.origin.y + bounds.size.height);
    CGPoint p3 = CGPointMake(bounds.origin.x + bounds.size.width, bounds.origin.y + bounds.size.height);
    CGPoint p4 = CGPointMake(bounds.origin.x + bounds.size.width, bounds.origin.y);
    
    if (CGRectContainsPoint([region bounds], p1) && CGRectContainsPoint([region bounds], p2)) return YES;
    if (CGRectContainsPoint([region bounds], p2) && CGRectContainsPoint([region bounds], p3)) return YES;
    if (CGRectContainsPoint([region bounds], p3) && CGRectContainsPoint([region bounds], p4)) return YES;
    if (CGRectContainsPoint([region bounds], p4) && CGRectContainsPoint([region bounds], p1)) return YES;
    return NO;
}

- (void) reduceIfOverlaps:(FCRegion *)region
{
    CGPoint p1 = CGPointMake(bounds.origin.x, bounds.origin.y);
    CGPoint p2 = CGPointMake(bounds.origin.x, bounds.origin.y + bounds.size.height);
    CGPoint p3 = CGPointMake(bounds.origin.x + bounds.size.width, bounds.origin.y + bounds.size.height);
    CGPoint p4 = CGPointMake(bounds.origin.x + bounds.size.width, bounds.origin.y);
    
    if (CGRectContainsPoint([region bounds], p1) && CGRectContainsPoint([region bounds], p2))
    {
        CGFloat diff = CGRectGetMaxX([region bounds]) - CGRectGetMinX(bounds);
        bounds.origin.x += diff;
        bounds.size.width -= diff;
    }
    if (CGRectContainsPoint([region bounds], p2) && CGRectContainsPoint([region bounds], p3))
    {
        CGFloat diff = CGRectGetMaxY(bounds) - CGRectGetMinY([region bounds]);
        bounds.size.height -= diff;
    }
    if (CGRectContainsPoint([region bounds], p3) && CGRectContainsPoint([region bounds], p4))
    {
        CGFloat diff = CGRectGetMaxX(bounds) - CGRectGetMinX([region bounds]);
        bounds.size.width -= diff;
    }
    if (CGRectContainsPoint([region bounds], p4) && CGRectContainsPoint([region bounds], p1))
    {
        CGFloat diff = CGRectGetMaxY([region bounds]) - CGRectGetMinY(bounds);
        bounds.origin.y += diff;
        bounds.size.height -= diff;
    }
}

@end


@implementation FCAppDelegate

@synthesize trimImagesBtn, removeDuplicatesBtn;
@synthesize exportInfo, exportMatrix, compareUsingMD5, maxSubregions;

int convertDecimalToBaseN(int a, int n)
{
    int k;
    int c;
    k = floor(log10((double) a) / log10((double) n)) + 1;
    c = pow((double) n, (double) k - 1);
    for(int i = 0; i < k;)
    {
        a = a % c;
        k = k - 1;
    }
    return k;
}

// SUBREGION_THRESHOLD compare stored difference of each pixel channel to this, if lower ignore the diff
#define SUBREGION_THRESHOLD 0
// SUBREGION_INSET (negative) expands the bounds of an existing rect when searching for determining if a point should be inside a region
#define SUBREGION_INSET -1
// regions with fewer than MIN_POINTS_PER_SUBREGION will be rejected. 1 means keep all
#define MIN_POINTS_PER_SUBREGION 1
// largest edge allowed when building small subregions
#define EDGE_THRESHOLD 40
// subregion padding to overlap the cropped images over the knocked out background, needed for proper rendering when scaled down
#define SUBREGION_PADDING 1

#define INSET(r) CGRectInset(r,2,2)

- (NSMutableArray *) computeMaxSubregions:(NSUInteger)max fromData:(NSData *)data ofSize:(CGSize)size
{
    
    NSMutableArray *subregions = [NSMutableArray arrayWithCapacity:max];
    unsigned char *ptr = (unsigned char*)[data bytes];

    for (int r=0; r<size.height; r++)
    {
        for (int c=0; c<size.width; c++)
        {
            
            if (abs(*ptr) +abs(*(ptr+1)) + abs(*(ptr+2)) + abs(*(ptr+3)) > SUBREGION_THRESHOLD)
            {
                CGPoint point = CGPointMake(1.f*c,1.f*(size.height - r - 1));
                CGFloat minArea = -1;
                FCRegion *minRegion = nil;
                for (FCRegion *region in subregions)
                {
                    if ([region containsPoint:point withInset:SUBREGION_INSET] && [region maxSideWithPoint:point] < EDGE_THRESHOLD)
                    {
                        CGFloat newArea = [region areaWithPoint:point];
                        if (minArea < 0 || minArea > newArea)
                        {
                            minRegion = region;
                            minArea = newArea;
                        }
                    }
                }
                if (minArea > 0)
                {
                    [minRegion addPoint:point];
                }
                else
                {
                    FCRegion *region = [[FCRegion alloc] init];
                    [region addPoint:point];
                    [subregions addObject:region];
                    [region release];
                }
            }
            ptr+=4;
        }
    }
    
    NSMutableSet *set = [NSMutableSet setWithArray:subregions];
    
    // Initial pass through regions to find regions entirely contained in other regions
//    for (FCRegion *region in subregions)
//    {
//        if ([region numberOfPoints] < MIN_POINTS_PER_SUBREGION)
//        {
//            [set removeObject:region];
//        }
//        else
//        {
//            for (FCRegion *cregion in subregions)
//            {
//                if ([set containsObject:cregion] && [set containsObject:region] && cregion != region)
//                {
//                    if (CGRectContainsRect([cregion bounds], [region bounds]))
//                    {
//                        [set removeObject:region];
//                        break;
//                    }
//                }
//            }
//        }
//    }
    
    // Pass through regions to find some to combine that yield smaller areas
    int reduce = [set count]-max;
    int loopmax = [set count]-1;
//    for (int c=0; c<loopmax; c++)
//    {
//        NSMutableArray *allObjects = [[set allObjects] mutableCopy];
//        [allObjects shuffle];
//        for (FCRegion *r1 in allObjects)
//        {
//            if ([set containsObject:r1])
//            {
//                for (int compare=[allObjects indexOfObject:r1]+1; compare < [allObjects count]; compare++)
//                {
//                    FCRegion *r2 = [allObjects objectAtIndex:compare];
//                    if ([set containsObject:r2])
//                    {
//                        CGFloat comboArea = [r1 unionAreaWithBounds:[r2 bounds]];
//                        CGFloat sumArea = [r1 area] + [r2 area];
//                        if (sumArea > comboArea)
//                        {
//                            [r1 mergeWithRegion:r2];
//                            [set removeObject:r2];
//                        }
//                    }
//                }
//            }
//        }
//    }
    
    // main optimization loop -- reduce to find the bare minimum
    reduce = [set count]-max;
    loopmax = [set count]-1;
    for (int c=0; c<loopmax; c++)
    {
        NSMutableArray *allObjects = [[set allObjects] mutableCopy];
        [allObjects shuffle];
        CGFloat minArea = -1;
        FCRegion *min1=nil, *min2=nil;
        for (FCRegion *r1 in allObjects)
        {
            for (int compare=[allObjects indexOfObject:r1]+1; compare < [allObjects count]; compare++)
            {
                FCRegion *r2 = [allObjects objectAtIndex:compare];
                CGFloat comboArea = [r1 unionAreaWithBounds:[r2 bounds]];
                if (c < reduce && (comboArea < minArea || minArea < 0))
                {
                    minArea = comboArea;
                    min1 = r1;
                    min2 = r2;
                }
            }
        }
        if (min1 && min2)
        {
            [min1 mergeWithRegion:min2];
            [set removeObject:min2];
        }
    }

    // Another pass through remaining regions to find some to combine that yield smaller areas
    reduce = [set count]-max;
    loopmax = [set count]-1;
    for (int c=0; c<loopmax; c++)
    {
        NSMutableArray *allObjects = [[set allObjects] mutableCopy];
        [allObjects shuffle];
        for (FCRegion *r1 in allObjects)
        {
            for (int compare=[allObjects indexOfObject:r1]+1; compare < [allObjects count]; compare++)
            {
                FCRegion *r2 = [allObjects objectAtIndex:compare];
                CGFloat comboArea = [r1 unionAreaWithBounds:[r2 bounds]];
                CGFloat sumArea = [r1 area] + [r2 area];
                if ([set containsObject:r1] && [set containsObject:r2] && sumArea > comboArea)
                {
                    [r1 mergeWithRegion:r2];
                    [set removeObject:r2];
                }
            }
        }
    }
    
    // try to reduce area by looking for overlapping intersections
    reduce = [set count]-max;
    loopmax = [set count]-1;
    for (int c=0; c<loopmax; c++)
    {
        NSMutableArray *allObjects = [[set allObjects] mutableCopy];
        [allObjects shuffle];
        for (FCRegion *r1 in allObjects)
        {
            for (int compare=0; compare < [allObjects count]; compare++)
            {
                FCRegion *r2 = [allObjects objectAtIndex:compare];
                if (r1 != r2)
                {
                    [r1 reduceIfOverlaps:r2];
                }
            }
        }
    }

    // try to reduce area by looking for three overlapping intersections
    FCRegion *newRegion = [[FCRegion alloc] init];
    NSMutableArray *allObjects = [[set allObjects] mutableCopy];
    [allObjects shuffle];
    for (FCRegion *r1 in allObjects)
    {
        for (int compare=0; compare < [allObjects count]; compare++)
        {
            FCRegion *r2 = [allObjects objectAtIndex:compare];
            CGRect r12 = CGRectIntersection([r1 bounds], [r2 bounds]);
            if (r1 != r2 && !CGRectIsEmpty(r12))
            {
                for (int compare3=0; compare3 < [allObjects count]; compare3++)
                {
                    FCRegion *r3 = [allObjects objectAtIndex:compare3];
                    CGRect r312 = CGRectIntersection(CGRectInset([r3 bounds],-0.5,-0.5), CGRectInset(r12,-0.5,-0.5));
                    if (r2 != r3 && r1 != r3 && !CGRectIsEmpty(r312))
                    {
                        CGRect bounds = [r1 bounds];
                        CGPoint p1 = CGPointMake(bounds.origin.x, bounds.origin.y);
                        CGPoint p2 = CGPointMake(bounds.origin.x, bounds.origin.y + bounds.size.height);
                        CGPoint p3 = CGPointMake(bounds.origin.x + bounds.size.width, bounds.origin.y + bounds.size.height);
                        CGPoint p4 = CGPointMake(bounds.origin.x + bounds.size.width, bounds.origin.y);
                        
                        if ((CGRectContainsPoint([r2 bounds], p1) && CGRectContainsPoint([r3 bounds], p2)) || (CGRectContainsPoint([r2 bounds], p2) && CGRectContainsPoint([r3 bounds], p1)) )
                        {
                            CGFloat minmaxx = fminf(CGRectGetMaxX([r2 bounds]),CGRectGetMaxX([r3 bounds]));
                            CGFloat maxminx = fmaxf(CGRectGetMinX([r2 bounds]),CGRectGetMinX([r3 bounds]));
                            CGFloat miny = fminf(CGRectGetMinY([r2 bounds]),CGRectGetMinY([r3 bounds]));
                            CGFloat maxy = fmaxf(CGRectGetMaxY([r2 bounds]),CGRectGetMaxY([r3 bounds]));
                            [newRegion setBounds:CGRectMake(maxminx, miny, minmaxx-maxminx, maxy-miny)];
                        }
                        else if ((CGRectContainsPoint([r2 bounds], p3) && CGRectContainsPoint([r3 bounds], p4)) || (CGRectContainsPoint([r2 bounds], p4) && CGRectContainsPoint([r3 bounds], p3)) )
                        {
                            CGFloat minmaxx = fminf(CGRectGetMaxX([r2 bounds]),CGRectGetMaxX([r3 bounds]));
                            CGFloat maxminx = fmaxf(CGRectGetMinX([r2 bounds]),CGRectGetMinX([r3 bounds]));
                            CGFloat miny = fminf(CGRectGetMinY([r2 bounds]),CGRectGetMinY([r3 bounds]));
                            CGFloat maxy = fmaxf(CGRectGetMaxY([r2 bounds]),CGRectGetMaxY([r3 bounds]));
                            [newRegion setBounds:CGRectMake(maxminx, miny, minmaxx-maxminx, maxy-miny)];
                        }
                        
                        else if ((CGRectContainsPoint([r2 bounds], p2) && CGRectContainsPoint([r3 bounds], p3)) || (CGRectContainsPoint([r2 bounds], p3) && CGRectContainsPoint([r3 bounds], p2)) )
                        {
                            CGFloat minmaxy = fminf(CGRectGetMaxY([r2 bounds]),CGRectGetMaxY([r3 bounds]));
                            CGFloat maxminy = fmaxf(CGRectGetMinY([r2 bounds]),CGRectGetMinY([r3 bounds]));
                            CGFloat minx = fminf(CGRectGetMinX([r2 bounds]),CGRectGetMinX([r3 bounds]));
                            CGFloat maxx = fmaxf(CGRectGetMaxX([r2 bounds]),CGRectGetMaxX([r3 bounds]));
                            [newRegion setBounds:CGRectMake(minx, maxminy, maxx-minx, minmaxy-maxminy)];
                        }
                        else if ((CGRectContainsPoint([r2 bounds], p1) && CGRectContainsPoint([r3 bounds], p4)) || (CGRectContainsPoint([r2 bounds], p4) && CGRectContainsPoint([r3 bounds], p1)) )
                        {
                            CGFloat minmaxy = fminf(CGRectGetMaxY([r2 bounds]),CGRectGetMaxY([r3 bounds]));
                            CGFloat maxminy = fmaxf(CGRectGetMinY([r2 bounds]),CGRectGetMinY([r3 bounds]));
                            CGFloat minx = fminf(CGRectGetMinX([r2 bounds]),CGRectGetMinX([r3 bounds]));
                            CGFloat maxx = fmaxf(CGRectGetMaxX([r2 bounds]),CGRectGetMaxX([r3 bounds]));
                            [newRegion setBounds:CGRectMake(minx, maxminy, maxx-minx, minmaxy-maxminy)];
                        }

                        [r1 reduceIfOverlaps:newRegion];
                    }
                }
            }
        }
    }
    
    // try to reduce area by chopping one-vertex overlapping
    allObjects = [[set allObjects] mutableCopy];
    [allObjects shuffle];
    for (FCRegion *r1 in allObjects)
    {
        for (int compare=0; compare < [allObjects count]; compare++)
        {
            FCRegion *r2 = [allObjects objectAtIndex:compare];
            CGRect r12 = CGRectIntersection([r1 bounds], [r2 bounds]);
            if (r1 != r2 && !CGRectIsEmpty(r12))
            {
                CGRect bounds = [r1 bounds];
                CGPoint p1 = CGPointMake(bounds.origin.x, bounds.origin.y);
                CGPoint p2 = CGPointMake(bounds.origin.x, bounds.origin.y + bounds.size.height);
                CGPoint p3 = CGPointMake(bounds.origin.x + bounds.size.width, bounds.origin.y + bounds.size.height);
                CGPoint p4 = CGPointMake(bounds.origin.x + bounds.size.width, bounds.origin.y);
                
                if (CGRectContainsPoint(INSET([r2 bounds]), p1))
                {
                    FCRegion *extraRegion = [[FCRegion alloc] init];
                    CGPoint origin = CGPointMake(bounds.origin.x,bounds.origin.y+r12.size.height);
                    extraRegion.bounds = CGRectMake(origin.x,origin.y,bounds.size.width,bounds.size.height-r12.size.height);
                    [set addObject:extraRegion];
                    [extraRegion release];
                    bounds.size.height = r12.size.height;
                    bounds.origin.x += r12.size.width;
                    bounds.size.width -= r12.size.width;
                    r1.bounds = bounds;
                }
                else if (CGRectContainsPoint(INSET([r2 bounds]), p2))
                {
                    FCRegion *extraRegion = [[FCRegion alloc] init];
                    CGPoint origin = CGPointMake(bounds.origin.x+r12.size.width,[r2 bounds].origin.y);
                    extraRegion.bounds = CGRectMake(origin.x,origin.y,bounds.size.width-r12.size.width,r12.size.height);
                    [set addObject:extraRegion];
                    [extraRegion release];
                    bounds.size.height -= r12.size.height;
                    r1.bounds = bounds;
                }
                else if (CGRectContainsPoint(INSET([r2 bounds]), p3))
                {
                    FCRegion *extraRegion = [[FCRegion alloc] init];
                    CGPoint origin = CGPointMake(bounds.origin.x, r12.origin.y);
                    extraRegion.bounds = CGRectMake(origin.x,origin.y,bounds.size.width-r12.size.width,r12.size.height);
                    [set addObject:extraRegion];
                    [extraRegion release];
                    bounds.size.height -= r12.size.height;
                    r1.bounds = bounds;
                }
                else if (CGRectContainsPoint(INSET([r2 bounds]), p4))
                {
                    FCRegion *extraRegion = [[FCRegion alloc] init];
                    CGPoint origin = CGPointMake(bounds.origin.x, bounds.origin.y+r12.size.height);
                    extraRegion.bounds = CGRectMake(origin.x,origin.y,bounds.size.width,bounds.size.height-r12.size.height);
                    [set addObject:extraRegion];
                    [extraRegion release];
                    bounds.size.height = r12.size.height;
                    bounds.size.width -= r12.size.width;
                    r1.bounds = bounds;
                }
            }
        }
    }

    [newRegion release];

    return [NSMutableArray arrayWithArray:[set allObjects]];
}

- (void) exportImage:(FCImage*)image toFileName:(NSString*)fileName queue:(NSOperationQueue*)_queue withExportMatrix:(NSInteger)selectedRow
{
    switch(selectedRow)
    {
        case 0:
            [image exportPNGTo:fileName
                     withQueue:_queue];
            break;
        case 1:
            [image exportLZ4To:fileName
                     withQueue:_queue];
            break;
        case 2:
            [image exportPVRPhotoTo:fileName
                          withQueue:_queue];
            break;
        case 3:
            [image exportPVRGradientTo:fileName
                             withQueue:_queue];
            break;
        case 4:
            [image exportPNGQuantTo:fileName
                          withQueue:_queue
                      withTableSize:256];
            break;
        case 5:
            [image exportPNGQuantTo:fileName
                          withQueue:_queue
                      withTableSize:128];
            break;
        case 6:
            [image exportPNGQuantTo:fileName
                          withQueue:_queue
                      withTableSize:64];
            break;
        case 7:
            [image exportSP1To:fileName
                     withQueue:_queue
                 withTableSize:64];
            break;
    }

}

- (NSString *) extensionForExportMatrix:(NSInteger)selectedRow
{
    switch(selectedRow)
    {
        case 0:
        case 4:
        case 5:
        case 6:
        case 7:
            return @"png";
            break;
        case 1:
            return @"lz4";
            break;
        case 2:
        case 3:
            return @"pvr";
            break;
    }
    return @"";
}

- (void) processDirectoryAtPath:(NSString *)sourceDirectory
{
    NSRect screenRect = [[NSScreen mainScreen] frame];
    
    NSWindow * transWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(screenRect.origin.x+screenRect.size.width-(260+10),
                                                                              screenRect.origin.y+screenRect.size.height-(72+30),
                                                                              260, 72)
                                                         styleMask:NSBorderlessWindowMask
                                                           backing:NSBackingStoreRetained
                                                             defer:NO];
    
    [transWindow setBackgroundColor: [NSColor clearColor]];
    [transWindow setOpaque:NO];
    [transWindow setLevel:NSPopUpMenuWindowLevel];
    
    [transWindow makeKeyAndOrderFront:NULL];
    
    [transWindow startProgressBarWithMessage:@"Initializing Process"];
    
    queue = [[NSOperationQueue alloc] init];
    queue.maxConcurrentOperationCount = 1;

    NSMutableArray * allFiles = [NSMutableArray arrayWithArray:[[NSFileManager defaultManager] contentsOfDirectoryAtPath:sourceDirectory error:NULL]];
    
    NSMutableArray * allImages = [NSMutableArray array];
    NSMutableArray * processedImages = [NSMutableArray array];
    NSMutableArray * uniqueImages = [NSMutableArray array];
    NSInteger imageIndex = 0;
    
    gCompareUsingMD5 = [compareUsingMD5 intValue];
    gShouldTrimImages = [trimImagesBtn intValue];
    gShouldRemoveDuplicates = [removeDuplicatesBtn intValue];
    
    [allFiles sortUsingComparator:^NSComparisonResult(NSString * obj1, NSString * obj2) {
        obj1 = [obj1 stringByTrimmingCharactersInSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]];
        obj2 = [obj2 stringByTrimmingCharactersInSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]];
        
        int num1 = [obj1 intValue];
        int num2 = [obj2 intValue];
        
        return [[NSNumber numberWithInt:num1] compare:[NSNumber numberWithInt:num2]];
    }];
    
    globalMin.x = 99999999999;
    globalMin.y = 99999999999;
    globalMax.x = 0;
    globalMax.y = 0;
    
    NSInteger findSubregionsMax = [maxSubregions selectedItem].tag;
    NSMutableData *subregionData = nil;
    FCImage *firstImage = nil;
    
    imageIndex = 0;
    for(NSString * fileName in allFiles)
    {
        @autoreleasepool {
            NSString * filePath = [sourceDirectory stringByAppendingPathComponent:fileName];
            
            if([filePath hasSuffix:@"png"])
            {
                [transWindow continueProgressBarMessage:[NSString stringWithFormat:@"Cropping %@", [filePath lastPathComponent]]
                                              withValue:((float)imageIndex/(float)[allFiles count])];
                
                FCImage * newImage = [[[FCImage alloc] initWithSource:filePath] autorelease];
//                NSLog(@"newImage");[FCImage dumpData:[newImage pixelData]];
                
                if(newImage)
                {
                    if(findSubregionsMax == 0 && gShouldTrimImages)
                    {
                        CGPoint localMin, localMax;
                        
                        [newImage trimmedValuesWithMin:&localMin
                                                andMax:&localMax];
                        
                        if(localMin.x < globalMin.x)
                        {
                            globalMin.x = localMin.x;
                        }
                        if(localMin.y < globalMin.y)
                        {
                            globalMin.y = localMin.y;
                        }
                        
                        if(localMax.x > globalMax.x)
                        {
                            globalMax.x = localMax.x;
                        }
                        if(localMax.y > globalMax.y)
                        {
                            globalMax.y = localMax.y;
                        }
                    }
                    
                    [allImages addObject:newImage];
                    
                    if (findSubregionsMax > 0)
                    {
                        if (!firstImage)
                        {
                            firstImage = [[FCImage alloc] initWithSource:filePath];
                            subregionData = [[NSMutableData dataWithLength:[[firstImage pixelData] length]] retain];
                        }
                        else
                        {
                            NSData *diff = [firstImage subtract:newImage];
                            unsigned char * ptr1 = (unsigned char*)[subregionData bytes];
                            unsigned char * ptr2 = (unsigned char*)[diff bytes];
                            
                            for(int i=0; i<[subregionData length]; i++)
                            {
                                if (*ptr2 > *ptr1)
                                {
                                    *ptr1 = *ptr2;
                                }
//                                NSUInteger sum = *ptr1 + *ptr2;
//                                *ptr1 = (sum > 255 ? 255 : sum);
                                ptr1++;
                                ptr2++;
                            }
                        }
                    }

                }
            }
        }
        
        imageIndex++;
    }

    NSMutableArray *subregions = nil;
    if (findSubregionsMax > 0)
    {
        NSRect imageBounds = NSMakeRect(0, 0, 1024, 1024);
        CGSize imgSize = [firstImage size];
        imageBounds.size = NSSizeFromCGSize(imgSize);
        CGFloat maxSize = (imgSize.width > imgSize.height ? imgSize.width : imgSize.height);
        if (maxSize > 1024)
        {
            imageBounds.size.width = 1024/maxSize * imgSize.width;
            imageBounds.size.height = 1024/maxSize * imgSize.height;
        }
        imageBounds.size.height +=20;
        NSWindow *win = [[NSWindow alloc] initWithContentRect:imageBounds
                                                    styleMask:(NSTitledWindowMask|NSClosableWindowMask)
                                                      backing:NSBackingStoreBuffered
                                                        defer:NO];
        imageBounds.size.height -=20;
        NSImageView *imageView = [[NSImageView alloc] initWithFrame:imageBounds];
        NSImage *image = [[NSImage alloc ] initByReferencingFile:firstImage.sourceFile];
        imageView.image = image;
        imageView.tag = 314;

        [FCImage dumpData:subregionData size:[firstImage size]];
        subregions = [self computeMaxSubregions:findSubregionsMax fromData:subregionData ofSize:[firstImage size]];
        
        CGFloat totalArea = 0.f;
        for (FCRegion *region in subregions)
        {
            totalArea += [region area];
            CGRect rbounds = [region bounds];
            CGFloat scale = imgSize.height / imageBounds.size.height;
            scale = (scale < 1.f ? scale : 1.f/scale);
            NSRect vbounds = NSMakeRect(rbounds.origin.x*scale, rbounds.origin.y*scale, rbounds.size.width*scale, rbounds.size.height*scale);
            NSView *view = [[NSView alloc] initWithFrame:vbounds];
            CALayer *viewLayer = [CALayer layer];

            [viewLayer setBackgroundColor:CGColorCreateGenericRGB(0.8, 0.0, 0.0, 0.4)];
            viewLayer.borderColor = CGColorCreateGenericRGB(0.4, 0.f, 0.f, 0.8);
            viewLayer.borderWidth = 1.f;
            [view setWantsLayer:YES];
            [view setLayer:viewLayer];
            [imageView addSubview:view];
//            NSLog(@"drawing box: %@ <== %@", NSStringFromRect(vbounds), NSStringFromRect(NSRectFromCGRect(rbounds)));
        }
        NSLog(@"total area %.0f px^2 from %d regions", totalArea, [subregions count]);
        [win setTitle:[NSString stringWithFormat:@"%.0f sqpx in %d regions", totalArea, [subregions count]]];
        [win.contentView addSubview:imageView];
        [win makeKeyAndOrderFront:[NSApplication sharedApplication]];

    }

    NSString *regionsSnippet = @"";
    NSString *baseFileName = [[[firstImage sourceFile] lastPathComponent] stringByDeletingPathExtension];
    baseFileName = [baseFileName stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789"]];

    // Create the export directory
    NSString * exportDirectory = [sourceDirectory stringByAppendingPathComponent:@"export"];
    
    [[NSFileManager defaultManager] removeItemAtPath:exportDirectory error:NULL];
    
    [[NSFileManager defaultManager] createDirectoryAtPath:exportDirectory
                              withIntermediateDirectories:NO
                                               attributes:NULL
                                                    error:NULL];
    // export whole first image if using subregions
    if(findSubregionsMax > 0)
    {
        globalMin = CGPointZero;
        globalMax = CGPointMake(firstImage.size.width, firstImage.size.height);
        FCImage *baseImage = [[FCImage alloc] initWithSource:firstImage.sourceFile];
        for (FCRegion *region in subregions)
        {
            [baseImage makeTransparentRect:[region bounds]];
            [region expandBoundsBy:1.f toMaxSize:firstImage.size];
        }
        NSString *fileName = [baseFileName stringByAppendingString:@"base"];
        [self exportImage:baseImage toFileName:[exportDirectory stringByAppendingPathComponent:fileName] queue:queue withExportMatrix:[exportMatrix selectedRow]];
        fileName = [fileName stringByAppendingPathExtension:[self extensionForExportMatrix:[exportMatrix selectedRow]]];
        regionsSnippet = [regionsSnippet stringByAppendingFormat:@"<Image bounds=\"0,0,%d,%d\" urlPath=\"bundle://%@\">\n", (int)([firstImage size].width), (int)([firstImage size].height), fileName];
        [baseImage release];
    }

    int currentRegion = 0;
    do {
        imageIndex = 0;
        
        FCRegion *region = nil;
        NSString *suffix = @"";
        CGRect cropBounds;
        if (subregions)
        {
            region = [subregions objectAtIndex:currentRegion];
            cropBounds = [region bounds];
            CGSize imgSize = [firstImage size];
            globalMin.x = cropBounds.origin.x;
            globalMin.y = imgSize.height - cropBounds.origin.y - cropBounds.size.height;
            globalMax.x = cropBounds.origin.x + cropBounds.size.width;
            globalMax.y = globalMin.y + cropBounds.size.height;
            suffix = [NSString stringWithFormat:@"region%02d_",currentRegion];
            NSString *fileName = [baseFileName stringByAppendingFormat:@"%@0000",suffix];
            fileName = [fileName stringByAppendingPathExtension:[self extensionForExportMatrix:[exportMatrix selectedRow]]];
            regionsSnippet = [regionsSnippet stringByAppendingFormat:@"\t<Image bounds=\"%d,%d,%d,%d\" urlPath=\"%@\">\n", (int)(cropBounds.origin.x), (int)(cropBounds.origin.y), (int)(cropBounds.size.width), (int)(cropBounds.size.height), [NSString stringWithFormat:@"bundle://%@",fileName]];

        }
        
        [processedImages removeAllObjects];
        [uniqueImages removeAllObjects];
        
        for(FCImage * newImage in allImages)
        {
            @autoreleasepool {
                if (subregions)
                {
                    [transWindow continueProgressBarMessage:[NSString stringWithFormat:@"Region %d/%d %@", currentRegion, [subregions count], [newImage.sourceFile lastPathComponent]]
                                                  withValue:((float)imageIndex/(float)[allFiles count])];
                }
                else
                {
                    [transWindow continueProgressBarMessage:[NSString stringWithFormat:@"Processing %@", [newImage.sourceFile lastPathComponent]]
                                                  withValue:((float)imageIndex/(float)[allFiles count])];
                }
        
                FCImage * duplicateOfImage = NULL;
                
                newImage.index = imageIndex++;
                
                if(gShouldRemoveDuplicates)
                {
                    // Check to see if another frame is like this frame.
                    for(FCImage * existingImage in uniqueImages)
                    {
                        @autoreleasepool {
                            
                            if (subregions)
                            {
                                if ([newImage compare:existingImage pixelsWithMin:globalMin andMax:globalMax])
                                {
                                    NSLog(@"DUPLICATE: %@ and %@", [newImage.sourceFile lastPathComponent], [existingImage.sourceFile lastPathComponent]);
                                    duplicateOfImage = existingImage;
                                    [newImage dropMemory];
                                    [existingImage dropMemory];
                                    break;
                                }
                            }
                            else if([newImage compare:existingImage])
                            {
                                NSLog(@"DUPLICATE: %@ and %@", [newImage.sourceFile lastPathComponent], [existingImage.sourceFile lastPathComponent]);
                                duplicateOfImage = existingImage;
                                [newImage dropMemory];
                                [existingImage dropMemory];
                                break;
                            }
                            
                            [newImage dropMemory];
                            [existingImage dropMemory];
                        }
                    }
                }
                
                if(duplicateOfImage)
                {
                    newImage.index = duplicateOfImage.index;
                }
                else
                {
                    [uniqueImages addObject:newImage];
                }

                [processedImages addObject:newImage];
            }
        }
        
        // Translate the indices in processedImages to their uniqueImages equivalents
        for(FCImage * image in processedImages)
        {
            FCImage * otherImage = [processedImages objectAtIndex:image.index];
            image.index = [uniqueImages indexOfObject:otherImage];
            [image dropMemory];
        }
        
        NSMutableString * frameSequence = [NSMutableString string];
        for(int i = 0; i < [processedImages count]; i++)
        {
            FCImage * image = [processedImages objectAtIndex:i];
            BOOL didConversion = NO;
            
            // Detect runs of the same number...
            for(int j = i+1; j < [processedImages count]; j++)
            {
                FCImage * nextImage = [processedImages objectAtIndex:j];
                
                if(nextImage.index != image.index || j+1 >= [processedImages count])
                {
                    if(j-i > 1)
                    {
                        [frameSequence appendFormat:@"%d*%d,", (int)image.index, j-i];
                        i = j-1;
                        didConversion = YES;
                    }
                    break;
                }
            }
            if(didConversion) continue;
            
            // Detect runs of incremental number...
            for(int j = i+1; j < [processedImages count]; j++)
            {
                FCImage * nextImage = [processedImages objectAtIndex:j];
                FCImage * prevImage = [processedImages objectAtIndex:j-1];
                
                if(nextImage.index != prevImage.index+1 || j+1 >= [processedImages count])
                {
                    if(prevImage.index-image.index > 1)
                    {
                        [frameSequence appendFormat:@"%d-%d,", (int)image.index, (int)prevImage.index];
                        i = j-1;
                        didConversion = YES;
                    }
                    break;
                }
            }
            if(didConversion) continue;
            
            
            
            [frameSequence appendFormat:@"%d,", (int)image.index];
        }
        
        // Export all of the images
        
        for(FCImage * image in uniqueImages)
        {
            NSString * fileName = [[[image sourceFile] lastPathComponent] stringByDeletingPathExtension];

            if (findSubregionsMax > 0)
            {
                fileName = [fileName stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789"]];
                fileName = [baseFileName stringByAppendingString:suffix];
                fileName = [exportDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@%04d", fileName, (int)image.index]];
            }
            else if(gShouldRemoveDuplicates)
            {
                fileName = [fileName stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789"]];
                fileName = [exportDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@%04d", fileName, (int)image.index]];
            }
            else
            {
                fileName = [exportDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@", fileName]];
            }

            [self exportImage:image toFileName:fileName queue:queue withExportMatrix:[exportMatrix selectedRow]];
        }
        
        while([queue operationCount])
        {
            usleep(50000);
            
            [transWindow continueProgressBarMessage:[NSString stringWithFormat:@"Exporting Images..."]
                                          withValue:1.0f - ((float)[queue operationCount]/(float)[uniqueImages count])];
        }
        
        
        if(findSubregionsMax > 0)
        {
            NSString *pathFormat = [NSString stringWithFormat:@"%@%@#", baseFileName, suffix];
            pathFormat = [pathFormat stringByAppendingPathExtension:[self extensionForExportMatrix:[exportMatrix selectedRow]]];
            regionsSnippet = [regionsSnippet stringByAppendingFormat:@"\t\t<FrameAnimation looping=\"true\" sequence=\"%@\" pathFormat=\"bundle://%@\" digits=\"4\" />\n\t</Image>\n", frameSequence, pathFormat];
        }
        else if (gShouldRemoveDuplicates)
        {
            NSString *bounds = [NSString stringWithFormat:@"%d,%d,%d,%d", (int)(globalMin.x), (int)(globalMin.y), (int)(globalMax.x-globalMin.x), (int)(globalMax.y-globalMin.y)];
            
            [bounds writeToFile:[exportDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"bounds.txt"]]
                     atomically:NO
                       encoding:NSUTF8StringEncoding
                          error:NULL];
            
            [frameSequence writeToFile:[exportDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"sequence.txt"]]
                            atomically:NO
                              encoding:NSUTF8StringEncoding
                                 error:NULL];
        }
        currentRegion++;
    } while (currentRegion < [subregions count]);

    // export whole first image if using subregions
    if(findSubregionsMax > 0)
    {
        regionsSnippet = [regionsSnippet stringByAppendingString:@"</Image>"];
        [regionsSnippet writeToFile:[exportDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"regions.xml"]]
                        atomically:NO
                          encoding:NSUTF8StringEncoding
                             error:NULL];
    }

    
    [transWindow stopProgressBarWithMessage:@"Process Complete"];
    
    [queue release];
    [transWindow autorelease];
    [subregionData release];
}


#pragma mark -

- (void)dealloc
{
    [super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Insert code here to initialize your application
    NSOpenPanel * setDirectory = [NSOpenPanel openPanel];
    setDirectory.canChooseFiles=NO;
    setDirectory.canCreateDirectories=YES;
    setDirectory.canChooseDirectories=YES;
    
    [setDirectory setAccessoryView:exportInfo];
    
    NSInteger result = [setDirectory runModal];
    
    if(result == NSFileHandlingPanelOKButton)
    {
        [self processDirectoryAtPath:[[[setDirectory URLs] objectAtIndex:0] path]];
    }
    
//    exit(1);
}

@end

