//
//  PocketSVG.h
//
//  Based on SvgToBezier.h, created by Martin Haywood on 5/9/11.
//  Attribution-ShareAlike 3.0 Unported (CC BY-SA 3.0) license 2011 Ponderwell.
//
//  Cleaned up by Bob Monaghan - Glue Tools LLC 6 November 2011
//  Integrated into PocketSVG 10 August 2012
//

#ifdef TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
typedef UIBezierPath BEZIER_PATH_TYPE;
#else
#import <Cocoa/Cocoa.h>
typedef NSBezierPath BEZIER_PATH_TYPE;
#endif

#import "RXMLElement.h"

@interface PocketSVG : NSObject

@property(nonatomic, readonly) BEZIER_PATH_TYPE *bezier;

- (id) initFromSVGFile: (NSString *) filename;

@end
