
@interface NSOffsetData : NSObject
{
    NSData * data;
    NSUInteger offset;
    NSUInteger length;
    
    char * replacementBytes;
    NSUInteger replacementLength;
}

+ (id)dataWithBytesNoCopy:(void *)bytes length:(NSUInteger)length;
+ (id)dataWithBytesNoCopy:(void *)bytes length:(NSUInteger)length freeWhenDone:(BOOL)b;

- (id)initWithBytesNoCopy:(void *)bytes length:(NSUInteger)length freeWhenDone:(BOOL)b;

- (void) setOffset:(NSUInteger)off;
- (void) setLength:(NSUInteger)l;

- (NSOffsetData *) cczInflate;

- (NSData *)data;

- (NSUInteger)length;
- (const void *) bytes;

- (void *) beginReplacementOfSize:(NSUInteger)newSize;
- (void) commitReplacement;

@end



@interface NSData (PackBitsAdditions)

- (NSData *)unpackedBits;

- (NSData*)packedBitsForRange:(NSRange)range skip:(int)skip;
- (NSData*)packedBits;

- (NSData*) packedImageRGBA;
- (NSData *)unpackedImageRGBA;

- (NSData *)unpackedTargaRGBA;
- (NSData*) packedTargaRGBA;

- (NSData *) zlibInflate;
- (NSData *) zlibDeflate;

- (NSData *) cczInflate;

- (NSData *)fastlzDeflate;
- (NSData *) fastlzInflate;

- (NSData *)lz4Deflate;
- (NSData *)lz4Inflate;

@end
