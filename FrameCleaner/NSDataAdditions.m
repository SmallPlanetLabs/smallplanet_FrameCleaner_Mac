#include <zlib.h>
#include "fastlz.h"
#include "lz4.h"

#import "NSDataAdditions.h"

#define USE_SNAPPY 0
#define USE_ZLIB 0
#define USE_FASTLZ 1

// Format header
struct CCZHeader {
uint8_t			sig[4];				// signature. Should be 'CCZ!' 4 bytes
uint16_t		compression_type;	// See enums below
uint16_t		version;			// should be 2
uint32_t		reserved;			// Reserverd for users.
uint32_t		len;				// size of the uncompressed file
};

enum {
	CCZ_COMPRESSION_ZLIB,			// zlib format.
	CCZ_COMPRESSION_BZIP2,			// bzip2 format
	CCZ_COMPRESSION_GZIP,			// gzip format
};



#define MIN_RUN     3                   /* minimum run length to encode */
#define MAX_RUN     (128 + MIN_RUN - 1) /* maximum run length to encode */
#define MAX_COPY    128                 /* maximum characters to copy */

/* maximum that can be read before copy block is written */
#define MAX_READ    (MAX_COPY + MIN_RUN - 1)





@implementation NSOffsetData

+ (id)dataWithBytesNoCopy:(void *)bytes length:(NSUInteger)length
{
    return [[[NSOffsetData alloc] initWithBytesNoCopy:bytes length:length freeWhenDone:YES] autorelease];
}

+ (id)dataWithBytesNoCopy:(void *)bytes length:(NSUInteger)length freeWhenDone:(BOOL)b
{
    return [[[NSOffsetData alloc] initWithBytesNoCopy:bytes length:length freeWhenDone:b] autorelease];
}

- (id)initWithBytesNoCopy:(void *)bytes length:(NSUInteger)_length freeWhenDone:(BOOL)b
{
    self = [super init];
    if(self)
    {
        data = [[NSData alloc] initWithBytesNoCopy:bytes length:_length freeWhenDone:b];
        offset = 0;
        length = _length;
    }
    return self;
}

- (void) dealloc
{
    [data release];
    [super dealloc];
}

- (void *) beginReplacementOfSize:(NSUInteger)newSize
{
    replacementBytes = (char *)malloc(newSize);
    replacementLength = newSize;
    return replacementBytes;
}

- (void) commitReplacement
{
    [data release];
    
    data = [[NSData dataWithBytesNoCopy:replacementBytes length:replacementLength freeWhenDone:YES] retain];
    
    offset = 0;
    length = 0;
    
    replacementBytes = NULL;
    replacementLength = 0;
}

- (NSData *)data
{
    return data;
}

- (void) setOffset:(NSUInteger)off
{
    offset = off;
}

- (void) setLength:(NSUInteger)l
{
    length = l;
}

- (NSUInteger)length
{
    if(length)
        return length;
    return [data length] - offset;
}

- (const void *) bytes
{
    return (const void *)((char *)[data bytes]+offset);
}


- (NSOffsetData *) cczInflate
{
	// load file into memory
	unsigned char *compressed = (unsigned char *)[self bytes];
	
#if USE_ZLIB
	int fileLen = [self length];
#endif
	
	struct CCZHeader *header = (struct CCZHeader*) compressed;
	
	// verify header
	if( header->sig[0] != 'C' || header->sig[1] != 'C' || header->sig[2] != 'Z' || header->sig[3] != '!' ) {
		NSLog(@"Invalid CCZ file");
		return [[[NSOffsetData alloc] init] autorelease];
	}
	
	// verify header version
	uint16_t version = CFSwapInt16BigToHost( header->version );
	if( version > 2 ) {
		NSLog(@"Unsupported CCZ header format");
		return [[[NSOffsetData alloc] init] autorelease];
	}
	
	// verify compression format
	if( CFSwapInt16BigToHost(header->compression_type) != CCZ_COMPRESSION_ZLIB ) {
		NSLog(@"CCZ Unsupported compression method");
		return [[[NSOffsetData alloc] init] autorelease];
	}
	
	uint32_t len = CFSwapInt32BigToHost( header->len );
	const Bytef * source = compressed + sizeof(*header);
	
#if USE_SNAPPY
	size_t slen = 0;
	snappy_uncompressed_length((const char *)source,
							   [self length]-sizeof(*header),
							   &slen);
	
	len = slen;
#endif
	
	uLongf destlen = len;
	
	Bytef * outBuffer = (Bytef *)malloc( len );
	if(! outBuffer )
	{
		NSLog(@"CCZ: Failed to allocate memory for texture");
		return [[[NSOffsetData alloc] init] autorelease];
	}	
	
#if USE_SNAPPY
	snappy_uncompress((const char *)source,
					  [self length]-sizeof(*header),
					  (char *)outBuffer,
					  &slen);
#endif
	
#if USE_FASTLZ
	fastlz_decompress(source, [self length]-sizeof(*header), outBuffer, len); 
#endif
	
#if USE_ZLIB
	int ret = uncompress(outBuffer, &destlen, source, fileLen - sizeof(*header) );
	if( ret != Z_OK )
	{
		NSLog(@"CCZ: Failed to uncompress data");
		free( outBuffer );
		outBuffer = NULL;
		return [[[NSOffsetData alloc] init] autorelease];
	}
#endif
	
	return [NSOffsetData dataWithBytesNoCopy:outBuffer length:destlen freeWhenDone:YES];
}

