//
//  PVRUtility.h
//  Planetscapes
//
//  Created by Rocco Bowling on 11/10/10.
//  Copyright 2010 Chimera Software. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface PVRUtility : NSObject
{

}

+ (NSData *) DecompressPVRData:(NSData *)data;
+ (NSData *) CompressDataLossy:(NSData *)data
						OfSize:(NSSize)size
                   AltTileSize:(int*)altTileSize
                 WithWeighting:(NSString *)weighting
                   WithSamples:(int)samplesPerPixel;

@end
