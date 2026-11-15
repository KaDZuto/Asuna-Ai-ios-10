//
//  AsunaLive2DView.mm
//  AsunaLiquidGlass
//
//  Native Live2D Cubism 2.1 Character View using OpenGL ES 1.1 / GLKit
//

#import "AsunaLive2DView.h"
#import <GLKit/GLKit.h>
#import <OpenGLES/ES1/gl.h>
#import <OpenGLES/ES1/glext.h>
#import <QuartzCore/QuartzCore.h>
#include <map>
#include <vector>
#include <string>
#include <cmath>

#define L2D_TARGET_IPHONE 1
#include "Live2D.h"
#include "Live2DModelIPhone.h"
#include "motion/Live2DMotion.h"
#include "motion/MotionQueueManager.h"
#include "framework/L2DPhysics.h"
#include "framework/L2DExpressionMotion.h"
#include "framework/L2DEyeBlink.h"
#include "util/UtSystem.h"

@interface AsunaLive2DView () <GLKViewDelegate> {
    live2d::Live2DModelIPhone *_live2DModel;
    live2d::MotionQueueManager *_motionManager;
    live2d::MotionQueueManager *_expressionManager;
    live2d::framework::L2DPhysics *_physics;
    live2d::framework::L2DEyeBlink *_eyeBlink;
    
    std::map<std::string, live2d::Live2DMotion *> _motions;
    std::map<std::string, live2d::framework::L2DExpressionMotion *> _expressions;
    
    std::vector<GLuint> _glTextures;
    
    float _targetLipSync;
    float _currentLipSync;
    
    // Live2D dynamic parameters from LLM/SmallTalk
    float _targetHeadX;
    float _currentHeadX;
    float _targetHeadY;
    float _currentHeadY;
    float _targetBodyAngle;
    float _currentBodyAngle;
    float _targetEyeOpen;
    float _currentEyeOpen;
    
    // Procedural gesture simulation
    std::string _activeGestureName;
    NSTimeInterval _gestureStartTime;
    NSTimeInterval _gestureDuration;
    float _gestureIntensity;
    std::string _gestureSide;
    
    BOOL _isSwitchingModel;
    NSRecursiveLock *_renderLock;
    
    NSTimeInterval _idleStartTime;
    NSTimeInterval _nextIdleSwitchTime;
    NSTimeInterval _nextExpressionTime;
    NSTimeInterval _nextLifeNudgeTime;
    NSTimeInterval _lastPanTime;
}

@property (nonatomic, strong) EAGLContext *context;
@property (nonatomic, strong) GLKView *glkView;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, copy, readwrite) NSString *currentModelId;
@property (nonatomic, assign, readwrite) BOOL isModelLoaded;

@end

@implementation AsunaLive2DView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        self.userInteractionEnabled = YES;
        _renderLock = [[NSRecursiveLock alloc] init];
        _isSwitchingModel = NO;
        _idleStartTime = [NSDate timeIntervalSinceReferenceDate];
        _nextIdleSwitchTime = _idleStartTime + 4.0;
        _nextExpressionTime = _idleStartTime + 6.0;
        _nextLifeNudgeTime = _idleStartTime + 3.0;
        _lastPanTime = 0;
        _targetHeadX = _currentHeadX = 0;
        _targetHeadY = _currentHeadY = 0;
        _targetBodyAngle = _currentBodyAngle = 0;
        _targetEyeOpen = _currentEyeOpen = 1.0f;
        _targetLipSync = _currentLipSync = 0;
        _gestureDuration = 0;
        
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            live2d::Live2D::init();
        });
        
        _context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES1];
        if (!_context) {
            NSLog(@"[Live2D] Failed to create OpenGLES 1 context");
            return self;
        }
        
        _glkView = [[GLKView alloc] initWithFrame:self.bounds context:_context];
        _glkView.delegate = self;
        _glkView.backgroundColor = [UIColor clearColor];
        _glkView.opaque = NO;
        _glkView.drawableColorFormat = GLKViewDrawableColorFormatRGBA8888;
        _glkView.drawableDepthFormat = GLKViewDrawableDepthFormatNone;
        _glkView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_glkView];
        
        _motionManager = new live2d::MotionQueueManager();
        _expressionManager = new live2d::MotionQueueManager();
        _eyeBlink = new live2d::framework::L2DEyeBlink();
        
        _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(onRenderLoop)];
        _displayLink.preferredFramesPerSecond = 60;
        [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _glkView.frame = self.bounds;
}