@end


@implementation NSData (PackBitsAdditions)

- (NSData *)unpackedImageRGBA
{
	unsigned int * length = (unsigned int*)[self bytes];
    char * row = ((char*)[self bytes]) + 4;
	char * rowPtr = row;
	int l;
	int nchannels = 4;
	
	char * outRawData = (char *)malloc((*length)*4);
	char * outRawDataStart = outRawData;
	
	char * src;
	
	unsigned int totalLength = ((*length)*4);
	int repeatTimes;
	UInt8 repeatByte;
	
	for(int channel = 0; channel < nchannels; channel++)
	{
		outRawData = outRawDataStart + channel;

		while (outRawData-outRawDataStart < totalLength)
		{
			if (*rowPtr < 0)
			{
				repeatTimes = (MIN_RUN - 1) - *rowPtr;
				repeatByte = *(rowPtr+1);
				while(repeatTimes >= 80)
				{
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					repeatTimes -= 80;
				}
				while(repeatTimes >= 40)
				{
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					repeatTimes -= 40;
				}
				while(repeatTimes >= 20)
				{
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					repeatTimes -= 20;
				}
				while(repeatTimes >= 10)
				{
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					repeatTimes -= 10;
				}
				while(repeatTimes >= 6)
				{
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					repeatTimes -= 6;
				}
				while(repeatTimes >= 4)
				{
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					repeatTimes -= 4;
				}
				while(repeatTimes >= 3)
				{
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					repeatTimes -= 3;
				}
				while(repeatTimes >= 2)
				{
					*outRawData = repeatByte;
					outRawData += nchannels;
					*outRawData = repeatByte;
					outRawData += nchannels;
					repeatTimes -= 2;
				}
				while(repeatTimes--)
				{
					*outRawData = repeatByte;
					outRawData += nchannels;
				}
				
				rowPtr += 2;
			}
			else
			{
				l = *rowPtr+1;
				src = rowPtr+1;
				
				while(l >= 80)
				{
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					l -= 80;
				}
				while(l >= 40)
				{
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					l -= 40;
				}
				while(l >= 20)
				{
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					l -= 20;
				}
				while(l >= 10)
				{
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					l -= 10;
				}
				while(l >= 6)
				{
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					l -= 6;
				}
				while(l >= 4)
				{
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					l -= 4;
				}
				while(l >= 3)
				{
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					l -= 3;
				}
				while(l >= 2)
				{
					*outRawData = *(src++);
					outRawData += nchannels;
					*outRawData = *(src++);
					outRawData += nchannels;
					l -= 2;
				}
				while(l--)
				{
					*outRawData = *(src++);
					outRawData += nchannels;
				}
				
				rowPtr += 2 + *rowPtr;
			}
		}
		
		// Skip the next length
		rowPtr += 4;
	}
	
    return [NSData dataWithBytesNoCopy:outRawDataStart length:totalLength freeWhenDone:YES];
}

