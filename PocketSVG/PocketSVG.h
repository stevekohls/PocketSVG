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
typedef UIBezierPath PS_BEZIER_PATH;
#else
#import <Cocoa/Cocoa.h>
typedef NSBezierPath PS_BEZIER_PATH;
#endif


@interface PocketSVG : NSObject

@property(nonatomic, readonly) PS_BEZIER_PATH *bezier;

- (id)initFromSVGFileNamed:(NSString *)nameOfSVG;

@end
