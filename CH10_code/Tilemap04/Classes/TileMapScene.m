//
//  HelloWorldLayer.m
//  Tilemap
//
//  Created by Steffen Itterheim on 28.08.10.
//  Copyright Steffen Itterheim 2010. All rights reserved.
//

#import "TileMapScene.h"
#import "SimpleAudioEngine.h"

@implementation TileMapLayer

+(id) scene
{
	CCScene *scene = [CCScene node];
	TileMapLayer *layer = [TileMapLayer node];
	[scene addChild: layer];
	return scene;
}

-(id) init
{
	if ((self = [super init]))
	{
		CCTMXTiledMap* tileMap = [CCTMXTiledMap tiledMapWithTMXFile:@"orthogonal.tmx"];
		tileMapHeightInPixels = tileMap.mapSize.height * tileMap.tileSize.height;
		[self addChild:tileMap z:-1 tag:TileMapNode];
		
		// Use a negative offset to set the tilemap's start position
		//tileMap.position = CGPointMake(-160, -120);

		// hide the event layer, we only need this information for code, not to display it
		CCTMXLayer* eventLayer = [tileMap layerNamed:@"GameEventLayer"];
		eventLayer.visible = NO;

		CCTMXLayer* winterLayer = [tileMap layerNamed:@"WinterLayer"];
		winterLayer.visible = NO;

		self.isTouchEnabled = YES;

		[[SimpleAudioEngine sharedEngine] preloadEffect:@"alien-sfx.caf"];
	}

	return self;
}

-(CGPoint) locationFromTouch:(UITouch*)touch
{
	CGPoint touchLocation = [touch locationInView: [touch view]];
	return [[CCDirector sharedDirector] convertToGL:touchLocation];
}

-(CGPoint) locationFromTouches:(NSSet*)touches
{
	return [self locationFromTouch:[touches anyObject]];
}

-(CGPoint) tilePosFromLocation:(CGPoint)location tileMap:(CCTMXTiledMap*)tileMap
{
	// Tilemap position must be added as an offset, in case the tilemap position is not at 0,0 due to scrolling
	CGPoint pos = ccpSub(location, tileMap.position);
	
	// Cast to int makes sure that result is in whole numbers, tile coordinates will be used as array indices
	pos.x = (int)(pos.x / tileMap.tileSize.width);
	pos.y = (int)((tileMapHeightInPixels - pos.y) / tileMap.tileSize.height);
	
	CCLOG(@"touch at (%.0f, %.0f) is at tileCoord (%i, %i)", location.x, location.y, (int)pos.x, (int)pos.y);
	NSAssert(pos.x >= 0 && pos.y >= 0 && pos.x < tileMap.mapSize.width && pos.y < tileMap.mapSize.height,
			 @"%@: coordinates (%i, %i) out of bounds!", NSStringFromSelector(_cmd), (int)pos.x, (int)pos.y);
	
	return pos;
}

-(void) centerTileMapOnTileCoord:(CGPoint)tilePos tileMap:(CCTMXTiledMap*)tileMap
{
	// center tilemap on the given tile pos
	CGSize screenSize = [[CCDirector sharedDirector] winSize];
	CGPoint screenCenter = CGPointMake(screenSize.width * 0.5f, screenSize.height * 0.5f);
	
	// tile coordinates are counted from upper left corner, this maps coordinates to lower left corner
	tilePos.y = (tileMap.mapSize.height - 1) - tilePos.y;
	
	// point is now at lower left corner of the screen
	CGPoint scrollPosition = CGPointMake(-(tilePos.x * tileMap.tileSize.width), 
										  -(tilePos.y * tileMap.tileSize.height));
	
	// offset point to center of screen and center of tile
	scrollPosition.x += screenCenter.x - tileMap.tileSize.width * 0.5f;
	scrollPosition.y += screenCenter.y - tileMap.tileSize.height * 0.5f;

	// make sure tilemap scrolling stops at the tilemap borders
	scrollPosition.x = MIN(scrollPosition.x, 0);
	scrollPosition.x = MAX(scrollPosition.x, -screenSize.width);
	scrollPosition.y = MIN(scrollPosition.y, 0);
	scrollPosition.y = MAX(scrollPosition.y, -screenSize.height);
	
	CCLOG(@"tilePos: (%i, %i) moveTo: (%.0f, %.0f)", (int)tilePos.x, (int)tilePos.y, scrollPosition.x, scrollPosition.y);
	
	CCAction* move = [CCMoveTo actionWithDuration:0.2f position:scrollPosition];
	[tileMap stopAllActions];
	[tileMap runAction:move];
}