- (void)dealloc {
    [_displayLink invalidate];
    [self releaseModelResources];
    if (_motionManager) delete _motionManager;
    if (_expressionManager) delete _expressionManager;
    if (_eyeBlink) delete _eyeBlink;
}

- (void)releaseModelResources {
    [_renderLock lock];
    _isModelLoaded = NO;
    _isSwitchingModel = YES;
    
    if (_motionManager) _motionManager->stopAllMotions();
    if (_expressionManager) _expressionManager->stopAllMotions();
    _activeGestureName.clear();
    _currentHeadX = _currentHeadY = _currentBodyAngle = 0;
    _targetHeadX = _targetHeadY = _targetBodyAngle = 0;
    _currentLipSync = _targetLipSync = 0;
    _currentEyeOpen = _targetEyeOpen = 1.0f;
    
    [EAGLContext setCurrentContext:_context];
    for (GLuint tex : _glTextures) {
        if (tex != 0) {
            glDeleteTextures(1, &tex);
        }
    }
    _glTextures.clear();
    
    for (auto it = _motions.begin(); it != _motions.end(); ++it) {
        if (it->second) delete it->second;
    }
    _motions.clear();
    
    for (auto it = _expressions.begin(); it != _expressions.end(); ++it) {
        if (it->second) delete it->second;
    }
    _expressions.clear();
    
    if (_physics) {
        delete _physics;
        _physics = nullptr;
    }
    
    if (_live2DModel) {
        delete _live2DModel;
        _live2DModel = nullptr;
    }
    [_renderLock unlock];
}

- (void)loadModelNamed:(NSString *)modelName {
    if (!modelName || modelName.length == 0) modelName = @"asuna_01";
    
    NSString *bundleRoot = [[NSBundle mainBundle] bundlePath];
    NSArray *candidates = @[
        [bundleRoot stringByAppendingPathComponent:[NSString stringWithFormat:@"models/%@", modelName]],
        [bundleRoot stringByAppendingPathComponent:[NSString stringWithFormat:@"www/models/%@", modelName]],
        [NSString stringWithFormat:@"/Applications/AsunaLiquidGlass.app/models/%@", modelName],
        [NSString stringWithFormat:@"/Applications/AsunaLiquidGlass.app/www/models/%@", modelName],
        [NSString stringWithFormat:@"/home/alexius/Projects/ios/LinuxiOSBuilder-full-starter/LinuxiOSBuilder/AsunaLiquidGlass/models/%@", modelName]
    ];
    
    NSString *selectedDir = nil;
    for (NSString *dir in candidates) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:dir]) {
            selectedDir = dir;
            break;
        }
    }
    
    if (!selectedDir) {
        NSLog(@"[Live2D] Model directory for %@ not found in candidates", modelName);
        return;
    }
    
    NSString *jsonName = [NSString stringWithFormat:@"%@.model.json", modelName];
    [self loadModelFromDirectory:selectedDir jsonName:jsonName];
}