- (NSData *)unpackedBits
{
	unsigned int * length = (unsigned int*)[self bytes];
    char * row = ((char*)[self bytes]) + 4;
    int pbOffset = 0;
	
	char * outRawData = (char *)malloc((*length+20));
	char * outRawDataStart = outRawData;
	
    while (pbOffset < [self length]){
        int headerByte = (int)row[pbOffset];
        if (headerByte < 0){
            int repeatTimes = (MIN_RUN - 1) - headerByte;
            UInt8 repeatByte = (UInt8)row[pbOffset+1];

			memset(outRawData, repeatByte, repeatTimes);

			outRawData += repeatTimes;
			
            pbOffset += 2;
        } else if (headerByte >= 0){
			
			memcpy(outRawData, row+pbOffset+1, headerByte + 1);
			
			outRawData += headerByte + 1;

            pbOffset += 2 + headerByte;
        }
    }
	
    return [NSData dataWithBytesNoCopy:outRawDataStart length:*length freeWhenDone:YES];
}

#pragma mark -

- (NSData*) packedBitsForRange:(NSRange)range skip:(int)skip
{
    char    * bytesIn = (char *)[self bytes];
    int     bytesLength = range.location + range.length;
    int     bytesOffset = range.location;
    NSMutableData * dataOut = [NSMutableData data];
	
    BOOL currIsEOF = NO;
    unsigned char currChar;             /* current character */
    unsigned char charBuf[MAX_READ];    /* buffer of already read characters */
    int count;                          /* number of characters in a run */
	
    /* prime the read loop */
    currChar = bytesIn[bytesOffset];
    bytesOffset = bytesOffset + skip;
    count = 0;
	
    /* read input until there's nothing left */
    while (!currIsEOF)
    {
        charBuf[count] = (unsigned char)currChar;
        count++;
		
        if (count >= MIN_RUN){
            int i;
			
            /* check for run  charBuf[count - 1] .. charBuf[count - MIN_RUN]*/
            for (i = 2; i <= MIN_RUN; i++){
                if (currChar != charBuf[count - i]){
                    /* no run */
                    i = 0;
                    break;
                }
            }
			
            if (i != 0){
                /* we have a run write out buffer before run*/
                unsigned char nextChar;
				
                if (count > MIN_RUN){
                    /* block size - 1 followed by contents */
                    UInt8 a = count - MIN_RUN - 1;
                    [dataOut appendBytes:&a length:sizeof(UInt8)];
                    [dataOut appendBytes:&charBuf length:sizeof(unsigned char) * (count - MIN_RUN)];
                }
				
                /* determine run length (MIN_RUN so far) */
                count = MIN_RUN;
                while (true){
                    if (bytesOffset < bytesLength){
                        nextChar = bytesIn[bytesOffset];
                        bytesOffset += skip;
                    } else {
                        currIsEOF = YES;
                        nextChar = EOF;
                    }
                    if (nextChar != currChar) break;
					
                    count++;
                    if (count == MAX_RUN){
                        /* run is at max length */
                        break;
                    }
                }
				
                /* write out encoded run length and run symbol */
                UInt8 a = ((int)(MIN_RUN - 1) - (int)(count));
                [dataOut appendBytes:&a length:sizeof(UInt8)];
                [dataOut appendBytes:&currChar length:sizeof(UInt8)];
				
                if ((!currIsEOF) && (count != MAX_RUN)){
                    /* make run breaker start of next buffer */
                    charBuf[0] = nextChar;
                    count = 1;
                } else {
                    /* file or max run ends in a run */
                    count = 0;
                }
            }
        }
		
        if (count == MAX_READ){
            int i;
			
            /* write out buffer */
            UInt8 a = MAX_COPY - 1;
            [dataOut appendBytes:&a length:sizeof(UInt8)];
            [dataOut appendBytes:&charBuf[0] length:sizeof(unsigned char) * MAX_COPY];
			
            /* start a new buffer */
            count = MAX_READ - MAX_COPY;
			
            /* copy excess to front of buffer */
            for (i = 0; i < count; i++)
                charBuf[i] = charBuf[MAX_COPY + i];
        }
		
        if (bytesOffset < bytesLength)
            currChar = bytesIn[bytesOffset];
        else
            currIsEOF = YES;
        bytesOffset += skip;
    }
	
    /* write out last buffer */
    if (0 != count){
        if (count <= MAX_COPY){
            /* write out entire copy buffer */
            UInt8 a = count - 1;
            [dataOut appendBytes:&a length:sizeof(UInt8)];
            [dataOut appendBytes:&charBuf length:sizeof(unsigned char) * count];
        }
        else
        {
            /* we read more than the maximum for a single copy buffer */
            UInt8 a = MAX_COPY - 1;
            [dataOut appendBytes:&a length:sizeof(UInt8)];
            [dataOut appendBytes:&charBuf length:sizeof(unsigned char) * MAX_COPY];
			
            /* write out remainder */
            count -= MAX_COPY;
            a = count - 1;
            [dataOut appendBytes:&a length:sizeof(UInt8)];
            [dataOut appendBytes:&charBuf[MAX_COPY] length:sizeof(unsigned char) * count];
        }
    }
	
	// Prepend the data block with the uncompressed size
	unsigned int length = [self length]/skip;
	[dataOut replaceBytesInRange:NSMakeRange(0, 0)
					   withBytes:&length
						  length:sizeof(length)];
	
    return dataOut;
}