-(CGRect) getRectFromObjectProperties:(NSDictionary*)dict tileMap:(CCTMXTiledMap*)tileMap
{
	float x, y, width, height;
	x = [[dict valueForKey:@"x"] floatValue] + tileMap.position.x;
	y = [[dict valueForKey:@"y"] floatValue] + tileMap.position.y;
	width = [[dict valueForKey:@"width"] floatValue];
	height = [[dict valueForKey:@"height"] floatValue];
	
	return CGRectMake(x, y, width, height);
}

-(void) ccTouchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
	CCNode* node = [self getChildByTag:TileMapNode];
	NSAssert([node isKindOfClass:[CCTMXTiledMap class]], @"not a CCTMXTiledMap");
	CCTMXTiledMap* tileMap = (CCTMXTiledMap*)node;

	// get the position in tile coordinates from the touch location
	CGPoint touchLocation = [self locationFromTouches:touches];
	CGPoint tilePos = [self tilePosFromLocation:touchLocation tileMap:tileMap];

	// move tilemap so that touched tiles is at center of screen
	[self centerTileMapOnTileCoord:tilePos tileMap:tileMap];

	// Check if the touch was on water (eg. tiles with isWater property drawn in GameEventLayer)
	bool isTouchOnWater = NO;
	CCTMXLayer* eventLayer = [tileMap layerNamed:@"GameEventLayer"];
	int tileGID = [eventLayer tileGIDAt:tilePos];
	
	if (tileGID != 0)
	{
		NSDictionary* properties = [tileMap propertiesForGID:tileGID];
		if (properties)
		{
			NSString* isWaterProperty = [properties valueForKey:@"isWater"];
			isTouchOnWater = ([isWaterProperty boolValue] == YES);
		}
	}

	// Check if the touch was within one of the rectangle objects
	CCTMXObjectGroup* objectLayer = [tileMap objectGroupNamed:@"ObjectLayer"];
	NSAssert([objectLayer isKindOfClass:[CCTMXObjectGroup class]], @"ObjectLayer not found or not a CCTMXObjectGroup");

	bool isTouchInRectangle = NO;
	int numObjects = [[objectLayer objects] count];
	for (int i = 0; i < numObjects; i++)
	{
		NSDictionary* properties = [[objectLayer objects] objectAtIndex:i];
		CGRect rect = [self getRectFromObjectProperties:properties tileMap:tileMap];

		if (CGRectContainsPoint(rect, touchLocation))
		{
			isTouchInRectangle = YES;
			break;
		}
	}
	
	// decide what to do depending on where the touch was ...
	if (isTouchOnWater)
	{
		[[SimpleAudioEngine sharedEngine] playEffect:@"alien-sfx.caf"];
	}
	else if (isTouchInRectangle)
	{
		CCParticleSystem* system = [CCQuadParticleSystem particleWithFile:@"fx-explosion.plist"];
		system.autoRemoveOnFinish = YES;
		system.position = touchLocation;
		[self addChild:system z:1];
	}
	else
	{
		// get the winter layer and toggle its visibility
		//CCTMXLayer* winterLayer = [tileMap layerNamed:@"WinterLayer"];
		//winterLayer.visible = !winterLayer.visible;
		
		// remove the touched tile
		//[winterLayer removeTileAt:tilePos];
		
		// adds a given tile
		//tileGID = [winterLayer tileGIDAt:CGPointMake(0, 19)];
		//[winterLayer setTileGID:tileGID at:tilePos];
	}
}