- (void)loadModelFromDirectory:(NSString *)modelDir jsonName:(NSString *)jsonName {
    [_renderLock lock];
    _isSwitchingModel = YES;
    
    [self releaseModelResources];
    [EAGLContext setCurrentContext:_context];
    
    NSString *jsonPath = [modelDir stringByAppendingPathComponent:jsonName];
    NSData *jsonData = [NSData dataWithContentsOfFile:jsonPath];
    if (!jsonData) {
        NSLog(@"[Live2D] Could not read model.json at %@", jsonPath);
        _isSwitchingModel = NO;
        [_renderLock unlock];
        return;
    }
    
    NSError *err = nil;
    NSDictionary *root = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&err];
    if (!root || err) {
        NSLog(@"[Live2D] JSON parse error: %@", err);
        _isSwitchingModel = NO;
        [_renderLock unlock];
        return;
    }
    
    // 1. Model .moc
    NSString *mocRelative = root[@"model"];
    NSString *mocPath = [modelDir stringByAppendingPathComponent:mocRelative];
    _live2DModel = live2d::Live2DModelIPhone::loadModel([mocPath UTF8String]);
    if (!_live2DModel) {
        NSLog(@"[Live2D] Failed to load moc at %@", mocPath);
        _isSwitchingModel = NO;
        [_renderLock unlock];
        return;
    }
    
    // 2. Textures: Straight Alpha with No Mipmap Seams & Clamp-to-Edge
    NSArray *textures = root[@"textures"];
    int texIndex = 0;
    for (NSString *texRel in textures) {
        NSString *texPath = [modelDir stringByAppendingPathComponent:texRel];
        
        // Disable automatic premultiplication and mipmaps to eliminate border seams
        NSDictionary *loaderOptions = @{
            GLKTextureLoaderApplyPremultiplication: @(NO),
            GLKTextureLoaderGenerateMipmaps: @(NO)
        };
        GLKTextureInfo *texInfo = [GLKTextureLoader textureWithContentsOfFile:texPath
                                                                     options:loaderOptions
                                                                       error:&err];
        if (texInfo) {
            glBindTexture(GL_TEXTURE_2D, texInfo.name);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
            
            _live2DModel->setTexture(texIndex, texInfo.name);
            _glTextures.push_back(texInfo.name);
        } else {
            NSLog(@"[Live2D] Failed to load texture: %@ (%@)", texPath, err);
        }
        texIndex++;
    }
    
    // 3. Physics
    NSString *physicsRel = root[@"physics"];
    if (physicsRel) {
        NSString *physicsPath = [modelDir stringByAppendingPathComponent:physicsRel];
        NSData *pData = [NSData dataWithContentsOfFile:physicsPath];
        if (pData) {
            _physics = live2d::framework::L2DPhysics::load(pData.bytes, (int)pData.length);
        }
    }
    
    // 4. Expressions
    NSArray *expressions = root[@"expressions"];
    for (NSDictionary *expDict in expressions) {
        NSString *name = expDict[@"name"];
        NSString *fileRel = expDict[@"file"];
        if (name && fileRel) {
            NSString *expPath = [modelDir stringByAppendingPathComponent:fileRel];
            NSData *eData = [NSData dataWithContentsOfFile:expPath];
            if (eData) {
                live2d::framework::L2DExpressionMotion *expMotion = live2d::framework::L2DExpressionMotion::loadJson(eData.bytes, (int)eData.length);
                if (expMotion) {
                    _expressions[[name UTF8String]] = expMotion;
                }
            }
        }
    }
    
    // 5. Motions
    NSDictionary *motionsDict = root[@"motions"];
    [motionsDict enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        NSString *groupName = (NSString *)key;
        NSArray *groupList = (NSArray *)obj;
        for (NSInteger mIdx = 0; mIdx < groupList.count; mIdx++) {
            NSDictionary *mInfo = groupList[mIdx];
            NSString *fileRel = mInfo[@"file"];
            if (fileRel) {
                NSString *motionPath = [modelDir stringByAppendingPathComponent:fileRel];
                NSData *mData = [NSData dataWithContentsOfFile:motionPath];
                if (mData) {
                    live2d::Live2DMotion *motion = live2d::Live2DMotion::loadMotion(mData.bytes, (int)mData.length);
                    if (motion) {
                        std::string motionKey = [groupName UTF8String];
                        if (motionKey.empty()) motionKey = "tap";
                        if (mIdx > 0) motionKey += "_" + std::to_string(mIdx);
                        _motions[motionKey] = motion;
                    }
                }
            }
        }
    }];
    
    _currentModelId = jsonName.stringByDeletingPathExtension.stringByDeletingPathExtension;
    _isModelLoaded = YES;
    _isSwitchingModel = NO;
    _idleStartTime = [NSDate timeIntervalSinceReferenceDate];
    _nextExpressionTime = _idleStartTime + 20.0 + (arc4random_uniform(1500) / 100.0);
    _nextLifeNudgeTime = _idleStartTime + 3.0;
    
    [self startIdleAnimation];
    if (_expressions.find("F_NOMAL") != _expressions.end()) [self setExpressionNamed:@"F_NOMAL"];
    else if (_expressions.find("F_FUN_SMILE") != _expressions.end()) [self setExpressionNamed:@"F_FUN_SMILE"];
    else if (!_expressions.empty()) [self setExpressionNamed:[NSString stringWithUTF8String:_expressions.begin()->first.c_str()]];
    [_renderLock unlock];
    
    NSLog(@"[Live2D] Successfully loaded native model %@ (%lu textures, %lu motions, %lu expressions)",
          _currentModelId, _glTextures.size(), _motions.size(), _expressions.size());
}