- (NSData*)packedBits
{
	return [self packedBitsForRange:NSMakeRange(0, [self length]) skip:1];
}

- (NSData*) packedImageRGBA
{
	NSData * channel1 = [self packedBitsForRange:NSMakeRange(0, [self length]) skip:4];
	NSData * channel2 = [self packedBitsForRange:NSMakeRange(1, [self length]-1) skip:4];
	NSData * channel3 = [self packedBitsForRange:NSMakeRange(2, [self length]-2) skip:4];
	NSData * channel4 = [self packedBitsForRange:NSMakeRange(3, [self length]-3) skip:4];
	
	NSMutableData * outData = [NSMutableData dataWithCapacity:[channel1 length]+[channel2 length]+[channel3 length]+[channel4 length]];
	
	[outData appendData:channel1];
	[outData appendData:channel2];
	[outData appendData:channel3];
	[outData appendData:channel4];
	
	return outData;
}

#pragma mark -

- (NSData *)unpackedTargaRGBA
{
	UInt32 * length = (UInt32*)[self bytes];
    UInt32 * dataPtr = ((UInt32*)[self bytes]) + 1;
	UInt32 * dataEndPtr = (UInt32*)((UInt8*)[self bytes]+[self length]);
	UInt8 * headerPtr;
	UInt32 runLength;
	
	UInt32 * outRawData = (UInt32 *)malloc((*length+20));
	UInt32 * outRawDataStart = outRawData;
	
	while(dataPtr < dataEndPtr)
	{
		headerPtr = (UInt8*)dataPtr;
		dataPtr = (UInt32*)(headerPtr+1);
		
		if(*headerPtr < 128)
		{
			// Raw pixels
			runLength = (*headerPtr + 1);
			while(runLength--)
			{
				*(outRawData++) = *(dataPtr++);
			}
		}
		else
		{
			// Repeat pixels
			runLength = *headerPtr - 127;
			while(runLength--)
			{
				*(outRawData++) = *dataPtr;
			}
			dataPtr++;
		}
	}
	
	
    return [NSData dataWithBytesNoCopy:outRawDataStart length:*length freeWhenDone:YES];
}

- (NSData*) packedTargaRGBA
{
	NSMutableData * dataOut = [NSMutableData data];
	
	UInt32 * pixelPtr = (UInt32 *)[self bytes];
	UInt32 * lastPixelPtr = (UInt32 *)((UInt8*)[self bytes] + [self length] - 8);
	UInt32 * pixelRunPtr;
	UInt8 hdr;
	UInt32 length;
	
	while(pixelPtr <= lastPixelPtr)
	{
		pixelRunPtr = pixelPtr;
		pixelPtr++;
		if(*pixelRunPtr == *pixelPtr)
		{
			// A run of same pixels; find the end of the run
			while(*pixelRunPtr == *pixelPtr && (pixelPtr-pixelRunPtr) < 128 && pixelPtr <= lastPixelPtr)
			{
				pixelPtr++;
			}
			
			// We have a run of like pixels, output to the data...
			length = (pixelPtr-pixelRunPtr);
			hdr = length+127;
			[dataOut appendBytes:&hdr length:sizeof(UInt8)];
			[dataOut appendBytes:pixelRunPtr length:sizeof(UInt32)];
		}
		else
		{
			// A run of differing pixels
			while(*pixelRunPtr != *pixelPtr && (pixelPtr-pixelRunPtr) < 128 && pixelPtr <= lastPixelPtr)
			{
				pixelPtr++;
			}
			
			// We have a run of differing pixels, output to the data...
			length = (pixelPtr-pixelRunPtr);
			hdr = (length-1);
			[dataOut appendBytes:&hdr length:sizeof(UInt8)];
			[dataOut appendBytes:pixelRunPtr length:sizeof(UInt32)*length];
		}
	}
	
	// Prepend the data block with the uncompressed size
	UInt32 totalLength = [self length];
	[dataOut replaceBytesInRange:NSMakeRange(0, 0)
					   withBytes:&totalLength
						  length:sizeof(totalLength)];
	
	return dataOut;
}

