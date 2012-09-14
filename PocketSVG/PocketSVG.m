//
//  PocketSVG.m
//
//  Based on SvgToBezier.m, created by by Martin Haywood on 5/9/11.
//  Attribution-ShareAlike 3.0 Unported (CC BY-SA 3.0) license 2011 Ponderwell.
//
//  NB: Private methods here declared in a class extension, implemented in the class' main implementation block.
//
//  Cleaned up by Bob Monaghan - Glue Tools LLC 6 November 2011
//  Integrated into PocketSVG 10 August 2012
//

#import "PocketSVG.h"
#import "RXMLElement.h"

NSInteger const kMaxPathComplexity  = 1000;
NSInteger const kMaxParameters      = 64;
NSInteger const kMaxTokenLength	    = 64;
NSString* const kSeparatorCharString = @"-,CcMmLlHhVvZzqQaAsS";
NSString* const kCommandCharString   = @"CcMmLlHhVvZzqQaAsS";
unichar   const invalidCommand      = '*';


#pragma mark - Token class interface

@interface Token : NSObject {
	@private
	unichar        _command;
	NSMutableArray *_values;
}

- (id)initWithCommand:(unichar)commandChar;
- (void)addValue:(CGFloat)value;
- (CGFloat)parameter:(NSInteger)index;
- (NSInteger)valence;
@property(nonatomic, assign) unichar command;
@end


#pragma mark - Token class implementation

@implementation Token

@synthesize command = _command;


- (id)initWithCommand:(unichar)commandChar {
	self = [self init];
    if (self) {
		_command = commandChar;
		_values = [[NSMutableArray alloc] initWithCapacity:kMaxParameters];
	}
	return self;
}

- (void)addValue:(CGFloat)value {
	[_values addObject:[NSNumber numberWithDouble:value]];
}

- (CGFloat)parameter:(NSInteger)index {
	return [[_values objectAtIndex:index] doubleValue];
}

- (NSInteger)valence {
	return [_values count];
}

@end


#pragma mark - PocketSVG class private interface

@interface PocketSVG ()
{
    float			_pathScale;
    PS_BEZIER_PATH  *_bezier;
    CGPoint			_lastPoint;
    CGPoint			_lastControlPoint;
    BOOL			_validLastControlPoint;
    NSCharacterSet  *_separatorSet;
    NSCharacterSet  *_commandSet;
    NSMutableArray  *_tokens;
}

- (NSString *) parseSVGFile: (NSString *) filename;

- (NSMutableArray *)parsePath:(NSString *)attr;
- (PS_BEZIER_PATH *)generateBezier:(NSArray *)tokens;

- (void)reset;
- (void)appendSVGMCommand:(Token *)token;
- (void)appendSVGLCommand:(Token *)token;
- (void)appendSVGCCommand:(Token *)token;
- (void)appendSVGSCommand:(Token *)token;

@end


#pragma mark - PocketSVG class implementation

@implementation PocketSVG

@synthesize bezier = _bezier;


#pragma mark - initialization

- (id) initFromSVGFile: (NSString *) filename
{
    self = [super init];
    if (self) {
		_pathScale = 0;
		_separatorSet = [NSCharacterSet characterSetWithCharactersInString:kSeparatorCharString];
		_commandSet = [NSCharacterSet characterSetWithCharactersInString:kCommandCharString];
        [self reset];
        
        NSString *dAttribute = [self parseSVGFile: filename];
        
        _tokens = [self parsePath:dAttribute];
		_bezier = [self generateBezier:_tokens];
    }
    return self;
}


#pragma mark - parsing