- (void)startIdleAnimation {
    if (!_live2DModel || !_motionManager) return;
    std::vector<std::string> idleKeys;
    for (auto &p : _motions) {
        if (p.first.find("idle") != std::string::npos) idleKeys.push_back(p.first);
    }
    if (idleKeys.empty()) {
        for (auto &p : _motions) idleKeys.push_back(p.first);
    }
    if (idleKeys.empty()) return;
    std::string key = idleKeys[arc4random_uniform((uint32_t)idleKeys.size())];
    auto it = _motions.find(key);
    if (it != _motions.end() && it->second) {
        it->second->setLoop(false);
        _motionManager->startMotion(it->second, false);
    }
    _nextIdleSwitchTime = [NSDate timeIntervalSinceReferenceDate] + 8.0 + (arc4random_uniform(700) / 100.0);
}

- (void)setLipSyncValue:(CGFloat)value {
    _targetLipSync = (float)value;
}

- (void)setExpressionNamed:(NSString *)name {
    if (!_expressionManager || !name) return;
    auto it = _expressions.find([name UTF8String]);
    if (it != _expressions.end() && it->second) {
        _expressionManager->startMotion(it->second, false);
    }
}

- (void)triggerTapAtPoint:(CGPoint)pt {
    [_renderLock lock];
    if (!_live2DModel || !_isModelLoaded) {
        [_renderLock unlock];
        return;
    }
    
    // Play random non-idle reaction motion (prefer tap/reaction groups)
    std::vector<std::string> tapKeys;
    for (auto &pair : _motions) {
        const std::string &k = pair.first;
        if (k.find("idle") == std::string::npos) {
            tapKeys.push_back(k);
        }
    }
    if (!tapKeys.empty()) {
        int idx = arc4random_uniform((uint32_t)tapKeys.size());
        auto it = _motions.find(tapKeys[idx]);
        if (it != _motions.end() && it->second) {
            it->second->setLoop(false);
            _motionManager->startMotion(it->second, false);
        }
    }
    
    // Pick random expression from all loaded
    if (!_expressions.empty()) {
        int idx = arc4random_uniform((uint32_t)_expressions.size());
        auto it = _expressions.begin();
        std::advance(it, idx);
        [self setExpressionNamed:[NSString stringWithUTF8String:it->first.c_str()]];
    }
    // small reactive look
    CGFloat nx = ((pt.x / MAX(1.0, self.bounds.size.width)) * 2.0 - 1.0);
    CGFloat ny = (1.0 - (pt.y / MAX(1.0, self.bounds.size.height)) * 2.0);
    _targetHeadX = (float)fmax(-1.0,fmin(1.0,nx)) * 12.0f;
    _targetHeadY = (float)fmax(-1.0,fmin(1.0,ny)) * 10.0f;
    _nextIdleSwitchTime = [NSDate timeIntervalSinceReferenceDate] + 3.0;
    [_renderLock unlock];
}