#pragma mark -

- (NSData *)zlibInflate
{
	if ([self length] == 0) return self;
	
	unsigned full_length = [self length];
	unsigned half_length = [self length] / 2;
	
	NSMutableData *decompressed = [NSMutableData dataWithLength: full_length + half_length];
	BOOL done = NO;
	int status;
	
	z_stream strm;
	strm.next_in = (Bytef *)[self bytes];
	strm.avail_in = [self length];
	strm.total_out = 0;
	strm.zalloc = Z_NULL;
	strm.zfree = Z_NULL;
	
	if (inflateInit (&strm) != Z_OK) return nil;
	
	while (!done)
	{
		// Make sure we have enough room and reset the lengths.
		if (strm.total_out >= [decompressed length])
			[decompressed increaseLengthBy: half_length];
		strm.next_out = (Bytef *)([decompressed mutableBytes]) + strm.total_out;
		strm.avail_out = [decompressed length] - strm.total_out;
		
		// Inflate another chunk.
		status = inflate (&strm, Z_SYNC_FLUSH);
		if (status == Z_STREAM_END) done = YES;
		else if (status != Z_OK) break;
	}
	if (inflateEnd (&strm) != Z_OK) return nil;
	
	// Set real length.
	if (done)
	{
		[decompressed setLength: strm.total_out];
		return [NSData dataWithData: decompressed];
	}
	else return nil;
}

- (NSData *)zlibDeflate
{
	if ([self length] == 0) return self;
	
	z_stream strm;
	
	strm.zalloc = Z_NULL;
	strm.zfree = Z_NULL;
	strm.opaque = Z_NULL;
	strm.total_out = 0;
	strm.next_in=(Bytef *)[self bytes];
	strm.avail_in = [self length];
	
	// Compresssion Levels:
	//   Z_NO_COMPRESSION
	//   Z_BEST_SPEED
	//   Z_BEST_COMPRESSION
	//   Z_DEFAULT_COMPRESSION
	
	if (deflateInit(&strm, Z_DEFAULT_COMPRESSION) != Z_OK) return nil;
	
	NSMutableData *compressed = [NSMutableData dataWithLength:16384];  // 16K chuncks for expansion
	
	do {
		
		if (strm.total_out >= [compressed length])
			[compressed increaseLengthBy: 16384];
		
		strm.next_out = (Bytef *)([compressed mutableBytes]) + strm.total_out;
		strm.avail_out = [compressed length] - strm.total_out;
		
		deflate(&strm, Z_FINISH);  
		
	} while (strm.avail_out == 0);
	
	deflateEnd(&strm);
	
	[compressed setLength: strm.total_out];
	return [NSData dataWithData: compressed];
}

#pragma mark -

- (NSData *) fastlzInflate
{
	// load file into memory
	unsigned char *compressed = (unsigned char *)[self bytes];
    
    // verify header
    if(compressed[0] != 'F' || compressed[1] != 'T' || compressed[2] != 'L' || compressed[3] != 'Z')
        return self;
    
    // grab the uncompressed length
    unsigned int * uncompressedLength = (unsigned int *)(compressed+4);
	
	void * outBuffer = (void *)malloc( *uncompressedLength );
	if(! outBuffer )
	{
		NSLog(@"Failed to allocate memory for fastlz decompression");
		return [NSData data];
	}	
    
	fastlz_decompress(compressed+8, [self length]-8, outBuffer, *uncompressedLength); 
	
	return [NSData dataWithBytesNoCopy:outBuffer length:*uncompressedLength freeWhenDone:YES];
}

- (NSData *)fastlzDeflate
{
	if ([self length] == 0) return self;
    
	NSMutableData *compressed = [NSMutableData dataWithLength:[self length]*2+8];  // 16K chuncks for expansion
	unsigned char * outPtr = (unsigned char *)[compressed bytes];
    unsigned int * uncompressedLength = (unsigned int *)(outPtr+4);
    
    outPtr[0] = 'F';
    outPtr[1] = 'T';
    outPtr[2] = 'L';
    outPtr[3] = 'Z';
    
    *uncompressedLength = [self length];
    
	int compressedLength = fastlz_compress((const void*)[self bytes], [self length], (void*)(outPtr+8)); 
    	
	[compressed setLength: compressedLength+8];
	return [NSData dataWithData: compressed];
}

