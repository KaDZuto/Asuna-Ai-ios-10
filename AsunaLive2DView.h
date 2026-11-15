//
//  AsunaLive2DView.h
//  AsunaLiquidGlass
//
//  Native Live2D Cubism 2.1 Character View using OpenGL ES 1.1 / GLKit
//

#import <UIKit/UIKit.h>

@interface AsunaLive2DView : UIView

- (void)loadModelNamed:(NSString *)modelName;
- (void)loadModelFromDirectory:(NSString *)modelDir jsonName:(NSString *)jsonName;
- (void)setLipSyncValue:(CGFloat)value;
- (void)setExpressionNamed:(NSString *)name;
- (void)triggerTapAtPoint:(CGPoint)pt;
- (void)lookAtNormalizedPoint:(CGPoint)pt; // x,y in [-1..1]
- (void)resetLookAt;
- (void)startIdleAnimation;

// Full <live2d> action dispatch from PC version
- (void)applyLive2DAction:(NSDictionary *)action;
- (void)playGestureNamed:(NSString *)name side:(NSString *)side intensity:(CGFloat)intensity speed:(CGFloat)speed;

@property (nonatomic, assign, readonly) BOOL isModelLoaded;
@property (nonatomic, copy, readonly) NSString *currentModelId;
@property (nonatomic, assign) NSInteger displayPreset; // 0 full, 1 skirt-to-head, 2 close

@end