- (void)applyLive2DAction:(NSDictionary *)action {
    if (!action) return;
    [_renderLock lock];
    if (!_isModelLoaded || !_live2DModel) {
        [_renderLock unlock];
        return;
    }
    
    NSString *expression = action[@"expression"];
    if ([expression isKindOfClass:[NSString class]] && expression.length > 0) {
        [self setExpressionNamed:expression];
    }
    
    id mg = action[@"motion_group"];
    id mi = action[@"motion_index"];
    if (mg && mi && [mg isKindOfClass:[NSString class]]) {
        NSInteger idx = [mi isKindOfClass:[NSNumber class]] ? [mi integerValue] : -1;
        if (idx >= 0) {
            std::string base = [((NSString *)mg) UTF8String];
            std::string key = base;
            if (idx > 0) key = base + "_" + std::to_string((int)idx);
            auto it = _motions.find(key);
            if (it == _motions.end()) it = _motions.find(base);
            if (it != _motions.end() && it->second) {
                it->second->setLoop(false);
                if (_motionManager) _motionManager->startMotion(it->second, false);
            }
        }
    }
    
    auto setTarget = ^(id val, float &target, float scale) {
        if ([val isKindOfClass:[NSNumber class]]) target = [val floatValue] * scale;
    };
    setTarget(action[@"head_x"], _targetHeadX, 30.0f);
    setTarget(action[@"head_y"], _targetHeadY, 30.0f);
    setTarget(action[@"body_angle"], _targetBodyAngle, 10.0f);
    if ([action[@"eye_open"] isKindOfClass:[NSNumber class]]) {
        _targetEyeOpen = [action[@"eye_open"] floatValue];
    }
    if ([action[@"mouth_open"] isKindOfClass:[NSNumber class]]) {
        _targetLipSync = [action[@"mouth_open"] floatValue];
    }
    
    // gestures array: [{name, side, intensity, speed}, ...]
    NSArray *gestures = action[@"gestures"];
    if ([gestures isKindOfClass:[NSArray class]] && gestures.count > 0) {
        NSDictionary *g = gestures[0];
        if ([g isKindOfClass:[NSDictionary class]]) {
            NSString *name = g[@"name"] ?: @"";
            NSString *side = g[@"side"] ?: @"right";
            float intensity = [g[@"intensity"] respondsToSelector:@selector(floatValue)] ? [g[@"intensity"] floatValue] : 0.7f;
            float speed = [g[@"speed"] respondsToSelector:@selector(floatValue)] ? [g[@"speed"] floatValue] : 1.0f;
            [self playGestureNamed:name side:side intensity:intensity speed:speed];
        }
    }
    
    [_renderLock unlock];
}