#pragma mark -

- (NSData *) lz4Inflate
{
	// load file into memory
	unsigned char *compressed = (unsigned char *)[self bytes];
    
    // verify header
    if(compressed[0] != 'L' || compressed[1] != 'Z' || compressed[2] != '4' || compressed[3] != ' ')
        return self;
    
    // grab the uncompressed length
    unsigned int * uncompressedLength = (unsigned int *)(compressed+4);
	
	void * outBuffer = (void *)malloc( *uncompressedLength );
	if(! outBuffer )
	{
		NSLog(@"Failed to allocate memory for fastlz decompression");
		return [NSData data];
	}
    
    LZ4_decompress_fast((const char*)compressed+8, (char*)outBuffer, *uncompressedLength);
    
	return [NSData dataWithBytesNoCopy:outBuffer length:*uncompressedLength freeWhenDone:YES];
}

- (NSData *)lz4Deflate
{
	if ([self length] == 0) return self;
    
	NSMutableData *compressed = [NSMutableData dataWithLength:[self length]*2+8];  // 16K chuncks for expansion
	unsigned char * outPtr = (unsigned char *)[compressed bytes];
    unsigned int * uncompressedLength = (unsigned int *)(outPtr+4);
    
    outPtr[0] = 'L';
    outPtr[1] = 'Z';
    outPtr[2] = '4';
    outPtr[3] = ' ';
    
    *uncompressedLength = [self length];
    
    int compressedLength = LZ4_compress((const char*)[self bytes], (char*)(outPtr+8), [self length]);
    
    // If our compression is not smaller than the original length, don't use it...
    if(compressedLength > [self length])
        return self;
    
	[compressed setLength: compressedLength+8];
	return [NSData dataWithData: compressed];
}

#pragma mark -

- (NSData *) cczInflate
{
	// load file into memory
	unsigned char *compressed = (unsigned char *)[self bytes];
	
#if USE_ZLIB
	int fileLen = [self length];
#endif
	
	struct CCZHeader *header = (struct CCZHeader*) compressed;
	
	// verify header
	if( header->sig[0] != 'C' || header->sig[1] != 'C' || header->sig[2] != 'Z' || header->sig[3] != '!' ) {
		NSLog(@"Invalid CCZ file");
		return [NSData data];
	}
	
	// verify header version
	uint16_t version = CFSwapInt16BigToHost( header->version );
	if( version > 2 ) {
		NSLog(@"Unsupported CCZ header format");
		return [NSData data];
	}
	
	// verify compression format
	if( CFSwapInt16BigToHost(header->compression_type) != CCZ_COMPRESSION_ZLIB ) {
		NSLog(@"CCZ Unsupported compression method");
		return [NSData data];
	}
	
	uint32_t len = CFSwapInt32BigToHost( header->len );
	const Bytef * source = compressed + sizeof(*header);
	
#if USE_SNAPPY
	size_t slen = 0;
	snappy_uncompressed_length((const char *)source,
							   [self length]-sizeof(*header),
							   &slen);
	
	len = slen;
#endif
	
	uLongf destlen = len;
	
	Bytef * outBuffer = (Bytef *)malloc( len );
	if(! outBuffer )
	{
		NSLog(@"CCZ: Failed to allocate memory for texture");
		return [NSData data];
	}	
	
#if USE_SNAPPY
	snappy_uncompress((const char *)source,
					  [self length]-sizeof(*header),
					  (char *)outBuffer,
					  &slen);
#endif
	
#if USE_FASTLZ
	fastlz_decompress(source, [self length]-sizeof(*header), outBuffer, len); 
#endif
	
#if USE_ZLIB
	int ret = uncompress(outBuffer, &destlen, source, fileLen - sizeof(*header) );
	if( ret != Z_OK )
	{
		NSLog(@"CCZ: Failed to uncompress data");
		free( outBuffer );
		outBuffer = NULL;
		return [NSData data];
	}
#endif
	
	return [NSData dataWithBytesNoCopy:outBuffer length:destlen freeWhenDone:YES];
}

@end