#ifdef DEBUG
-(void) drawRect:(CGRect)rect
{
	// Because there is no specialized rect drawing method the rect is drawn using 4 lines
	CGPoint pos1, pos2, pos3, pos4;
	pos1 = CGPointMake(rect.origin.x, rect.origin.y);
	pos2 = CGPointMake(rect.origin.x, rect.origin.y + rect.size.height);
	pos3 = CGPointMake(rect.origin.x + rect.size.width, rect.origin.y + rect.size.height);
	pos4 = CGPointMake(rect.origin.x + rect.size.width, rect.origin.y);
	
	ccDrawLine(pos1, pos2);
	ccDrawLine(pos2, pos3);
	ccDrawLine(pos3, pos4);
	ccDrawLine(pos4, pos1);
}

// Alternative, slightly faster version of the drawRect method
// Based on the ccDrawLine code and modified to draw a CGRect
-(void) drawRectFaster:(CGRect)rect
{
	CGPoint pos1, pos2, pos3, pos4;
	pos1 = CGPointMake(rect.origin.x, rect.origin.y);
	pos2 = CGPointMake(rect.origin.x, rect.origin.y + rect.size.height);
	pos3 = CGPointMake(rect.origin.x + rect.size.width, rect.origin.y + rect.size.height);
	pos4 = CGPointMake(rect.origin.x + rect.size.width, rect.origin.y);
	
	CGPoint vertices[8];
	vertices[0] = pos1;
	vertices[1] = pos2;
	vertices[2] = pos2;
	vertices[3] = pos3;
	vertices[4] = pos3;
	vertices[5] = pos4;
	vertices[6] = pos4;
	vertices[7] = pos1;
	
	// Default GL states: GL_TEXTURE_2D, GL_VERTEX_ARRAY, GL_COLOR_ARRAY, GL_TEXTURE_COORD_ARRAY
	// Needed states: GL_VERTEX_ARRAY, 
	// Unneeded states: GL_TEXTURE_2D, GL_TEXTURE_COORD_ARRAY, GL_COLOR_ARRAY	
	glDisable(GL_TEXTURE_2D);
	glDisableClientState(GL_TEXTURE_COORD_ARRAY);
	glDisableClientState(GL_COLOR_ARRAY);
	
	glVertexPointer(2, GL_FLOAT, 0, vertices);	
	glDrawArrays(GL_LINES, 0, 8);
	
	// restore default state
	glEnableClientState(GL_COLOR_ARRAY);
	glEnableClientState(GL_TEXTURE_COORD_ARRAY);
	glEnable(GL_TEXTURE_2D);	
}

// Draw the object rectangles for debugging and illustration purposes.
-(void) draw
{
	CCNode* node = [self getChildByTag:TileMapNode];
	NSAssert([node isKindOfClass:[CCTMXTiledMap class]], @"not a CCTMXTiledMap");
	CCTMXTiledMap* tileMap = (CCTMXTiledMap*)node;
	
	// get the object layer
	CCTMXObjectGroup* objectLayer = [tileMap objectGroupNamed:@"ObjectLayer"];
	NSAssert([objectLayer isKindOfClass:[CCTMXObjectGroup class]], @"ObjectLayer not found or not a CCTMXObjectGroup");
	
	// make the line 3 pixels thick
	glLineWidth(3.0f);
	glColor4f(1, 0, 1, 1);
	
	int numObjects = [[objectLayer objects] count];
	for (int i = 0; i < numObjects; i++)
	{
		NSDictionary* properties = [[objectLayer objects] objectAtIndex:i];
		CGRect rect = [self getRectFromObjectProperties:properties tileMap:tileMap];
		[self drawRectFaster:rect];
	}

	// show center screen position
	CGSize screenSize = [[CCDirector sharedDirector] winSize];
	CGPoint center = CGPointMake(screenSize.width * 0.5f, screenSize.height * 0.5f);
	ccDrawCircle(center, 10, 0, 8, NO);
	
	// reset line width & color as to not interfere with draw code in other nodes that draws lines
	glLineWidth(1.0f);
	glColor4f(1, 1, 1, 1);
}
#endif

@end