/********
 Returns the content of the SVG's d attribute as an NSString
*/
- (NSString *) parseSVGFile: (NSString *) filename
{    
    RXMLElement *rootXML = [RXMLElement elementFromXMLFilename: filename fileExtension: @"svg"];

    if (rootXML == nil)
    {
        NSLog(@"*** PocketSVG Error: Root element nil");
        exit(EXIT_FAILURE);
    }
    if (![rootXML.tag isEqualToString: @"svg"])
    {
        NSLog(@"*** PocketSVG Error: Root element not equal to \"svg\", instead %@:", rootXML.tag);
        exit(EXIT_FAILURE);
    }

    // find the first <path> element
    RXMLElement *pathElement = [rootXML child: @"path"];
    if (pathElement == nil)
    {
        NSLog(@"*** PocketSVG Error: No <path> elements found");
        exit(EXIT_FAILURE);
    }
    
    NSString *dString = [pathElement attribute: @"d"];
    if (dString == nil)
    {
        NSLog(@"*** PocketSVG Error: No \"d\" attribute found");
        exit(EXIT_FAILURE);
    }

    NSArray *dStringWithPossibleWhiteSpace = [dString componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    dString = [dStringWithPossibleWhiteSpace componentsJoinedByString:@""];
    
    //Uncomment the line below to print the raw path data of the SVG file:
    //NSLog(@"*** PocketSVG: Path data of %@ is: %@", nameOfSVG, dString);
    
    return dString;
}


#pragma mark - Private methods

/*
	Tokenise pseudocode, used in parsePath below

	start a token
	eat a character
	while more characters to eat
		add character to token
		while in a token and more characters to eat
			eat character
			add character to token
		add completed token to store
		start a new token
	throw away empty token
*/

- (NSMutableArray *)parsePath:(NSString *)attr
{
	NSMutableArray *stringTokens = [NSMutableArray arrayWithCapacity: kMaxPathComplexity];
	
	NSInteger index = 0;
	while (index < [attr length]) {
		NSMutableString *stringToken = [[NSMutableString alloc] initWithCapacity:kMaxTokenLength];
		[stringToken setString:@""];
		unichar	charAtIndex = [attr characterAtIndex:index];
		if (charAtIndex != ',') {
			[stringToken appendString:[NSString stringWithFormat:@"%c", charAtIndex]];
		}
		if (![_commandSet characterIsMember:charAtIndex] && charAtIndex != ',') {
			while ( (++index < [attr length]) && ![_separatorSet characterIsMember:(charAtIndex = [attr characterAtIndex:index])] ) {
				[stringToken appendString:[NSString stringWithFormat:@"%c", charAtIndex]];
			}
		}
		else {
			index++;
		}
		if ([stringToken length]) {
			[stringTokens addObject:stringToken];
		}
	}
	
	if ([stringTokens count] == 0) {
		NSLog(@"*** PocketSVG Error: Path string is empty of tokens");
		return nil;
	}
	
	// turn the stringTokens array into Tokens, checking validity of tokens as we go
	_tokens = [[NSMutableArray alloc] initWithCapacity:kMaxPathComplexity];
	index = 0;
	NSString *stringToken = [stringTokens objectAtIndex:index];
	unichar command = [stringToken characterAtIndex:0];
	while (index < [stringTokens count]) {
		if (![_commandSet characterIsMember:command]) {
			NSLog(@"*** PocketSVG Error: Path string parse error: found float where expecting command at token %d in path %s.", 
					index, [attr cStringUsingEncoding:NSUTF8StringEncoding]);
			return nil;
		}
		Token *token = [[Token alloc] initWithCommand:command];
		
		// There can be any number of floats after a command. Suck them in until the next command.
		while ((++index < [stringTokens count]) && ![_commandSet characterIsMember:
				(command = [(stringToken = [stringTokens objectAtIndex:index]) characterAtIndex:0])]) {
			
			NSScanner *floatScanner = [NSScanner scannerWithString:stringToken];
			float value;
			if (![floatScanner scanFloat:&value]) {
				NSLog(@"*** PocketSVG Error: Path string parse error: expected float or command at token %d (but found %s) in path %s.", 
					  index, [stringToken cStringUsingEncoding:NSUTF8StringEncoding], [attr cStringUsingEncoding:NSUTF8StringEncoding]);
				return nil;
			}
			// Maintain scale.
			_pathScale = (abs(value) > _pathScale) ? abs(value) : _pathScale;
			[token addValue:value];
		}
		
		// now we've reached a command or the end of the stringTokens array
		[_tokens	addObject:token];
	}
	//[stringTokens release];
	return _tokens;
}

- (PS_BEZIER_PATH *)generateBezier:(NSArray *)inTokens
{
	_bezier = [[PS_BEZIER_PATH alloc] init];
	[self reset];
	for (Token *thisToken in inTokens) {
		unichar command = [thisToken command];
		switch (command) {
			case 'M':
			case 'm':
				[self appendSVGMCommand:thisToken];
				break;
			case 'L':
			case 'l':
			case 'H':
			case 'h':
			case 'V':
			case 'v':
				[self appendSVGLCommand:thisToken];
				break;
			case 'C':
			case 'c':
				[self appendSVGCCommand:thisToken];
				break;
			case 'S':
			case 's':
				[self appendSVGSCommand:thisToken];
				break;
			case 'Z':
			case 'z':
				[_bezier closePath];
				break;
			default:
				NSLog(@"*** PocketSVG Error: Cannot process command : '%c'", command);
				break;
		}
	}
	return _bezier;
}

- (void)reset
{
	_lastPoint = CGPointMake(0, 0);
	_validLastControlPoint = NO;
}

- (void)appendSVGMCommand:(Token *)token
{
	_validLastControlPoint = NO;
	NSInteger index = 0;
	BOOL first = YES;
	while (index < [token valence]) {
		CGFloat x = [token parameter:index] + ([token command] == 'm' ? _lastPoint.x : 0);
		if (++index == [token valence]) {
			NSLog(@"*** PocketSVG Error: Invalid parameter count in M style token");
			return;
		}
		CGFloat y = [token parameter:index] + ([token command] == 'm' ? _lastPoint.y : 0);
		_lastPoint = CGPointMake(x, y);
		if (first) {
			[_bezier moveToPoint:_lastPoint];
			first = NO;
		}
		else {
#ifdef TARGET_OS_IPHONE
			[_bezier addLineToPoint:_lastPoint];
#else
			[_bezier lineToPoint:NSPointFromCGPoint(_lastPoint)];
#endif
		}
		index++;
	}
}

- (void)appendSVGLCommand:(Token *)token
{
	_validLastControlPoint = NO;
	NSInteger index = 0;
	while (index < [token valence]) {
		CGFloat x = 0;
		CGFloat y = 0;
		switch ( [token command] ) {
			case 'l':
				x = _lastPoint.x;
				y = _lastPoint.y;
			case 'L':
				x += [token parameter:index];
				if (++index == [token valence]) {
					NSLog(@"*** PocketSVG Error: Invalid parameter count in L style token");
					return;
				}
				y += [token parameter:index];
				break;
			case 'h' :
				x = _lastPoint.x;				
			case 'H' :
				x += [token parameter:index];
				y = _lastPoint.y;
				break;
			case 'v' :
				y = _lastPoint.y;
			case 'V' :
				y += [token parameter:index];
				x = _lastPoint.x;
				break;
			default:
				NSLog(@"*** PocketSVG Error: Unrecognised L style command.");
				return;
		}
		_lastPoint = CGPointMake(x, y);
#ifdef TARGET_OS_IPHONE
		[_bezier addLineToPoint:_lastPoint];
#else
		[_bezier lineToPoint:NSPointFromCGPoint(_lastPoint)];
#endif
		index++;
	}
}

- (void)appendSVGCCommand:(Token *)token
{
	NSInteger index = 0;
	while ((index + 5) < [token valence]) {  // we must have 6 floats here (x1, y1, x2, y2, x, y).
		CGFloat x1 = [token parameter:index++] + ([token command] == 'c' ? _lastPoint.x : 0);
		CGFloat y1 = [token parameter:index++] + ([token command] == 'c' ? _lastPoint.y : 0);
		CGFloat x2 = [token parameter:index++] + ([token command] == 'c' ? _lastPoint.x : 0);
		CGFloat y2 = [token parameter:index++] + ([token command] == 'c' ? _lastPoint.y : 0);
		CGFloat x  = [token parameter:index++] + ([token command] == 'c' ? _lastPoint.x : 0);
		CGFloat y  = [token parameter:index++] + ([token command] == 'c' ? _lastPoint.y : 0);
		_lastPoint = CGPointMake(x, y);
#ifdef TARGET_OS_IPHONE
		[_bezier addCurveToPoint:_lastPoint 
				  controlPoint1:CGPointMake(x1,y1) 
				  controlPoint2:CGPointMake(x2, y2)];
#else
		[_bezier curveToPoint:NSPointFromCGPoint(_lastPoint)
			   controlPoint1:NSPointFromCGPoint(CGPointMake(x1,y1))
			   controlPoint2:NSPointFromCGPoint(CGPointMake(x2, y2)];
#endif
        _lastControlPoint = CGPointMake(x2, y2);
		_validLastControlPoint = YES;
	}
	if (index == 0) {
		NSLog(@"*** PocketSVG Error: Insufficient parameters for C command");
	}
}

- (void)appendSVGSCommand:(Token *)token
{
	if (!_validLastControlPoint) {
		NSLog(@"*** PocketSVG Error: Invalid last control point in S command");
	}
	NSInteger index = 0;
	while ((index + 3) < [token valence]) {  // we must have 4 floats here (x2, y2, x, y).
		CGFloat x1 = _lastPoint.x + (_lastPoint.x - _lastControlPoint.x); // + ([token command] == 's' ? lastPoint.x : 0);
		CGFloat y1 = _lastPoint.y + (_lastPoint.y - _lastControlPoint.y); // + ([token command] == 's' ? lastPoint.y : 0);
		CGFloat x2 = [token parameter:index++] + ([token command] == 's' ? _lastPoint.x : 0);
		CGFloat y2 = [token parameter:index++] + ([token command] == 's' ? _lastPoint.y : 0);
		CGFloat x  = [token parameter:index++] + ([token command] == 's' ? _lastPoint.x : 0);
		CGFloat y  = [token parameter:index++] + ([token command] == 's' ? _lastPoint.y : 0);
		_lastPoint = CGPointMake(x, y);
#ifdef TARGET_OS_IPHONE
		[_bezier addCurveToPoint:_lastPoint 
				  controlPoint1:CGPointMake(x1,y1)
				  controlPoint2:CGPointMake(x2, y2)];
#else
		[_bezier curveToPoint:NSPointFromCGPoint(_lastPoint)
			   controlPoint1:NSPointFromCGPoint(CGPointMake(x1,y1)) 
			   controlPoint2:NSPointFromCGPoint(CGPointMake(x2, y2)];
#endif
		_lastControlPoint = CGPointMake(x2, y2);
		_validLastControlPoint = YES;
	}
	if (index == 0) {
		NSLog(@"*** PocketSVG Error: Insufficient parameters for S command");
	}
}

//- (CGPoint)bezierPoint:(CGPoint)svgPoint
//{
//	CGPoint newPoint;
//    
// 	CGFloat scaleX = viewBox.size.width / _pathScale;
//	CGFloat scaleY = viewBox.size.height / _pathScale;
//
//    newPoint.x = (svgPoint.x * scaleX) + viewBox.origin.x;
//    newPoint.y = (svgPoint.y * scaleY) + viewBox.origin.y;
//	return svgPoint;
//}


@end