- (void)playGestureNamed:(NSString *)name side:(NSString *)side intensity:(CGFloat)intensity speed:(CGFloat)speed {
    if (!name) name = @"";
    _activeGestureName = [name UTF8String];
    _gestureStartTime = [NSDate timeIntervalSinceReferenceDate];
    _gestureIntensity = (float)fmax(0.1, fmin(1.0, intensity));
    _gestureSide = side ? [side UTF8String] : "right";
    float sp = speed > 0.05f ? (float)speed : 1.0f;
    _gestureDuration = 1.2 / sp;
    // map some gesture names to quick expression hints
    if ([name isEqualToString:@"nod"]) [self setExpressionNamed:@"F_FUN_SMILE"];
    else if ([name isEqualToString:@"shake_head"]) [self setExpressionNamed:@"F_SAD"];
    else if ([name isEqualToString:@"wave"] || [name isEqualToString:@"greeting"]) [self setExpressionNamed:@"F_FUN"];
    else if ([name isEqualToString:@"happy_gesture"] || [name isEqualToString:@"clap"]) [self setExpressionNamed:@"F_FUN_MAX"];
    else if ([name isEqualToString:@"angry"] || [name isEqualToString:@"annoyed"]) [self setExpressionNamed:@"F_ANGRY"];
    else if ([name isEqualToString:@"crying"]) [self setExpressionNamed:@"F_SAD"];
    else if ([name isEqualToString:@"think"]) [self setExpressionNamed:@"F_THINK"];
}


- (void)lookAtNormalizedPoint:(CGPoint)pt {
    float nx = (float)fmax(-1.0, fmin(1.0, pt.x));
    float ny = (float)fmax(-1.0, fmin(1.0, pt.y));
    _targetHeadX = nx * 30.0f;
    _targetHeadY = ny * 30.0f;
    _targetBodyAngle = nx * 8.0f;
    _lastPanTime = [NSDate timeIntervalSinceReferenceDate];
}

- (void)resetLookAt {
    _targetHeadX = 0;
    _targetHeadY = 0;
    _targetBodyAngle = 0;
}

- (void)onRenderLoop {
    [_glkView display];
}

#pragma mark - GLKViewDelegate

- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect {
    glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    
    if (_isSwitchingModel) return;
    if (![_renderLock tryLock]) return;
    
    if (!_live2DModel || !_isModelLoaded) {
        [_renderLock unlock];
        return;
    }
    
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSTimeInterval idleElapsed = now - _idleStartTime;
    
    // Lively motion: restart/switch idle when finished or after interval
    if (_motionManager) {
        if (_motionManager->isFinished() || now >= _nextIdleSwitchTime) {
            [self startIdleAnimation];
        }
    }
    // Occasional soft expression changes for liveliness (no random mood swings)
    if (now >= _nextExpressionTime && !_expressions.empty()) {
        static const char *calm[] = {"F_NOMAL","F_FUN","F_FUN_SMILE","F_FUN_WARM","F_FUN_HANIKAMI","F_THINK","F_SILENT","F_SURPRISE"};
        int calmCount = (int)(sizeof(calm)/sizeof(calm[0]));
        std::string pick = calm[arc4random_uniform(calmCount)];
        if (_expressions.find(pick) == _expressions.end()) {
            // fallback: first available calm-ish or stay
            for (auto &e : _expressions) {
                if (e.first.find("FUN") != std::string::npos || e.first.find("NOMAL") != std::string::npos || e.first.find("SMILE") != std::string::npos) { pick = e.first; break; }
            }
        }
        if (_expressions.find(pick) != _expressions.end()) {
            [self setExpressionNamed:[NSString stringWithUTF8String:pick.c_str()]];
        }
        _nextExpressionTime = now + 25.0 + (arc4random_uniform(2500) / 100.0);
    }
    // Small autonomous head/body nudges when not being dragged
    if (now >= _nextLifeNudgeTime && (now - _lastPanTime) > 0.8) {
        float nx = ((int)arc4random_uniform(200) - 100) / 300.0f;
        float ny = ((int)arc4random_uniform(200) - 100) / 360.0f;
        _targetHeadX += nx * 4.0f;
        _targetHeadY += ny * 3.0f;
        _targetBodyAngle += nx * 1.5f;
        _nextLifeNudgeTime = now + 4.0 + (arc4random_uniform(400) / 100.0);
    }
    
    // Continuous procedural breathing & micro-sway (natural life idle)
    float breath = (sinf(idleElapsed * 2.0f) + 1.0f) * 0.5f; // 0..1 smooth breathing
    float swayAngleZ = sinf(idleElapsed * 0.8f) * 1.5f;     // gentle head tilt
    float bodyAngleX = sinf(idleElapsed * 0.5f) * 0.8f;     // gentle body sway
    
    // Smooth parameter interpolation (LLM/gestures -> model)
    // Lip sync: fast attack, slower release for natural speech (no "chatter" decay)
    float lipK = (_targetLipSync > _currentLipSync) ? 0.45f : 0.18f;
    _currentLipSync += (_targetLipSync - _currentLipSync) * lipK;
    _currentHeadX += (_targetHeadX - _currentHeadX) * 0.12f;
    _currentHeadY += (_targetHeadY - _currentHeadY) * 0.12f;
    _currentBodyAngle += (_targetBodyAngle - _currentBodyAngle) * 0.12f;
    _currentEyeOpen += (_targetEyeOpen - _currentEyeOpen) * 0.15f;
    // decay targets toward neutral so one-shot commands don't stick forever (gentler, but pause during active pan)
    if ((now - _lastPanTime) > 0.25) {
        _targetHeadX *= 0.992f;
        _targetHeadY *= 0.992f;
        _targetBodyAngle *= 0.992f;
    }
    _targetEyeOpen += (1.0f - _targetEyeOpen) * 0.01f;
    
    // Gesture offsets (procedural, applied on top)
    float gAngleX = 0, gAngleY = 0, gAngleZ = 0, gBodyX = 0, gArmR = 0, gArmL = 0;
    if (!_activeGestureName.empty()) {
        double t = now - _gestureStartTime;
        double d = _gestureDuration > 0.1 ? _gestureDuration : 1.0;
        if (t >= d) {
            _activeGestureName.clear();
        } else {
            float p = (float)(t / d);
            float e = sinf((float)M_PI * p); // 0..1..0 envelope
            float amp = _gestureIntensity;
            bool left = (_gestureSide == "left");
            const std::string &gn = _activeGestureName;
            if (gn == "nod") { gAngleY = -12.0f * amp * sinf(p * (float)M_PI * 2.0f); }
            else if (gn == "shake_head") { gAngleX = 15.0f * amp * sinf(p * (float)M_PI * 3.0f); }
            else if (gn == "wave" || gn == "greeting") { float side = left ? -1.f : 1.f; gArmR = left ? 0 : -8.f*amp*sinf(p*(float)M_PI*3.f); gArmL = left ? -8.f*amp*sinf(p*(float)M_PI*3.f) : 0; gAngleZ = side*4.f*amp*e; }
            else if (gn == "turn_left") { gAngleX = -20.0f * amp * e; gBodyX = -6.0f * amp * e; }
            else if (gn == "turn_right") { gAngleX = 20.0f * amp * e; gBodyX = 6.0f * amp * e; }
            else if (gn == "bow_casual" || gn == "thankful") { gAngleY = -18.0f * amp * e; gBodyX = -4.0f * amp * e; }
            else if (gn == "think") { gAngleX = 8.0f * amp * e; gAngleY = -6.0f * amp * e; }
            else if (gn == "clap" || gn == "happy_gesture") { gArmR = -6.f*amp*sinf(p*(float)M_PI*6.f); gArmL = -6.f*amp*sinf(p*(float)M_PI*6.f); }
            else if (gn == "angry") { gAngleY = -10.0f * amp * e; gAngleZ = 5.0f * amp * e; }
            else if (gn == "spin") { gAngleX = 30.0f * amp * sinf(p * (float)M_PI * 2.0f); gBodyX = 8.0f * amp * sinf(p * (float)M_PI * 2.0f); }
            else if (gn == "dance" || gn.find("dance_") == 0) { gBodyX = 6.0f*amp*sinf(p*(float)M_PI*4.f); gAngleZ = 8.0f*amp*sinf(p*(float)M_PI*4.f); gArmR = -5.f*amp*fabsf(sinf(p*(float)M_PI*4.f)); gArmL = -5.f*amp*fabsf(sinf(p*(float)M_PI*4.f + 1.57f)); }
            else { gAngleZ = 3.0f * amp * e; }
        }
    }
    
    // Update motion manager (file motions)
    if (_motionManager) {
        _motionManager->updateParam(_live2DModel);
    }
    
    // Update eye blink
    if (_eyeBlink) {
        _eyeBlink->setParam(_live2DModel);
    }
    
    // Update expression
    if (_expressionManager) {
        _expressionManager->updateParam(_live2DModel);
    }
    
    // Apply continuous idle + directed parameters
    _live2DModel->addToParamFloat("PARAM_BREATH", breath, 0.5f);
    _live2DModel->addToParamFloat("PARAM_ANGLE_Z", swayAngleZ + _currentHeadX * 0.0f + gAngleZ, 0.6f);
    _live2DModel->addToParamFloat("PARAM_ANGLE_X", _currentHeadX + gAngleX, 0.8f);
    _live2DModel->addToParamFloat("PARAM_ANGLE_Y", _currentHeadY + gAngleY, 0.8f);
    _live2DModel->addToParamFloat("PARAM_BODY_ANGLE_X", bodyAngleX + _currentBodyAngle + gBodyX, 0.6f);
    _live2DModel->addToParamFloat("PARAM_ARM_R", gArmR, 0.5f);
    _live2DModel->addToParamFloat("PARAM_ARM_L", gArmL, 0.5f);
    // eye follow from current head targets
    _live2DModel->setParamFloat("PARAM_EYE_BALL_X", fmaxf(-1.0f,fminf(1.0f,_currentHeadX/30.0f)));    _live2DModel->setParamFloat("PARAM_EYE_BALL_Y", fmaxf(-1.0f,fminf(1.0f,_currentHeadY/30.0f)));
    if (_currentEyeOpen > 0.01f && _currentEyeOpen < 0.99f) {
        _live2DModel->setParamFloat("PARAM_EYE_L_OPEN", _currentEyeOpen);
        _live2DModel->setParamFloat("PARAM_EYE_R_OPEN", _currentEyeOpen);
    }
    
    // Apply lip sync
    _live2DModel->setParamFloat("PARAM_MOUTH_OPEN_Y", fmaxf(0.0f, fminf(1.0f, _currentLipSync)));
    
    // Update physics (hair sway, ribbons)
    if (_physics) {
        _physics->updateParam(_live2DModel);
    }
    
    // Setup OpenGL viewport & projection
    CGFloat viewW = self.bounds.size.width;
    CGFloat viewH = self.bounds.size.height;
    if (viewW <= 0 || viewH <= 0) {
        [_renderLock unlock];
        return;
    }
    
    CGFloat canvasW = _live2DModel->getCanvasWidth();
    CGFloat canvasH = _live2DModel->getCanvasHeight();
    
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    
    CGFloat scaleX = viewW / canvasW;
    CGFloat scaleY = viewH / canvasH;
    CGFloat scale = MIN(scaleX, scaleY) * 1.05f;
    
    CGFloat scaledW = canvasW * scale;
    CGFloat scaledH = canvasH * scale;
    CGFloat offsetX = (viewW - scaledW) / 2.0f;
    CGFloat offsetY = (viewH - scaledH) / 2.0f - (viewH * 0.05f);
    
    glOrthof(0, viewW, viewH, 0, -1.0f, 1.0f);
    
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    glTranslatef(offsetX, offsetY, 0);
    glScalef(scale, scale, 1.0f);
    
    // Standard Straight Alpha Blending for clean seam-free rendering
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    
    _live2DModel->update();
    _live2DModel->draw();
    
    [_renderLock unlock];
}

@end
