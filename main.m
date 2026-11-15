#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Speech/Speech.h>
#import <QuartzCore/QuartzCore.h>
#import "AsunaLive2DView.h"

// --- Asuna Liquid Glass 26 Color Palette & Glassmorphism ---
#define ASUNA_DARK_BG       [UIColor colorWithRed:0.06 green:0.05 blue:0.07 alpha:1.0] /* #0F0E12 */
#define ASUNA_GLASS_DOCK    [UIColor colorWithRed:0.18 green:0.18 blue:0.22 alpha:0.45] /* Ultra-frosted Glass Dock */
#define ASUNA_GLASS_CARD    [UIColor colorWithRed:0.12 green:0.13 blue:0.17 alpha:0.85] /* High-contrast card */
#define ASUNA_PEACH_ACCENT  [UIColor colorWithRed:1.00 green:0.62 blue:0.48 alpha:1.0] /* Warm Peach #FF9E79 */
#define ASUNA_CYAN_ACCENT   [UIColor colorWithRed:0.28 green:0.90 blue:1.00 alpha:1.0] /* Cyber Cyan #48E5FF */
#define ASUNA_LAVENDER      [UIColor colorWithRed:0.70 green:0.51 blue:0.96 alpha:1.0] /* Lavender Tint #B282F5 */
#define ASUNA_TEXT_WHITE    [UIColor colorWithRed:0.95 green:0.96 blue:0.98 alpha:1.0] /* High-contrast text */
#define ASUNA_TEXT_MUTED    [UIColor colorWithRed:0.65 green:0.68 blue:0.74 alpha:1.0] /* Frosted subtitle */
#define ASUNA_USER_BUBBLE   [UIColor colorWithRed:0.18 green:0.20 blue:0.28 alpha:0.85]
#define ASUNA_BOT_BUBBLE    [UIColor colorWithRed:0.10 green:0.11 blue:0.14 alpha:0.80]

static UIFont *AsunaFont(CGFloat size, BOOL bold) {
    if (bold) return [UIFont boldSystemFontOfSize:size];
    return [UIFont systemFontOfSize:size];
}

static UIFont *AsunaMonoFont(CGFloat size) {
    UIFont *f = [UIFont fontWithName:@"Menlo" size:size];
    if (!f) f = [UIFont fontWithName:@"Courier" size:size];
    return f ?: [UIFont systemFontOfSize:size];
}

// Physical Liquid Glass Styling (Curved surface, Specular Fresnel Rim, Soft Ambient Shadow)
static void ApplyLiquidGlass(UIView *view, CGFloat cornerRadius, BOOL specularRim) {
    view.layer.cornerRadius = cornerRadius;
    view.layer.masksToBounds = NO;
    view.layer.shadowColor = [UIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:0.6].CGColor;
    view.layer.shadowOpacity = 0.55;
    view.layer.shadowRadius = 12.0;
    view.layer.shadowOffset = CGSizeMake(0, 6);
    
    if (specularRim) {
        view.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.32].CGColor;
        view.layer.borderWidth = 1.2;
    }
}

static NSString *StripEmoji(NSString *input) {
    if (!input) return @"";
    NSMutableString *out = [NSMutableString stringWithCapacity:input.length];
    [input enumerateSubstringsInRange:NSMakeRange(0, input.length)
                              options:NSStringEnumerationByComposedCharacterSequences
                           usingBlock:^(NSString *substr, NSRange substrRange, NSRange enclosingRange, BOOL *stop) {
        if (!substr) return;
        unichar c = [substr characterAtIndex:0];
        BOOL emoji = NO;
        if (substr.length > 1) {
            // surrogate pairs / sequences often used for emoji
            unichar c1 = c;
            unichar c2 = [substr characterAtIndex:1];
            if (c1 >= 0xD800 && c1 <= 0xDBFF && c2 >= 0xDC00 && c2 <= 0xDFFF) emoji = YES;
        }
        if (c >= 0x2600 && c <= 0x27BF) emoji = YES; // misc symbols, dingbats
        if (c >= 0xFE00 && c <= 0xFE0F) emoji = YES; // variation selectors
        if (c == 0x200D) emoji = YES; // ZWJ
        if (c >= 0x2300 && c <= 0x23FF) emoji = YES;
        if (c >= 0x2B00 && c <= 0x2BFF) emoji = YES;
        if ([substr rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"☺☹❤⭐✨⚡☀☁☔❄"]].location != NSNotFound) emoji = YES;
        // common emoji blocks by high surrogate ranges covered above; also filter pictographs via unicode scalars
        for (NSUInteger i = 0; i < substr.length && !emoji; i++) {
            unichar ch = [substr characterAtIndex:i];
            if (ch == 0x20E3) emoji = YES; // keycap
        }
        if (!emoji) [out appendString:substr];
    }];
    // collapse extra spaces
    NSRegularExpression *ws = [NSRegularExpression regularExpressionWithPattern:@"[ \t]{2,}" options:0 error:nil];
    NSString *res = [ws stringByReplacingMatchesInString:out options:0 range:NSMakeRange(0, out.length) withTemplate:@" "];
    return res;
}

// Clean speech/display text
static NSString *CleanSpeechText(NSString *input) {
    if (!input || input.length == 0) return @"";
    NSString *clean = input;
    NSRegularExpression *rxCode = [NSRegularExpression regularExpressionWithPattern:@"```[\\s\\S]*?```" options:0 error:nil];
    clean = [rxCode stringByReplacingMatchesInString:clean options:0 range:NSMakeRange(0, clean.length) withTemplate:@""];
    NSRegularExpression *rxInline = [NSRegularExpression regularExpressionWithPattern:@"`[^`]+`" options:0 error:nil];
    clean = [rxInline stringByReplacingMatchesInString:clean options:0 range:NSMakeRange(0, clean.length) withTemplate:@""];
    clean = [clean stringByReplacingOccurrencesOfString:@"*" withString:@""];
    clean = [clean stringByReplacingOccurrencesOfString:@"#" withString:@""];
    clean = StripEmoji(clean);
    return [clean stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

// --- Configuration & Defaults ---
#define DEFAULT_PROXY_HOST @"http://127.0.0.1:8088"
#define DEFAULT_GEMINI_KEY @""
#define DEFAULT_OPENROUTER_KEY @""

#define PREF_PROXY_URL @"Asuna_ProxyURL"
#define PREF_GEMINI_KEY @"Asuna_GeminiKey"
#define PREF_OPENROUTER_KEY @"Asuna_OpenRouterKey"
#define PREF_CURRENT_PROVIDER @"Asuna_CurrentProvider"
#define PREF_GEMINI_MODEL @"Asuna_GeminiModel"
#define PREF_OPENROUTER_MODEL @"Asuna_OpenRouterModel"
#define PREF_CURRENT_AVATAR @"Asuna_CurrentAvatar"
#define PREF_WEB_SEARCH @"Asuna_WebSearchEnabled"
#define PREF_CHATS @"Asuna_ChatsHistory"
#define PREF_TTS_LOCAL @"Asuna_TTSLocalEnabled"
#define PREF_TTS_MODE @"Asuna_TTSMode"
#define PREF_CUSTOM_BG_PATH @"Asuna_CustomBgPath"
#define PREF_DISPLAY_PRESET @"Asuna_DisplayPreset"
#define PREF_FREE_SCALE @"Asuna_FreeScale"
#define PREF_FREE_OX @"Asuna_FreeOffsetX"
#define PREF_FREE_OY @"Asuna_FreeOffsetY"

@interface SettingsManager : NSObject
+ (instancetype)shared;
@property (nonatomic, strong) NSString *proxyUrl;
@property (nonatomic, strong) NSString *geminiKey;
@property (nonatomic, strong) NSString *openRouterKey;
@property (nonatomic, strong) NSString *currentProvider;
@property (nonatomic, strong) NSString *geminiModel;
@property (nonatomic, strong) NSString *openRouterModel;
@property (nonatomic, strong) NSString *currentAvatar;
@property (nonatomic, assign) BOOL webSearchEnabled;
@property (nonatomic, assign) BOOL localTTSEnabled;
@property (nonatomic, assign) NSInteger ttsMode; // 0 off, 1 iOS, 2 Piper local
@property (nonatomic, strong) NSString *customBgPath;
@property (nonatomic, assign) NSInteger displayPreset;
@property (nonatomic, assign) CGFloat freeScale;
@property (nonatomic, assign) CGFloat freeOffsetX;
@property (nonatomic, assign) CGFloat freeOffsetY;
- (NSString *)activeModel;
- (void)save;
@end

@implementation SettingsManager
+ (instancetype)shared {
    static SettingsManager *inst;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ inst = [[SettingsManager alloc] init]; });
    return inst;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
        _proxyUrl = [defs stringForKey:PREF_PROXY_URL] ?: DEFAULT_PROXY_HOST;
        _geminiKey = [defs stringForKey:PREF_GEMINI_KEY] ?: DEFAULT_GEMINI_KEY;
        _openRouterKey = [defs stringForKey:PREF_OPENROUTER_KEY] ?: DEFAULT_OPENROUTER_KEY;
        _currentProvider = [defs stringForKey:PREF_CURRENT_PROVIDER] ?: @"gemini";
        
        _geminiModel = [defs stringForKey:PREF_GEMINI_MODEL];
        if (!_geminiModel || [_geminiModel containsString:@"flash-latest"] || [_geminiModel containsString:@"2.0-flash"]) {
            _geminiModel = @"gemini-3.5-flash-lite";
        }
        
        _openRouterModel = [defs stringForKey:PREF_OPENROUTER_MODEL];
        if (!_openRouterModel || [_openRouterModel containsString:@"exp:free"] || [_openRouterModel isEqualToString:@"openrouter/auto"]) {
            _openRouterModel = @"nvidia/nemotron-3.5-lightning:free";
        }
        
        _currentAvatar = [defs stringForKey:PREF_CURRENT_AVATAR] ?: @"asuna_01";
        _webSearchEnabled = [defs boolForKey:PREF_WEB_SEARCH];
        _localTTSEnabled = [defs objectForKey:PREF_TTS_LOCAL] != nil ? [defs boolForKey:PREF_TTS_LOCAL] : YES;
        NSNumber *tm = [defs objectForKey:PREF_TTS_MODE];
        NSInteger m = tm ? [tm integerValue] : (_localTTSEnabled ? 1 : 0);
        if (m == 3) m = 2; // old Piper index
        if (m < 0 || m > 2) m = (_localTTSEnabled ? 1 : 0);
        _ttsMode = m;
        _customBgPath = [defs stringForKey:PREF_CUSTOM_BG_PATH];
        _displayPreset = [[defs objectForKey:PREF_DISPLAY_PRESET] integerValue];
        NSNumber *fs = [defs objectForKey:PREF_FREE_SCALE];
        _freeScale = fs ? [fs doubleValue] : 1.0;
        _freeOffsetX = [[defs objectForKey:PREF_FREE_OX] doubleValue];
        _freeOffsetY = [[defs objectForKey:PREF_FREE_OY] doubleValue];
    }
    return self;
}

- (NSString *)activeModel {
    if ([_currentProvider isEqualToString:@"openrouter"]) {
        return _openRouterModel ?: @"nvidia/nemotron-3.5-lightning:free";
    }
    return _geminiModel ?: @"gemini-3.5-flash-lite";
}

- (void)save {
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    [defs setObject:_proxyUrl forKey:PREF_PROXY_URL];
    [defs setObject:_geminiKey forKey:PREF_GEMINI_KEY];
    [defs setObject:_openRouterKey forKey:PREF_OPENROUTER_KEY];
    [defs setObject:_currentProvider forKey:PREF_CURRENT_PROVIDER];
    [defs setObject:_geminiModel forKey:PREF_GEMINI_MODEL];
    [defs setObject:_openRouterModel forKey:PREF_OPENROUTER_MODEL];
    [defs setObject:_currentAvatar forKey:PREF_CURRENT_AVATAR];
    [defs setBool:_webSearchEnabled forKey:PREF_WEB_SEARCH];
    _localTTSEnabled = (_ttsMode != 0);
    [defs setBool:_localTTSEnabled forKey:PREF_TTS_LOCAL];
    [defs setInteger:_ttsMode forKey:PREF_TTS_MODE];
    [defs setObject:_customBgPath ?: @"" forKey:PREF_CUSTOM_BG_PATH];
    [defs setInteger:_displayPreset forKey:PREF_DISPLAY_PRESET];
    [defs setDouble:_freeScale forKey:PREF_FREE_SCALE];
    [defs setDouble:_freeOffsetX forKey:PREF_FREE_OX];
    [defs setDouble:_freeOffsetY forKey:PREF_FREE_OY];
    [defs synchronize];
}
@end

// --- Local Chat Storage ---
@interface ChatStore : NSObject
+ (instancetype)shared;
- (NSArray<NSDictionary *> *)allChats;
- (NSString *)createChatWithTitle:(NSString *)title;
- (NSDictionary *)getChatById:(NSString *)chatId;
- (void)saveMessages:(NSArray *)messages forChatId:(NSString *)chatId;
@end

@implementation ChatStore {
    NSMutableArray *_chats;
}

+ (instancetype)shared {
    static ChatStore *store;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ store = [[ChatStore alloc] init]; });
    return store;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:PREF_CHATS];
        if (saved) {
            _chats = [saved mutableCopy];
        } else {
            _chats = [NSMutableArray array];
            NSString *cid = [[NSUUID UUID] UUIDString];
            [_chats addObject:@{
                @"id": cid,
                @"title": @"Асуна",
                @"created_at": @((long)[[NSDate date] timeIntervalSince1970]),
                @"messages": @[
                    @{
                        @"role": @"assistant",
                        @"text": @"Привет! Я Асуна в дизайне Liquid Glass. Нажми на светящуюся стеклянную сферу микрофона внизу, чтобы поговорить со мной!",
                        @"time": @"Только что"
                    }
                ]
            }];
            [self persist];
        }
    }
    return self;
}

- (void)persist {
    [[NSUserDefaults standardUserDefaults] setObject:_chats forKey:PREF_CHATS];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSArray<NSDictionary *> *)allChats {
    return [_chats copy];
}

- (NSString *)createChatWithTitle:(NSString *)title {
    NSString *cid = [[NSUUID UUID] UUIDString];
    NSDictionary *newChat = @{
        @"id": cid,
        @"title": title.length > 0 ? title : @"Диалог",
        @"created_at": @((long)[[NSDate date] timeIntervalSince1970]),
        @"messages": @[]
    };
    [_chats insertObject:newChat atIndex:0];
    [self persist];
    return cid;
}

- (NSDictionary *)getChatById:(NSString *)chatId {
    for (NSDictionary *c in _chats) {
        if ([c[@"id"] isEqualToString:chatId]) return c;
    }
    return nil;
}

- (void)saveMessages:(NSArray *)messages forChatId:(NSString *)chatId {
    for (NSInteger i = 0; i < _chats.count; i++) {
        if ([_chats[i][@"id"] isEqualToString:chatId]) {
            NSMutableDictionary *mut = [_chats[i] mutableCopy];
            mut[@"messages"] = messages;
            _chats[i] = mut;
            [self persist];
            break;
        }
    }
}
@end

// --- Compact Modal Settings Sheet ---
@interface ModelsSettingsViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, copy) void (^onDismissed)(void);
@property (nonatomic, copy) void (^onBackgroundChanged)(void);
@property (nonatomic, copy) void (^onDisplayChanged)(void);
@property (nonatomic, copy) void (^onEnterAdjustMode)(void);
@end

@implementation ModelsSettingsViewController {
    UITableView *_tableView;
    UIActivityIndicatorView *_spinner;
    NSArray *_geminiModels;
    NSArray *_openRouterModels;
    NSDictionary *_openRouterKeyLimits;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Настройки";
    self.preferredContentSize = CGSizeMake(520, 600);
    self.view.backgroundColor = ASUNA_DARK_BG;
    
    // Explicit Close button to dismiss modal sheet
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Закрыть"
                                                                             style:UIBarButtonItemStyleDone
                                                                            target:self
                                                                            action:@selector(onClose)];
    
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Обновить"
                                                                              style:UIBarButtonItemStylePlain
                                                                             target:self
                                                                             action:@selector(fetchModelsAndLimits)];
    
    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _tableView.backgroundColor = ASUNA_DARK_BG;
    _tableView.separatorColor = [UIColor colorWithWhite:1.0 alpha:0.12];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    [self.view addSubview:_tableView];
    
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    _spinner.center = self.view.center;
    _spinner.hidesWhenStopped = YES;
    [self.view addSubview:_spinner];
    
    [self fetchModelsAndLimits];
}

- (void)onClose {
    [self dismissViewControllerAnimated:YES completion:^{
        if (self.onDismissed) self.onDismissed();
    }];
}

- (void)fetchModelsAndLimits {
    [_spinner startAnimating];
    NSString *urlStr = [NSString stringWithFormat:@"%@/models", [SettingsManager shared].proxyUrl];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr]];
    req.timeoutInterval = 15;
    [req setValue:[SettingsManager shared].geminiKey forHTTPHeaderField:@"X-Gemini-Key"];
    [req setValue:[SettingsManager shared].openRouterKey forHTTPHeaderField:@"X-OpenRouter-Key"];
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_spinner stopAnimating];
            if (data) {
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                if (json) {
                    self->_geminiModels = json[@"gemini"][@"models"] ?: @[];
                    self->_openRouterModels = json[@"openrouter"][@"models"] ?: @[];
                    self->_openRouterKeyLimits = json[@"openrouter"][@"key_info"] ?: @{};
                    [self->_tableView reloadData];
                }
            } else if (error) {
                UIAlertController *al = [UIAlertController alertControllerWithTitle:@"Ошибка связи" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
                [al addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:al animated:YES completion:nil];
            }
        });
    }] resume];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 7; }

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"ОФОРМЛЕНИЕ И ФОН";
        case 1: return @"ОТОБРАЖЕНИЕ ПЕРСОНАЖА";
        case 2: return @"СИНТЕЗ РЕЧИ (TTS)";
        case 3: return @"ПРОКСИ СЕРВЕР";
        case 4: return @"ПРОВАЙДЕР И КЛЮЧИ";
        case 5: return @"ЛИМИТЫ КЛЮЧЕЙ НА СЕРВЕРЕ";
        case 6: return @"МОДЕЛИ НЕЙРОСЕТЕЙ (ТАП ДЛЯ ВЫБОРА)";
        default: return nil;
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 2; // фон
        case 1: return ([SettingsManager shared].displayPreset == 3) ? 5 : 4; // пресеты + настройка
        case 2: return 2; // tts mode + asuna url
        case 3: return 1; // прокси
        case 4: return 3; // провайдер и ключи
        case 5: return 2; // лимиты
        case 6: {
            NSString *prov = [SettingsManager shared].currentProvider;
            if ([prov isEqualToString:@"gemini"]) {
                return _geminiModels.count > 0 ? _geminiModels.count : 4;
            } else {
                return _openRouterModels.count > 0 ? MIN(_openRouterModels.count, 60) : 4;
            }
        }
        default: return 0;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SettingsManager *sm = [SettingsManager shared];
    
    // Section 0: Custom Wallpaper & Background
    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
            cell.backgroundColor = ASUNA_GLASS_CARD;
            cell.textLabel.text = @"Выбрать обои из Фотографий";
            cell.textLabel.font = AsunaFont(15, YES);
            cell.textLabel.textColor = ASUNA_TEXT_WHITE;
            if (sm.customBgPath && [[NSFileManager defaultManager] fileExistsAtPath:sm.customBgPath]) {
                cell.detailTextLabel.text = @"Установлено пользовательское фото (нажмите для смены)";
                cell.detailTextLabel.textColor = ASUNA_PEACH_ACCENT;
            } else {
                cell.detailTextLabel.text = @"Выбрать свою картинку для заднего фона";
                cell.detailTextLabel.textColor = ASUNA_TEXT_MUTED;
            }
            cell.detailTextLabel.font = AsunaFont(13, NO);
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        } else {
            UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
            cell.backgroundColor = ASUNA_GLASS_CARD;
            cell.textLabel.text = @"Сбросить на Liquid Glass градиент";
            cell.textLabel.font = AsunaFont(15, YES);
            cell.textLabel.textColor = [UIColor colorWithRed:1.0 green:0.4 blue:0.4 alpha:1.0];
            cell.detailTextLabel.text = @"Вернуть динамический темный градиент";
            cell.detailTextLabel.font = AsunaFont(13, NO);
            cell.detailTextLabel.textColor = ASUNA_TEXT_MUTED;
            return cell;
        }
    }
    
    if (indexPath.section == 1) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
        cell.backgroundColor = ASUNA_GLASS_CARD;
        if (indexPath.row <= 3) {
            NSArray *titles = @[@"Полный рост", @"От юбки до головы", @"Крупный план", @"Свободный"];
            NSArray *subs = @[@"Весь персонаж целиком", @"Голова, верх и юбка (без ног)", @"Лицо и плечи крупнее", @"Ручная настройка положения и масштаба"];
            NSInteger row = indexPath.row;
            cell.textLabel.text = titles[row];
            cell.detailTextLabel.text = subs[row];
            cell.textLabel.font = AsunaFont(15, YES);
            cell.detailTextLabel.font = AsunaFont(13, NO);
            cell.textLabel.textColor = ASUNA_TEXT_WHITE;
            cell.detailTextLabel.textColor = ASUNA_TEXT_MUTED;
            cell.accessoryType = (sm.displayPreset == row) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
            if (sm.displayPreset == row) cell.textLabel.textColor = ASUNA_PEACH_ACCENT;
        } else {
            cell.textLabel.text = @"Настроить положение";
            cell.detailTextLabel.text = @"Перемещайте и масштабируйте, затем зафиксируйте";
            cell.textLabel.font = AsunaFont(15, YES);
            cell.detailTextLabel.font = AsunaFont(13, NO);
            cell.textLabel.textColor = ASUNA_CYAN_ACCENT;
            cell.detailTextLabel.textColor = ASUNA_TEXT_MUTED;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
        return cell;
    }
    
    if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
            cell.backgroundColor = ASUNA_GLASS_CARD;
            UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[@"Выкл", @"iOS TTS", @"Piper (локально)"]];
            seg.selectedSegmentIndex = MAX(0, MIN(2, (NSInteger)sm.ttsMode));
            seg.frame = CGRectMake(15, 6, tableView.bounds.size.width - 30, 32);
            seg.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            seg.tintColor = ASUNA_PEACH_ACCENT;
            [seg setTitleTextAttributes:@{NSFontAttributeName: AsunaFont(13, YES)} forState:UIControlStateNormal];
            [seg addTarget:self action:@selector(onTTSModeChanged:) forControlEvents:UIControlEventValueChanged];
            [cell.contentView addSubview:seg];
            return cell;
        } else {
            UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
            cell.backgroundColor = ASUNA_GLASS_CARD;
            cell.textLabel.text = @"Piper (локально, офлайн)";
            cell.textLabel.font = AsunaFont(15, YES);
            cell.textLabel.textColor = (sm.ttsMode == 2) ? ASUNA_TEXT_WHITE : ASUNA_TEXT_MUTED;
            cell.detailTextLabel.text = @"Голос: ru_RU-irina (мягкий женский)";
            cell.detailTextLabel.font = AsunaFont(13, NO);
            cell.detailTextLabel.textColor = ASUNA_TEXT_MUTED;
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            return cell;
        }
    }
    
    if (indexPath.section == 3) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
        cell.backgroundColor = ASUNA_GLASS_CARD;
        cell.textLabel.text = @"URL Прокси";
        cell.textLabel.font = AsunaFont(15, YES);
        cell.textLabel.textColor = ASUNA_TEXT_WHITE;
        cell.detailTextLabel.text = sm.proxyUrl;
        cell.detailTextLabel.font = AsunaFont(14, NO);
        cell.detailTextLabel.textColor = ASUNA_TEXT_MUTED;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    
    if (indexPath.section == 4) {
        if (indexPath.row == 0) {
            UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
            cell.backgroundColor = ASUNA_GLASS_CARD;
            UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[@"Google Gemini", @"OpenRouter"]];
            seg.selectedSegmentIndex = [sm.currentProvider isEqualToString:@"openrouter"] ? 1 : 0;
            seg.frame = CGRectMake(15, 6, tableView.bounds.size.width - 30, 32);
            seg.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            seg.tintColor = ASUNA_PEACH_ACCENT;
            [seg setTitleTextAttributes:@{NSFontAttributeName: AsunaFont(14, YES)} forState:UIControlStateNormal];
            [seg addTarget:self action:@selector(onProviderChanged:) forControlEvents:UIControlEventValueChanged];
            [cell.contentView addSubview:seg];
            return cell;
        } else if (indexPath.row == 1) {
            UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
            cell.backgroundColor = ASUNA_GLASS_CARD;
            cell.textLabel.text = @"Gemini API Key";
            cell.textLabel.font = AsunaFont(15, YES);
            cell.textLabel.textColor = ASUNA_TEXT_WHITE;
            cell.detailTextLabel.text = [sm.geminiKey substringToIndex:MIN(sm.geminiKey.length, 18)];
            cell.detailTextLabel.font = AsunaFont(13, NO);
            cell.detailTextLabel.textColor = ASUNA_TEXT_MUTED;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        } else {
            UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
            cell.backgroundColor = ASUNA_GLASS_CARD;
            cell.textLabel.text = @"OpenRouter API Key";
            cell.textLabel.font = AsunaFont(15, YES);
            cell.textLabel.textColor = ASUNA_TEXT_WHITE;
            cell.detailTextLabel.text = [sm.openRouterKey substringToIndex:MIN(sm.openRouterKey.length, 18)];
            cell.detailTextLabel.font = AsunaFont(13, NO);
            cell.detailTextLabel.textColor = ASUNA_TEXT_MUTED;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        }
    }
    
    if (indexPath.section == 5) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
        cell.backgroundColor = ASUNA_GLASS_CARD;
        cell.textLabel.font = AsunaFont(14, YES);
        cell.textLabel.textColor = ASUNA_TEXT_WHITE;
        cell.detailTextLabel.font = AsunaFont(14, NO);
        cell.detailTextLabel.textColor = ASUNA_CYAN_ACCENT;
        
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Дневной лимит OpenRouter";
            NSDictionary *daily = _openRouterKeyLimits[@"free_model_daily_requests"];
            if (daily) {
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ / %@ (Осталось: %@)", daily[@"used"], daily[@"limit"], daily[@"remaining"]];
            } else {
                cell.detailTextLabel.text = @"50 запросов в день";
            }
        } else {
            cell.textLabel.text = @"Gemini Free Tier Квоты";
            cell.detailTextLabel.text = @"15 RPM • 1M TPM • 1500 RPD";
        }
        return cell;
    }
    
    // Section 6: Models
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.backgroundColor = ASUNA_GLASS_CARD;
    
    NSString *prov = sm.currentProvider;
    NSString *modelId = @"";
    NSString *modelName = @"";
    NSString *desc = @"";
    
    if ([prov isEqualToString:@"gemini"]) {
        if (_geminiModels.count > indexPath.row) {
            NSDictionary *m = _geminiModels[indexPath.row];
            modelId = m[@"id"] ?: @"";
            modelName = m[@"name"] ?: modelId;
            desc = [NSString stringWithFormat:@"Контекст: %@ токенов", m[@"context_length"] ?: @"1M"];
        } else {
            NSArray *defaults = @[@"gemini-3.5-flash-lite", @"gemini-flash-lite-latest", @"gemini-3.5-flash", @"gemini-3.6-flash"];
            if (indexPath.row < defaults.count) {
                modelId = defaults[indexPath.row];
                modelName = modelId;
                desc = @"Быстрая надежная модель Gemini";
            }
        }
    } else {
        if (_openRouterModels.count > indexPath.row) {
            NSDictionary *m = _openRouterModels[indexPath.row];
            modelId = m[@"id"] ?: @"";
            modelName = m[@"name"] ?: modelId;
            desc = @"Бесплатная модель OpenRouter (:free)";
        } else {
            NSArray *defaults = @[@"nvidia/nemotron-3.5-lightning:free", @"google/gemma-4-26b-a4b-it:free", @"recursive/flint-v1.0:free", @"liquid/lfm-2.5-2.6b:free"];
            if (indexPath.row < defaults.count) {
                modelId = defaults[indexPath.row];
                modelName = modelId;
                desc = @"Бесплатная модель OpenRouter (:free)";
            }
        }
    }
    
    cell.textLabel.text = modelName;
    cell.textLabel.font = AsunaFont(15, YES);
    cell.textLabel.textColor = ASUNA_TEXT_WHITE;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@  [%@]", modelId, desc];
    cell.detailTextLabel.font = AsunaFont(12, NO);
    cell.detailTextLabel.textColor = ASUNA_TEXT_MUTED;
    
    BOOL isSelected = [prov isEqualToString:@"gemini"] ? [sm.geminiModel isEqualToString:modelId] : [sm.openRouterModel isEqualToString:modelId];
    if (isSelected) {
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
        cell.textLabel.textColor = ASUNA_PEACH_ACCENT;
    } else {
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    SettingsManager *sm = [SettingsManager shared];
    
    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            // Open Photo Library to pick custom background wallpaper
            if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
                UIImagePickerController *picker = [[UIImagePickerController alloc] init];
                picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
                picker.delegate = self;
                picker.modalPresentationStyle = UIModalPresentationPageSheet;
                [self presentViewController:picker animated:YES completion:nil];
            }
        } else {
            // Reset to default Liquid Glass gradient
            sm.customBgPath = nil;
            [sm save];
            if (self.onBackgroundChanged) self.onBackgroundChanged();
            [self->_tableView reloadData];
        }
    } else if (indexPath.section == 1) {
        if (indexPath.row <= 3) {
            sm.displayPreset = indexPath.row;
            [sm save];
            [tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationFade];
            if (self.onDisplayChanged) self.onDisplayChanged();
        } else {
            [self dismissViewControllerAnimated:YES completion:^{
                if (self.onEnterAdjustMode) self.onEnterAdjustMode();
            }];
        }
    } else if (indexPath.section == 3) {
        [self promptForTextTitle:@"URL Прокси" current:sm.proxyUrl onSave:^(NSString *val) {
            sm.proxyUrl = val;
            [sm save];
            [self fetchModelsAndLimits];
        }];
    } else if (indexPath.section == 4) {
        if (indexPath.row == 1) {
            [self promptForTextTitle:@"Gemini API Key" current:sm.geminiKey onSave:^(NSString *val) {
                sm.geminiKey = val;
                [sm save];
                [self->_tableView reloadData];
            }];
        } else if (indexPath.row == 2) {
            [self promptForTextTitle:@"OpenRouter API Key" current:sm.openRouterKey onSave:^(NSString *val) {
                sm.openRouterKey = val;
                [sm save];
                [self->_tableView reloadData];
            }];
        }
    } else if (indexPath.section == 6) {
        NSString *chosen = nil;
        if ([sm.currentProvider isEqualToString:@"gemini"]) {
            if (_geminiModels.count > indexPath.row) {
                chosen = _geminiModels[indexPath.row][@"id"];
            } else {
                NSArray *defaults = @[@"gemini-3.5-flash-lite", @"gemini-flash-lite-latest", @"gemini-3.5-flash", @"gemini-3.6-flash"];
                if (indexPath.row < defaults.count) chosen = defaults[indexPath.row];
            }
            if (chosen) sm.geminiModel = chosen;
        } else {
            if (_openRouterModels.count > indexPath.row) {
                chosen = _openRouterModels[indexPath.row][@"id"];
            } else {
                NSArray *defaults = @[@"nvidia/nemotron-3.5-lightning:free", @"google/gemma-4-26b-a4b-it:free", @"recursive/flint-v1.0:free", @"liquid/lfm-2.5-2.6b:free"];
                if (indexPath.row < defaults.count) chosen = defaults[indexPath.row];
            }
            if (chosen) sm.openRouterModel = chosen;
        }
        [sm save];
        [tableView reloadSections:[NSIndexSet indexSetWithIndex:6] withRowAnimation:UITableViewRowAnimationNone];
    }
}

#pragma mark - UIImagePickerControllerDelegate

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<NSString *,id> *)info {
    UIImage *img = info[UIImagePickerControllerOriginalImage];
    if (img) {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *docsDir = paths.firstObject;
        NSString *bgPath = [docsDir stringByAppendingPathComponent:@"custom_bg.png"];
        NSData *png = UIImagePNGRepresentation(img);
        if (!png) png = UIImageJPEGRepresentation(img, 0.9);
        [png writeToFile:bgPath atomically:YES];
        
        [SettingsManager shared].customBgPath = bgPath;
        [[SettingsManager shared] save];
        
        if (self.onBackgroundChanged) self.onBackgroundChanged();
    }
    [picker dismissViewControllerAnimated:YES completion:^{
        [self->_tableView reloadData];
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)promptForTextTitle:(NSString *)title current:(NSString *)current onSave:(void(^)(NSString *))onSave {
    UIAlertController *al = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert];
    [al addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = current; }];
    [al addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
    [al addAction:[UIAlertAction actionWithTitle:@"Сохранить" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *v = al.textFields.firstObject.text;
        if (v.length > 0 && onSave) onSave(v);
    }]];
    [self presentViewController:al animated:YES completion:nil];
}

- (void)onProviderChanged:(UISegmentedControl *)seg {
    SettingsManager *sm = [SettingsManager shared];
    sm.currentProvider = (seg.selectedSegmentIndex == 0) ? @"gemini" : @"openrouter";
    [sm save];
    [_tableView reloadData];
}

- (void)onTTSModeChanged:(UISegmentedControl *)seg {
    SettingsManager *sm = [SettingsManager shared];
    sm.ttsMode = seg.selectedSegmentIndex;
    sm.localTTSEnabled = (sm.ttsMode != 0);
    [sm save];
    [_tableView reloadSections:[NSIndexSet indexSetWithIndex:2] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (BOOL)shouldAutorotate {
    return NO;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return UIInterfaceOrientationPortrait;
}
@end

// --- Slide-over / Modal Chat Window ---
@interface ChatBubbleCell : UITableViewCell
@property (nonatomic, strong) UIView *bubble;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *bodyLabel;
@property (nonatomic, strong) NSLayoutConstraint *bubbleLeading;
@property (nonatomic, strong) NSLayoutConstraint *bubbleTrailing;
@end

@implementation ChatBubbleCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        self.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _bubble = [[UIView alloc] init];
        _bubble.translatesAutoresizingMaskIntoConstraints = NO;
        _bubble.layer.cornerRadius = 18;
        _bubble.layer.masksToBounds = YES;
        [self.contentView addSubview:_bubble];
        _nameLabel = [[UILabel alloc] init];
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _nameLabel.font = AsunaFont(11, YES);
        [_bubble addSubview:_nameLabel];
        _bodyLabel = [[UILabel alloc] init];
        _bodyLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _bodyLabel.font = AsunaFont(15, NO);
        _bodyLabel.textColor = ASUNA_TEXT_WHITE;
        _bodyLabel.numberOfLines = 0;
        [_bubble addSubview:_bodyLabel];
        _bubbleLeading = [_bubble.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12];
        _bubbleTrailing = [_bubble.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12];
        [NSLayoutConstraint activateConstraints:@[
            [_bubble.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6],
            [_bubble.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6],
            [_bubble.widthAnchor constraintLessThanOrEqualToAnchor:self.contentView.widthAnchor multiplier:0.78],
            [_nameLabel.topAnchor constraintEqualToAnchor:_bubble.topAnchor constant:8],
            [_nameLabel.leadingAnchor constraintEqualToAnchor:_bubble.leadingAnchor constant:12],
            [_nameLabel.trailingAnchor constraintEqualToAnchor:_bubble.trailingAnchor constant:-12],
            [_bodyLabel.topAnchor constraintEqualToAnchor:_nameLabel.bottomAnchor constant:2],
            [_bodyLabel.leadingAnchor constraintEqualToAnchor:_bubble.leadingAnchor constant:12],
            [_bodyLabel.trailingAnchor constraintEqualToAnchor:_bubble.trailingAnchor constant:-12],
            [_bodyLabel.bottomAnchor constraintEqualToAnchor:_bubble.bottomAnchor constant:-10],
        ]];
    }
    return self;
}
- (void)configureWithText:(NSString *)text role:(NSString *)role {
    BOOL isUser = [role isEqualToString:@"user"];
    _nameLabel.text = isUser ? @"Вы" : @"Асуна";
    _nameLabel.textColor = isUser ? ASUNA_PEACH_ACCENT : ASUNA_CYAN_ACCENT;
    _bodyLabel.text = text ?: @"";
    _bubble.backgroundColor = isUser ? ASUNA_USER_BUBBLE : ASUNA_BOT_BUBBLE;
    _bubble.layer.borderWidth = 1.0;
    _bubble.layer.borderColor = (isUser ? [ASUNA_PEACH_ACCENT colorWithAlphaComponent:0.25] : [UIColor colorWithWhite:1.0 alpha:0.12]).CGColor;
    _bubbleLeading.active = !isUser;
    _bubbleTrailing.active = isUser;
}
@end

@interface ChatDrawerViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@property (nonatomic, copy) void (^onNewReplyReceived)(NSString *reply);
@end

@implementation ChatDrawerViewController {
    UITableView *_tableView;
    UITextField *_inputField;
    UIButton *_sendBtn;
    UIView *_inputBar;
    UIView *_inputPill;
    NSMutableArray *_messages;
    NSString *_chatId;
    NSLayoutConstraint *_inputBarBottom;
    BOOL _waitingReply;
}

- (NSString *)stripLive2D:(NSString *)text {
    if (!text) return @"";
    NSString *clean = text;
    NSRange o = [clean rangeOfString:@"<live2d>" options:NSCaseInsensitiveSearch];
    NSRange c = [clean rangeOfString:@"</live2d>" options:NSCaseInsensitiveSearch];
    if (o.location != NSNotFound && c.location != NSNotFound && c.location > o.location) {
        clean = [clean stringByReplacingCharactersInRange:NSMakeRange(o.location, (c.location+c.length)-o.location) withString:@""];
    }
    clean = StripEmoji(clean);
    clean = [clean stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return clean.length ? clean : StripEmoji(text);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Чат с Асуной";
    self.view.backgroundColor = ASUNA_DARK_BG;
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    self.navigationController.navigationBar.translucent = YES;
    self.navigationController.navigationBar.tintColor = ASUNA_PEACH_ACCENT;
    
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Закрыть" style:UIBarButtonItemStyleDone target:self action:@selector(onClose)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCompose target:self action:@selector(onNewChat)];
    
    NSArray *all = [[ChatStore shared] allChats];
    if (all.count > 0) {
        _chatId = all.firstObject[@"id"];
        _messages = [all.firstObject[@"messages"] mutableCopy] ?: [NSMutableArray array];
    } else {
        _chatId = [[ChatStore shared] createChatWithTitle:@"Диалог"];
        _messages = [NSMutableArray array];
    }
    
    _inputBar = [[UIView alloc] init];
    _inputBar.translatesAutoresizingMaskIntoConstraints = NO;
    _inputBar.backgroundColor = [UIColor colorWithRed:0.10 green:0.10 blue:0.13 alpha:0.96];
    [self.view addSubview:_inputBar];
    
    UIView *sep = [[UIView alloc] init];
    sep.translatesAutoresizingMaskIntoConstraints = NO;
    sep.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    [_inputBar addSubview:sep];
    
    _inputPill = [[UIView alloc] init];
    _inputPill.translatesAutoresizingMaskIntoConstraints = NO;
    _inputPill.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    _inputPill.layer.cornerRadius = 20;
    [_inputBar addSubview:_inputPill];
    
    _inputField = [[UITextField alloc] init];
    _inputField.translatesAutoresizingMaskIntoConstraints = NO;
    _inputField.textColor = ASUNA_TEXT_WHITE;
    _inputField.font = AsunaFont(15, NO);
    _inputField.returnKeyType = UIReturnKeySend;
    _inputField.delegate = self;
    _inputField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"Сообщение Асуне..." attributes:@{NSForegroundColorAttributeName: ASUNA_TEXT_MUTED}];
    [_inputPill addSubview:_inputField];
    
    _sendBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    _sendBtn.translatesAutoresizingMaskIntoConstraints = NO;
    _sendBtn.backgroundColor = ASUNA_PEACH_ACCENT;
    _sendBtn.layer.cornerRadius = 18;
    [_sendBtn setTitle:@"↑" forState:UIControlStateNormal];
    [_sendBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _sendBtn.titleLabel.font = AsunaFont(18, YES);
    [_sendBtn addTarget:self action:@selector(onSend) forControlEvents:UIControlEventTouchUpInside];
    [_inputBar addSubview:_sendBtn];
    
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.backgroundColor = ASUNA_DARK_BG;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    _tableView.estimatedRowHeight = 80;
    _tableView.rowHeight = UITableViewAutomaticDimension;
    _tableView.contentInset = UIEdgeInsetsMake(12, 0, 12, 0);
    [_tableView registerClass:[ChatBubbleCell class] forCellReuseIdentifier:@"bubble"];
    [self.view addSubview:_tableView];
    [self.view sendSubviewToBack:_tableView];
    
    _inputBarBottom = [_inputBar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor];
    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:_inputBar.topAnchor],
        [_inputBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_inputBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        _inputBarBottom,
        [_inputBar.heightAnchor constraintGreaterThanOrEqualToConstant:64],
        [sep.topAnchor constraintEqualToAnchor:_inputBar.topAnchor],
        [sep.leadingAnchor constraintEqualToAnchor:_inputBar.leadingAnchor],
        [sep.trailingAnchor constraintEqualToAnchor:_inputBar.trailingAnchor],
        [sep.heightAnchor constraintEqualToConstant:0.5],
        [_sendBtn.trailingAnchor constraintEqualToAnchor:_inputBar.trailingAnchor constant:-12],
        [_sendBtn.centerYAnchor constraintEqualToAnchor:_inputPill.centerYAnchor],
        [_sendBtn.widthAnchor constraintEqualToConstant:36],
        [_sendBtn.heightAnchor constraintEqualToConstant:36],
        [_inputPill.leadingAnchor constraintEqualToAnchor:_inputBar.leadingAnchor constant:12],
        [_inputPill.trailingAnchor constraintEqualToAnchor:_sendBtn.leadingAnchor constant:-10],
        [_inputPill.topAnchor constraintEqualToAnchor:_inputBar.topAnchor constant:10],
        [_inputPill.bottomAnchor constraintEqualToAnchor:_inputBar.bottomAnchor constant:-10],
        [_inputPill.heightAnchor constraintGreaterThanOrEqualToConstant:40],
        [_inputField.leadingAnchor constraintEqualToAnchor:_inputPill.leadingAnchor constant:14],
        [_inputField.trailingAnchor constraintEqualToAnchor:_inputPill.trailingAnchor constant:-14],
        [_inputField.topAnchor constraintEqualToAnchor:_inputPill.topAnchor constant:8],
        [_inputField.bottomAnchor constraintEqualToAnchor:_inputPill.bottomAnchor constant:-8],
    ]];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(kbWillChange:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(kbWillHide:) name:UIKeyboardWillHideNotification object:nil];
    [self scrollToBottomAnimated:NO];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)kbWillChange:(NSNotification *)n {
    CGRect end = [n.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    NSTimeInterval dur = [n.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationCurve curve = [n.userInfo[UIKeyboardAnimationCurveUserInfoKey] integerValue];
    CGRect endInView = [self.view convertRect:end fromView:nil];
    CGFloat overlap = MAX(0, CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(endInView));
    _inputBarBottom.constant = -overlap;
    [UIView animateWithDuration:dur delay:0 options:(curve << 16) animations:^{ [self.view layoutIfNeeded]; } completion:nil];
    [self scrollToBottomAnimated:YES];
}
- (void)kbWillHide:(NSNotification *)n {
    NSTimeInterval dur = [n.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    _inputBarBottom.constant = 0;
    [UIView animateWithDuration:dur animations:^{ [self.view layoutIfNeeded]; }];
}

- (void)scrollToBottomAnimated:(BOOL)animated {
    if (_messages.count == 0) return;
    NSIndexPath *ip = [NSIndexPath indexPathForRow:_messages.count-1 inSection:0];
    dispatch_async(dispatch_get_main_queue(), ^{ [self->_tableView scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionBottom animated:animated]; });
}

- (void)onClose { [self.view endEditing:YES]; [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)onNewChat {
    _chatId = [[ChatStore shared] createChatWithTitle:@"Диалог"];
    _messages = [NSMutableArray array];
    [_tableView reloadData];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField { [self onSend]; return NO; }

- (void)onSend {
    NSString *txt = [_inputField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (txt.length == 0 || _waitingReply) return;
    _inputField.text = @"";
    
    [_messages addObject:@{@"role": @"user", @"text": txt}];
    [[ChatStore shared] saveMessages:_messages forChatId:_chatId];
    [_tableView reloadData];
    [self scrollToBottomAnimated:YES];
    
    _waitingReply = YES;
    SettingsManager *sm = [SettingsManager shared];
    NSString *urlStr = [NSString stringWithFormat:@"%@/chat", sm.proxyUrl];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr]];
    req.HTTPMethod = @"POST";
    req.timeoutInterval = 45;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    
    NSMutableArray *wire = [NSMutableArray array];
    [wire addObject:@{@"role": @"system", @"parts": @[@"Ты Асуна (Yuuki Asuna) — живая, тёплая и заботливая. Отвечай кратко и естественно по-русски, без эмодзи и смайликов. В конце ответа добавляй <live2d>{\"expression\":\"F_FUN\",\"motion_group\":\"idle\",\"motion_index\":0,\"eye_open\":1,\"gestures\":[{\"name\":\"nod\",\"side\":\"right\",\"intensity\":0.6,\"speed\":1}]}</live2d> (подбирай expression/gestures по смыслу, глаза открыты)."]}];
    for (NSDictionary *m in _messages) {
        [wire addObject:@{@"role": m[@"role"], @"parts": @[m[@"text"] ?: @""]}];
    }
    
    NSDictionary *body = @{
        @"provider": sm.currentProvider, @"model": [sm activeModel], @"messages": wire,
        @"gemini_api_key": sm.geminiKey, @"openrouter_api_key": sm.openRouterKey
    };
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_waitingReply = NO;
            NSString *rep = @"(нет ответа)";
            if (data) {
                NSDictionary *res = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                rep = res[@"reply"] ?: res[@"error"] ?: @"(нет ответа)";
            } else if (error) {
                rep = [NSString stringWithFormat:@"Ошибка: %@", error.localizedDescription];
            }
            NSString *clean = [self stripLive2D:rep];
            [self->_messages addObject:@{@"role": @"assistant", @"text": clean}];
            [[ChatStore shared] saveMessages:self->_messages forChatId:self->_chatId];
            [self->_tableView reloadData];
            [self scrollToBottomAnimated:YES];
            if (self.onNewReplyReceived) self.onNewReplyReceived(rep); // raw, so main can apply <live2d>
        });
    }] resume];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return _messages.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    ChatBubbleCell *cell = [tableView dequeueReusableCellWithIdentifier:@"bubble" forIndexPath:indexPath];
    NSDictionary *m = _messages[indexPath.row];
    [cell configureWithText:m[@"text"] role:m[@"role"]];
    return cell;
}

- (BOOL)shouldAutorotate { return NO; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskPortrait; }
- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation { return UIInterfaceOrientationPortrait; }
@end

// --- MAIN SCREEN: Asuna Liquid Glass Character Centerpiece with Floating Dock ---
@interface AsunaMainViewController : UIViewController <AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate>
@end

@implementation AsunaMainViewController {
    CAGradientLayer *_backgroundGradientLayer;
    UIImageView *_customBgImageView;
    NSInteger _currentBgIndex;
    
    AsunaLive2DView *_live2dCharacterView;
    UIView *_speechBubblePill;
    UILabel *_speechBubbleLabel;
    
    UIView *_bottomDockBar;
    UIButton *_dockChatBtn;
    UIButton *_dockSwapBtn;
    UIButton *_dockPttOrb;
    UIButton *_dockChipBtn;
    UIButton *_dockSettingsBtn;
    
    // Audio recording & Speech recognition
    AVAudioRecorder *_audioRecorder;
    NSURL *_audioFileURL;
    BOOL _isRecording;
    SFSpeechRecognizer *_speechRecognizer;
    AVSpeechSynthesizer *_speechSynthesizer;
    AVAudioPlayer *_asunaAudioPlayer;
    NSTimer *_asunaMeterTimer;
    BOOL _isTTSSpeaking;
    NSTimer *_lipSyncTimer;
    NSTimeInterval _lipSyncPhase;
    float _lipSyncCurrent;
    float _lipSyncTarget;
    float _lipSyncEnergy;
    BOOL _isAdjustingLayout;
    UIView *_adjustOverlay;
    UIPanGestureRecognizer *_adjustPan;
    UIPinchGestureRecognizer *_adjustPinch;
    CGFloat _adjustStartOX, _adjustStartOY, _adjustStartScale;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.07 green:0.05 blue:0.09 alpha:1.0];
    
    [self setupSpeech];
    [self setupCharacterHero];
    [self setupSpeechBubble];
    [self setupFloatingDock];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];
}

- (BOOL)shouldAutorotate {
    return NO;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return UIInterfaceOrientationPortrait;
}

- (void)setupSpeech {
    _speechSynthesizer = [[AVSpeechSynthesizer alloc] init];
    _speechSynthesizer.delegate = self;
    
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];
    [session setActive:YES error:nil];
    
    NSString *tmp = NSTemporaryDirectory();
    _audioFileURL = [NSURL fileURLWithPath:[tmp stringByAppendingPathComponent:@"ptt_speech.wav"]];
    
    _speechRecognizer = [[SFSpeechRecognizer alloc] initWithLocale:[NSLocale localeWithLocaleIdentifier:@"ru-RU"]];
    if (!_speechRecognizer) {
        _speechRecognizer = [[SFSpeechRecognizer alloc] initWithLocale:[NSLocale currentLocale]];
    }
    [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status) {}];
}

// 1. Live2D Interactive Animated Character View (Cubism 2 WebGL engine)
- (void)setupCharacterHero {
    // Dynamic Liquid Glass Ambient Background
    _backgroundGradientLayer = [CAGradientLayer layer];
    _backgroundGradientLayer.frame = self.view.bounds;
    [self.view.layer addSublayer:_backgroundGradientLayer];
    
    // Custom Wallpaper View
    _customBgImageView = [[UIImageView alloc] initWithFrame:self.view.bounds];
    _customBgImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _customBgImageView.contentMode = UIViewContentModeScaleAspectFill;
    _customBgImageView.clipsToBounds = YES;
    _customBgImageView.hidden = YES;
    [self.view addSubview:_customBgImageView];
    
    [self updateBackgroundDisplay];
    
    // Double-tap anywhere to cycle background themes
    UITapGestureRecognizer *bgDoubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(cycleNextBackground)];
    bgDoubleTap.numberOfTapsRequired = 2;
    [self.view addGestureRecognizer:bgDoubleTap];
    

    // Native Live2D Cubism 2.1 Character View (OpenGL ES 1.1 / GLKit)
    _live2dCharacterView = [[AsunaLive2DView alloc] initWithFrame:self.view.bounds];
    _live2dCharacterView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_live2dCharacterView];
    
    // Load saved outfit and display settings
    SettingsManager *sm = [SettingsManager shared];
    _live2dCharacterView.displayPreset = sm.displayPreset;
    _live2dCharacterView.freeScale = (sm.freeScale < 0.2 ? 1.0 : sm.freeScale);
    _live2dCharacterView.freeOffsetX = sm.freeOffsetX;
    _live2dCharacterView.freeOffsetY = sm.freeOffsetY;
    NSString *avatar = (sm.currentAvatar && sm.currentAvatar.length > 0) ? sm.currentAvatar : @"asuna_01";
    [_live2dCharacterView loadModelNamed:avatar];

    // Tap gesture for interactive reactions
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onCharacterTapped:)];
    tap.cancelsTouchesInView = NO;
    [_live2dCharacterView addGestureRecognizer:tap];
    
    // Follow finger
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onCharacterPanned:)];
    pan.cancelsTouchesInView = NO;
    [_live2dCharacterView addGestureRecognizer:pan];
    [tap requireGestureRecognizerToFail:pan];
}

- (void)onCharacterPanned:(UIPanGestureRecognizer *)pan {
    if (!_live2dCharacterView) return;
    if (_isAdjustingLayout) {
        CGPoint t = [pan translationInView:self.view];
        if (pan.state == UIGestureRecognizerStateBegan) {
            _adjustStartOX = _live2dCharacterView.freeOffsetX;
            _adjustStartOY = _live2dCharacterView.freeOffsetY;
        }
        _live2dCharacterView.freeOffsetX = _adjustStartOX + t.x;
        _live2dCharacterView.freeOffsetY = _adjustStartOY + t.y;
        return;
    }
    CGPoint p = [pan locationInView:_live2dCharacterView];
    CGSize sz = _live2dCharacterView.bounds.size;
    if (sz.width <= 1 || sz.height <= 1) return;
    if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled || pan.state == UIGestureRecognizerStateFailed) {
        [_live2dCharacterView resetLookAt];
        return;
    }
    CGFloat nx = (p.x / sz.width) * 2.0 - 1.0;
    CGFloat ny = 1.0 - (p.y / sz.height) * 2.0; // up positive
    [_live2dCharacterView lookAtNormalizedPoint:CGPointMake(nx, ny)];
}

- (void)onCharacterPinched:(UIPinchGestureRecognizer *)pinch {
    if (!_isAdjustingLayout || !_live2dCharacterView) return;
    if (pinch.state == UIGestureRecognizerStateBegan) {
        _adjustStartScale = _live2dCharacterView.freeScale;
        if (_adjustStartScale < 0.2) _adjustStartScale = [SettingsManager shared].freeScale;
        if (_adjustStartScale < 0.2) _adjustStartScale = 1.0;
    }
    CGFloat s = _adjustStartScale * pinch.scale;
    if (s < 0.4) s = 0.4;
    if (s > 4.0) s = 4.0;
    _live2dCharacterView.freeScale = s;
}

- (void)enterCharacterAdjustMode {
    if (_isAdjustingLayout) return;
    SettingsManager *sm = [SettingsManager shared];
    sm.displayPreset = 3;
    [sm save];
    _live2dCharacterView.displayPreset = 3;
    _live2dCharacterView.freeScale = (sm.freeScale < 0.2 ? 1.0 : sm.freeScale);
    _live2dCharacterView.freeOffsetX = sm.freeOffsetX;
    _live2dCharacterView.freeOffsetY = sm.freeOffsetY;
    _adjustStartScale = _live2dCharacterView.freeScale;
    _isAdjustingLayout = YES;
    _bottomDockBar.hidden = YES;
    _speechBubblePill.hidden = YES;
    
    if (!_adjustPinch) {
        _adjustPinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(onCharacterPinched:)];
        [_live2dCharacterView addGestureRecognizer:_adjustPinch];
    }
    _adjustPinch.enabled = YES;
    
    _adjustOverlay = [[UIView alloc] initWithFrame:CGRectMake(12, 40, self.view.bounds.size.width - 24, 56)];
    _adjustOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleBottomMargin;
    _adjustOverlay.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.78];
    _adjustOverlay.layer.cornerRadius = 16;
    [self.view addSubview:_adjustOverlay];
    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(12, 6, _adjustOverlay.bounds.size.width - 140, 44)];
    hint.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    hint.text = @"Перетащите и масштабируйте (2 пальца), затем зафиксируйте";
    hint.textColor = [UIColor whiteColor];
    hint.font = AsunaFont(13, NO);
    hint.numberOfLines = 2;
    [_adjustOverlay addSubview:hint];
    UIButton *ok = [UIButton buttonWithType:UIButtonTypeSystem];
    ok.frame = CGRectMake(_adjustOverlay.bounds.size.width - 120, 10, 108, 36);
    ok.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    ok.backgroundColor = ASUNA_PEACH_ACCENT;
    ok.layer.cornerRadius = 12;
    [ok setTitle:@"Зафиксировать" forState:UIControlStateNormal];
    [ok setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [ok addTarget:self action:@selector(finishCharacterAdjustMode) forControlEvents:UIControlEventTouchUpInside];
    [_adjustOverlay addSubview:ok];
}

- (void)finishCharacterAdjustMode {
    SettingsManager *sm = [SettingsManager shared];
    sm.displayPreset = 3;
    sm.freeScale = _live2dCharacterView.freeScale;
    sm.freeOffsetX = _live2dCharacterView.freeOffsetX;
    sm.freeOffsetY = _live2dCharacterView.freeOffsetY;
    _live2dCharacterView.displayPreset = 3;
    [sm save];
    _isAdjustingLayout = NO;
    if (_adjustPinch) _adjustPinch.enabled = NO;
    [_adjustOverlay removeFromSuperview];
    _adjustOverlay = nil;
    _bottomDockBar.hidden = NO;
}

- (void)updateBackgroundDisplay {
    NSString *customPath = [SettingsManager shared].customBgPath;
    if (customPath && [[NSFileManager defaultManager] fileExistsAtPath:customPath]) {
        UIImage *img = [UIImage imageWithContentsOfFile:customPath];
        if (img) {
            _customBgImageView.image = img;
            _customBgImageView.hidden = NO;
            _backgroundGradientLayer.hidden = YES;
            return;
        }
    }
    _customBgImageView.hidden = YES;
    _backgroundGradientLayer.hidden = NO;
    [self applyBackgroundTheme:_currentBgIndex];
}

// Background themes: Obsidian Dark, SAO Sunset, Cyberpunk Cyan, Lavender Dream, Pure OLED Black
- (void)applyBackgroundTheme:(NSInteger)themeIdx {
    _currentBgIndex = themeIdx % 5;
    if (_currentBgIndex < 0) _currentBgIndex += 5;
    
    UIColor *bgColor = ASUNA_DARK_BG;
    NSArray *colors = nil;
    
    switch (_currentBgIndex) {
        case 0: // Obsidian Liquid Glass (Default)
            bgColor = [UIColor colorWithRed:0.07 green:0.06 blue:0.09 alpha:1.0];
            colors = @[
                (id)[UIColor colorWithRed:0.25 green:0.18 blue:0.32 alpha:0.45].CGColor,
                (id)[UIColor colorWithRed:0.07 green:0.06 blue:0.09 alpha:1.0].CGColor
            ];
            break;
        case 1: // SAO Aincrad Sunset (Warm Peach & Crimson)
            bgColor = [UIColor colorWithRed:0.12 green:0.05 blue:0.08 alpha:1.0];
            colors = @[
                (id)[UIColor colorWithRed:0.85 green:0.35 blue:0.28 alpha:0.45].CGColor,
                (id)[UIColor colorWithRed:0.25 green:0.10 blue:0.22 alpha:0.60].CGColor,
                (id)[UIColor colorWithRed:0.12 green:0.05 blue:0.08 alpha:1.0].CGColor
            ];
            break;
        case 2: // Cyberpunk Neon Cyan
            bgColor = [UIColor colorWithRed:0.04 green:0.07 blue:0.12 alpha:1.0];
            colors = @[
                (id)[UIColor colorWithRed:0.12 green:0.45 blue:0.60 alpha:0.50].CGColor,
                (id)[UIColor colorWithRed:0.04 green:0.07 blue:0.12 alpha:1.0].CGColor
            ];
            break;
        case 3: // Lavender Dream
            bgColor = [UIColor colorWithRed:0.10 green:0.07 blue:0.15 alpha:1.0];
            colors = @[
                (id)[UIColor colorWithRed:0.50 green:0.30 blue:0.75 alpha:0.45].CGColor,
                (id)[UIColor colorWithRed:0.10 green:0.07 blue:0.15 alpha:1.0].CGColor
            ];
            break;
        case 4: // Pure OLED Deep Black
            bgColor = [UIColor colorWithWhite:0.02 alpha:1.0];
            colors = @[
                (id)[UIColor colorWithWhite:0.12 alpha:0.30].CGColor,
                (id)[UIColor colorWithWhite:0.02 alpha:1.0].CGColor
            ];
            break;
    }
    
    [UIView animateWithDuration:0.35 animations:^{
        self.view.backgroundColor = bgColor;
        self->_backgroundGradientLayer.colors = colors;
        self->_backgroundGradientLayer.startPoint = CGPointMake(0.5, 0.0);
        self->_backgroundGradientLayer.endPoint = CGPointMake(0.5, 0.95);
    }];
}

- (void)cycleNextBackground {
    [SettingsManager shared].customBgPath = nil;
    [[SettingsManager shared] save];
    _customBgImageView.hidden = YES;
    _backgroundGradientLayer.hidden = NO;
    [self applyBackgroundTheme:_currentBgIndex + 1];
}

// 2. Floating Liquid Glass Speech Bubble (for replies and live status)
- (void)setupSpeechBubble {
    CGFloat w = MIN(self.view.bounds.size.width - 40, 520);
    _speechBubblePill = [[UIView alloc] initWithFrame:CGRectMake((self.view.bounds.size.width - w)/2, 60, w, 56)];
    _speechBubblePill.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    _speechBubblePill.backgroundColor = ASUNA_GLASS_CARD;
    ApplyLiquidGlass(_speechBubblePill, 22, YES);
    
    _speechBubbleLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 8, w - 32, 40)];
    _speechBubbleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _speechBubbleLabel.numberOfLines = 2;
    _speechBubbleLabel.textColor = ASUNA_TEXT_WHITE;
    _speechBubbleLabel.font = AsunaFont(14, YES);
    _speechBubbleLabel.textAlignment = NSTextAlignmentCenter;
    _speechBubbleLabel.text = @"";
    [_speechBubblePill addSubview:_speechBubbleLabel];
    
    _speechBubblePill.hidden = YES;
    _speechBubblePill.alpha = 0.0;
    [self.view addSubview:_speechBubblePill];
}

// 3. Floating Liquid Glass Capsule Dock Bar (Exact match to screenshot)
- (void)setupFloatingDock {
    CGFloat dockW = MIN(self.view.bounds.size.width - 32, 480);
    CGFloat dockH = 76;
    CGFloat dockY = self.view.bounds.size.height - dockH - 24;
    
    _bottomDockBar = [[UIView alloc] initWithFrame:CGRectMake((self.view.bounds.size.width - dockW)/2, dockY, dockW, dockH)];
    _bottomDockBar.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    _bottomDockBar.backgroundColor = ASUNA_GLASS_DOCK;
    ApplyLiquidGlass(_bottomDockBar, 38, YES);
    [self.view addSubview:_bottomDockBar];
    
    CGFloat slotW = dockW / 5.0;
    
    // Button 1: Chat Drawer
    _dockChatBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    _dockChatBtn.frame = CGRectMake(slotW * 0 + (slotW - 44)/2, (dockH - 44)/2, 44, 44);
    [_dockChatBtn setImage:[UIImage imageNamed:@"dock_chat.png"] forState:UIControlStateNormal];
    [_dockChatBtn addTarget:self action:@selector(openChatDrawer) forControlEvents:UIControlEventTouchUpInside];
    [_bottomDockBar addSubview:_dockChatBtn];
    
    // Button 2: Swap Costume / Model
    _dockSwapBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    _dockSwapBtn.frame = CGRectMake(slotW * 1 + (slotW - 44)/2, (dockH - 44)/2, 44, 44);
    [_dockSwapBtn setImage:[UIImage imageNamed:@"dock_swap.png"] forState:UIControlStateNormal];
    [_dockSwapBtn addTarget:self action:@selector(onSwapModelTapped) forControlEvents:UIControlEventTouchUpInside];
    [_bottomDockBar addSubview:_dockSwapBtn];
    
    // Button 3: CENTRAL SPHERICAL GLASS PTT ORB (Exact match to screenshot sphere)
    _dockPttOrb = [UIButton buttonWithType:UIButtonTypeCustom];
    CGFloat orbSize = 78;
    _dockPttOrb.frame = CGRectMake(slotW * 2 + (slotW - orbSize)/2, (dockH - orbSize)/2 - 4, orbSize, orbSize);
    [_dockPttOrb setImage:[UIImage imageNamed:@"orb_ptt.png"] forState:UIControlStateNormal];
    [_dockPttOrb addTarget:self action:@selector(onPttOrbTapped) forControlEvents:UIControlEventTouchUpInside];
    [_bottomDockBar addSubview:_dockPttOrb];
    
    // Button 4: Neural Chip Info / Switch Provider
    _dockChipBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    _dockChipBtn.frame = CGRectMake(slotW * 3 + (slotW - 44)/2, (dockH - 44)/2, 44, 44);
    [_dockChipBtn setImage:[UIImage imageNamed:@"dock_chip.png"] forState:UIControlStateNormal];
    [_dockChipBtn addTarget:self action:@selector(onChipTapped) forControlEvents:UIControlEventTouchUpInside];
    [_bottomDockBar addSubview:_dockChipBtn];
    
    // Button 5: Settings Gear
    _dockSettingsBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    _dockSettingsBtn.frame = CGRectMake(slotW * 4 + (slotW - 44)/2, (dockH - 44)/2, 44, 44);
    [_dockSettingsBtn setImage:[UIImage imageNamed:@"dock_settings.png"] forState:UIControlStateNormal];
    [_dockSettingsBtn addTarget:self action:@selector(openSettingsSheet) forControlEvents:UIControlEventTouchUpInside];
    [_bottomDockBar addSubview:_dockSettingsBtn];
}

- (void)onCharacterTapped:(UITapGestureRecognizer *)gesture {
    CGPoint pt = [gesture locationInView:_live2dCharacterView];
    [_live2dCharacterView triggerTapAtPoint:pt];
}

#pragma mark - Speech Recognition PTT (Push-to-Talk)

- (void)onPttOrbTapped {
    if (!_isRecording) {
        [self startRecording];
    } else {
        [self stopRecordingAndProcess];
    }
}

- (void)startRecording {
    NSDictionary *settings = @{
        AVFormatIDKey: @(kAudioFormatLinearPCM),
        AVSampleRateKey: @(16000.0),
        AVNumberOfChannelsKey: @(1),
        AVLinearPCMBitDepthKey: @(16),
        AVLinearPCMIsBigEndianKey: @(NO),
        AVLinearPCMIsFloatKey: @(NO)
    };
    NSError *err = nil;
    _audioRecorder = [[AVAudioRecorder alloc] initWithURL:_audioFileURL settings:settings error:&err];
    if (err) return;
    
    [_audioRecorder record];
    _isRecording = YES;
    
    [_dockPttOrb setImage:[UIImage imageNamed:@"orb_ptt_rec.png"] forState:UIControlStateNormal];
    _speechBubbleLabel.text = @"🎙 Слушаю вас... Нажмите еще раз на сферу для ответа.";
    _speechBubbleLabel.textColor = ASUNA_CYAN_ACCENT;
}

- (void)stopRecordingAndProcess {
    if (!_isRecording) return;
    [_audioRecorder stop];
    _isRecording = NO;
    
    [_dockPttOrb setImage:[UIImage imageNamed:@"orb_ptt.png"] forState:UIControlStateNormal];
    _speechBubbleLabel.text = @"Распознавание речи...";
    _speechBubbleLabel.textColor = ASUNA_TEXT_WHITE;
    
    NSData *data = [NSData dataWithContentsOfURL:_audioFileURL];
    if (!data || data.length < 1000) {
        _speechBubbleLabel.text = @"«Запись слишком короткая. Попробуй еще раз.»";
        return;
    }
    
    // 1. Offline on-device SFSpeechRecognizer on iPad
    if (_speechRecognizer && _speechRecognizer.isAvailable) {
        SFSpeechURLRecognitionRequest *req = [[SFSpeechURLRecognitionRequest alloc] initWithURL:_audioFileURL];
        req.shouldReportPartialResults = NO;
        [_speechRecognizer recognitionTaskWithRequest:req resultHandler:^(SFSpeechRecognitionResult *result, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (result && result.isFinal) {
                    NSString *txt = result.bestTranscription.formattedString;
                    if (txt && txt.length > 0) {
                        [self executeAIQueryWithText:txt];
                        return;
                    }
                }
                if (error) {
                    [self fallbackServerTranscription:data];
                }
            });
        }];
    } else {
        [self fallbackServerTranscription:data];
    }
}

- (void)fallbackServerTranscription:(NSData *)audioData {
    NSString *b64 = [audioData base64EncodedStringWithOptions:0];
    SettingsManager *sm = [SettingsManager shared];
    NSString *urlStr = [NSString stringWithFormat:@"%@/transcribe", sm.proxyUrl];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr]];
    req.HTTPMethod = @"POST";
    req.timeoutInterval = 25;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    
    NSDictionary *body = @{
        @"audio_base64": b64,
        @"mime_type": @"audio/wav",
        @"gemini_api_key": sm.geminiKey
    };
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (data) {
                NSDictionary *res = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                NSString *trans = res[@"transcript"];
                if (trans && trans.length > 0) {
                    [self executeAIQueryWithText:trans];
                } else {
                    self->_speechBubbleLabel.text = @"«Не удалось расслышать. Повтори, пожалуйста.»";
                }
            }
        });
    }] resume];
}

- (NSDictionary *)extractLive2DActionFromText:(NSString *)text cleanedText:(NSString **)cleanedOut {
    if (cleanedOut) *cleanedOut = text ?: @"";
    if (!text) return nil;
    NSRange open = [text rangeOfString:@"<live2d>" options:NSCaseInsensitiveSearch];
    NSRange close = [text rangeOfString:@"</live2d>" options:NSCaseInsensitiveSearch];
    if (open.location == NSNotFound || close.location == NSNotFound || close.location <= open.location) return nil;
    NSRange inner = NSMakeRange(open.location + open.length, close.location - (open.location + open.length));
    NSString *jsonStr = [text substringWithRange:inner];
    NSString *clean = [[text stringByReplacingCharactersInRange:NSMakeRange(open.location, (close.location + close.length) - open.location) withString:@""] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (cleanedOut) *cleanedOut = clean.length ? clean : text;
    NSData *jd = [jsonStr dataUsingEncoding:NSUTF8StringEncoding];
    if (!jd) return nil;
    id obj = [NSJSONSerialization JSONObjectWithData:jd options:0 error:nil];
    if ([obj isKindOfClass:[NSDictionary class]]) return obj;
    return nil;
}

- (void)executeAIQueryWithText:(NSString *)userText {
    _speechBubblePill.hidden = NO;
    _speechBubblePill.alpha = 1.0;
    _speechBubbleLabel.text = [NSString stringWithFormat:@"Вы: «%@»\nАсуна думает...", userText];
    
    SettingsManager *sm = [SettingsManager shared];
    NSString *urlStr = [NSString stringWithFormat:@"%@/chat", sm.proxyUrl];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr]];
    req.HTTPMethod = @"POST";
    req.timeoutInterval = 45;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    
    NSString *systemPrompt =
    @"Ты Асуна Юки (Yuuki Asuna) из Sword Art Online — умная, заботливая и живая. "
    @"Отвечай на русском, кратко и естественно (1-3 предложения). Не используй эмодзи и смайлики. "
    @"В КОНЦЕ каждого ответа обязательно добавь блок <live2d>{...}</live2d> с JSON (без markdown): "
    @"{\"expression\":\"F_FUN|F_FUN_SMILE|F_FUN_MAX|F_SURPRISE|F_SAD|F_ANGRY|F_THINK|F_SLEEP\","
    @"\"motion_group\":\"idle\",\"motion_index\":0,"
    @"\"head_x\":0,\"head_y\":0,\"body_angle\":0,\"eye_open\":1,\"mouth_open\":0,"
    @"\"gestures\":[{\"name\":\"wave|nod|shake_head|turn_left|turn_right|bow_casual|clap|think|happy_gesture|greeting\",\"side\":\"right\",\"intensity\":0.7,\"speed\":1}]} "
    @"Подбирай expression/gestures по смыслу ответа. head_x/head_y/body_angle в диапазоне -1..1, eye_open всегда 1.";
    
    NSArray *msgs = @[
        @{@"role": @"system", @"parts": @[systemPrompt]},
        @{@"role": @"user", @"parts": @[userText]}
    ];
    
    NSDictionary *body = @{
        @"provider": sm.currentProvider,
        @"model": [sm activeModel],
        @"messages": msgs,
        @"gemini_api_key": sm.geminiKey,
        @"openrouter_api_key": sm.openRouterKey
    };
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (data) {
                NSDictionary *res = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                NSString *raw = res[@"reply"] ?: res[@"error"] ?: @"(нет ответа)";
                NSString *clean = raw;
                NSDictionary *action = [self extractLive2DActionFromText:raw cleanedText:&clean];
                self->_speechBubbleLabel.text = clean;
                self->_speechBubbleLabel.textColor = ASUNA_PEACH_ACCENT;
                if (action) {
                    [self->_live2dCharacterView applyLive2DAction:action];
                }
                if ([SettingsManager shared].ttsMode != 0) {
                    [self speakTextLocally:clean];
                }
            } else if (error) {
                self->_speechBubbleLabel.text = [NSString stringWithFormat:@"Ошибка связи: %@", error.localizedDescription];
            }
        });
    }] resume];
}

#pragma mark - Local Speech Synthesis

- (float)lipOpennessForCharacter:(unichar)c {
    // Approximate viseme openness from character (ru/en); vowels open, consonants/punct close
    unichar lc = c;
    if (lc >= 'A' && lc <= 'Z') lc = (unichar)(lc - 'A' + 'a');
    if (lc >= L'А' && lc <= L'Я') lc = (unichar)(lc - L'А' + L'а');
    if (lc == L'ё') lc = L'е';
    switch (lc) {
        case 'a': case L'а': case L'я': return 0.85f;
        case 'o': case L'о': case L'ё': return 0.80f;
        case 'u': case L'у': case L'ю': return 0.45f;
        case 'e': case L'э': case L'е': return 0.70f;
        case 'i': case L'и': case L'ы': return 0.35f;
        case 'y': return 0.35f;
        case ' ': case '\n': case '\t': case ',': case '.': case '!': case '?': case ':': case ';': return 0.05f;
        case 'm': case 'b': case 'p': case L'м': case L'б': case L'п': return 0.08f;
        case 'f': case 'v': case L'ф': case L'в': return 0.18f;
        case 's': case 'z': case 'c': case L'с': case L'з': case L'ц': return 0.20f;
        default: break;
    }
    if ([[NSCharacterSet letterCharacterSet] characterIsMember:c]) return 0.38f;
    return 0.10f;
}

- (void)startLipSyncAnimation {
    [self stopLipSyncAnimation];
    _lipSyncPhase = 0;
    _lipSyncCurrent = 0;
    _lipSyncTarget = 0.25f;
    _lipSyncEnergy = 0.4f;
    __weak typeof(self) weakSelf = self;
    _lipSyncTimer = [NSTimer scheduledTimerWithTimeInterval:1.0/30.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { [timer invalidate]; return; }
        self->_lipSyncPhase += 0.22 + (arc4random_uniform(18) / 100.0);
        // Coarticulation-like flow: drift target toward energy, occasional soft closures (consonants), no hard "am-am"
        float drift = ((arc4random_uniform(100) / 100.0f) - 0.5f) * 0.18f;
        float base = self->_lipSyncEnergy + drift;
        // soft syllabic modulation around current energy
        base += 0.12f * sinf((float)self->_lipSyncPhase * 1.25f);
        // occasional micro-closure
        float micro = (sinf((float)self->_lipSyncPhase * 3.7f) + 1.0f) * 0.5f;
        if (micro < 0.12f) base *= 0.35f;
        if (base < 0.04f) base = 0.04f;
        if (base > 0.95f) base = 0.95f;
        self->_lipSyncTarget = base;
        // ease current toward target (natural muscle lag)
        float k = (self->_lipSyncTarget > self->_lipSyncCurrent) ? 0.35f : 0.22f;
        self->_lipSyncCurrent += (self->_lipSyncTarget - self->_lipSyncCurrent) * k;
        [self->_live2dCharacterView setLipSyncValue:self->_lipSyncCurrent];
    }];
    [[NSRunLoop mainRunLoop] addTimer:_lipSyncTimer forMode:NSRunLoopCommonModes];
}

- (void)stopLipSyncAnimation {
    if (_lipSyncTimer) { [_lipSyncTimer invalidate]; _lipSyncTimer = nil; }
    _lipSyncCurrent = 0; _lipSyncTarget = 0; _lipSyncEnergy = 0;
    [_live2dCharacterView setLipSyncValue:0.0f];
}

- (void)stopAsunaOriginalPlayback {
    if (_asunaMeterTimer) { [_asunaMeterTimer invalidate]; _asunaMeterTimer = nil; }
    if (_asunaAudioPlayer) { [_asunaAudioPlayer stop]; _asunaAudioPlayer = nil; }
}

- (void)speakTextLocally:(NSString *)rawText {
    NSString *txt = CleanSpeechText(rawText);
    if (!txt || txt.length == 0) return;
    SettingsManager *sm = [SettingsManager shared];
    NSInteger mode = sm.ttsMode;

    if (_speechSynthesizer.isSpeaking) {
        [_speechSynthesizer stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    }
    [self stopAsunaOriginalPlayback];
    [self stopLipSyncAnimation];

    if (mode == 0) return;
    if (mode == 2) {
        [self speakTextWithPiper:txt];
        return;
    }

    AVSpeechUtterance *utt = [AVSpeechUtterance speechUtteranceWithString:txt];
    utt.rate = 0.48;
    utt.pitchMultiplier = 1.15;
    utt.volume = 1.0;
    AVSpeechSynthesisVoice *v = [AVSpeechSynthesisVoice voiceWithLanguage:@"ru-RU"];
    if (!v) v = [AVSpeechSynthesisVoice voiceWithLanguage:[NSLocale currentLocale].localeIdentifier];
    utt.voice = v;
    [_speechSynthesizer speakUtterance:utt];
}

- (void)speakTextWithPiper:(NSString *)txt {
    // Local Piper (sherpa-onnx) TTS. Requires sherpa-onnx c-api linked and model bundled in tts-piper/.
    NSString *bundle = [[NSBundle mainBundle] bundlePath];
    NSArray *candidates = @[
        [bundle stringByAppendingPathComponent:@"tts-piper"],
        @"/Applications/AsunaLiquidGlass.app/tts-piper"
    ];
    NSString *modelDir = nil;
    for (NSString *c in candidates) { if ([[NSFileManager defaultManager] fileExistsAtPath:[c stringByAppendingPathComponent:@"ru_RU-irina-medium.onnx"]]) { modelDir = c; break; } }
    if (!modelDir) { self->_speechBubbleLabel.text = @"Piper: модель не найдена в tts-piper"; return; }

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @try {
            NSData *wav = [self synthesizePiperWavForText:txt modelDir:modelDir];
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) self = weakSelf;
                if (!self) return;
                if (!wav || wav.length == 0) { self->_speechBubbleLabel.text = @"Piper: локальный движок ещё не подключён (нужна сборка sherpa-onnx под iOS 10 arm64)"; return; }
                [self playAsunaAudioData:wav];
            });
        } @catch (NSException *ex) {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) self = weakSelf;
                if (!self) return;
                self->_speechBubbleLabel.text = [NSString stringWithFormat:@"Piper: ошибка (%@)", ex.reason ?: @"unknown"]; 
            });
        }
    });
}

- (NSData *)synthesizePiperWavForText:(NSString *)txt modelDir:(NSString *)modelDir {
    // TODO: integrate sherpa-onnx c-api (SherpaOnnxCreateOfflineTts / SherpaOnnxOfflineTtsGenerate).
    // For now returns nil until libsherpa-onnx built for iOS 10 arm64 is linked.
    (void)txt; (void)modelDir;
    return nil;
}

- (void)playAsunaAudioData:(NSData *)data {
    [self stopAsunaOriginalPlayback];
    NSError *err = nil;
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:nil];
    [[AVAudioSession sharedInstance] setActive:YES error:nil];
    _asunaAudioPlayer = [[AVAudioPlayer alloc] initWithData:data error:&err];
    if (!_asunaAudioPlayer || err) {
        self->_speechBubbleLabel.text = [NSString stringWithFormat:@"Asuna TTS: ошибка воспроизведения (%@)", err.localizedDescription ?: @"?"];
        return;
    }
    _asunaAudioPlayer.delegate = self;
    _asunaAudioPlayer.meteringEnabled = YES;
    [_asunaAudioPlayer prepareToPlay];
    _isTTSSpeaking = YES;
    [self startLipSyncAnimation];
    [_asunaAudioPlayer play];
    __weak typeof(self) weakSelf = self;
    _asunaMeterTimer = [NSTimer scheduledTimerWithTimeInterval:1.0/30.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || !self->_asunaAudioPlayer || !self->_asunaAudioPlayer.isPlaying) return;
        [self->_asunaAudioPlayer updateMeters];
        float db = [self->_asunaAudioPlayer averagePowerForChannel:0];
        float level = powf(10.0f, db / 20.0f);
        if (level < 0.03f) level = 0.03f; if (level > 1.0f) level = 1.0f;
        self->_lipSyncEnergy = 0.06f + level * 0.88f;
    }];
    [[NSRunLoop mainRunLoop] addTimer:_asunaMeterTimer forMode:NSRunLoopCommonModes];
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    if (player == _asunaAudioPlayer) {
        [self stopAsunaOriginalPlayback];
        _isTTSSpeaking = NO;
        [self stopLipSyncAnimation];
    }
}

- (void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer *)player error:(NSError *)error {
    if (player == _asunaAudioPlayer) {
        [self stopAsunaOriginalPlayback];
        _isTTSSpeaking = NO;
        [self stopLipSyncAnimation];
    }
}

#pragma mark - AVSpeechSynthesizerDelegate (Lip Sync)

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didStartSpeechUtterance:(AVSpeechUtterance *)utterance {
    _isTTSSpeaking = YES;
    [self startLipSyncAnimation];
}

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer willSpeakRangeOfSpeechString:(NSRange)characterRange utterance:(AVSpeechUtterance *)utterance {
    NSString *full = utterance.speechString ?: @"";
    unichar c = (characterRange.location < full.length) ? [full characterAtIndex:characterRange.location] : ' ';
    unichar n = ((characterRange.location + 1) < full.length) ? [full characterAtIndex:characterRange.location + 1] : ' ';
    float o1 = [self lipOpennessForCharacter:c];
    float o2 = [self lipOpennessForCharacter:n];
    // blend current/next for coarticulation, keep energy as target the 30fps timer eases toward
    _lipSyncEnergy = o1 * 0.65f + o2 * 0.35f;
    // nudge phase for natural rhythm, but don't hard-set mouth (avoids "am-am")
    _lipSyncPhase += 0.35f + o1 * 0.5f;
}

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didFinishSpeechUtterance:(AVSpeechUtterance *)utterance {
    _isTTSSpeaking = NO;
    [self stopLipSyncAnimation];
}

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didCancelSpeechUtterance:(AVSpeechUtterance *)utterance {
    _isTTSSpeaking = NO;
    [self stopLipSyncAnimation];
}

#pragma mark - Dock Navigation

- (void)openChatDrawer {
    ChatDrawerViewController *drawer = [[ChatDrawerViewController alloc] init];
    drawer.onNewReplyReceived = ^(NSString *reply) {
        NSString *clean = reply;
        NSDictionary *action = [self extractLive2DActionFromText:reply cleanedText:&clean];
        clean = CleanSpeechText(clean);
        self->_speechBubbleLabel.text = clean;
        if (action) [self->_live2dCharacterView applyLive2DAction:action];
        if ([SettingsManager shared].ttsMode != 0) [self speakTextLocally:clean];
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:drawer];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)onSwapModelTapped {
    NSString *bundleRoot = [[NSBundle mainBundle] bundlePath];
    NSArray *modelDirs = @[
        [bundleRoot stringByAppendingPathComponent:@"models"],
        @"/Applications/AsunaLiquidGlass.app/models"
    ];
    NSMutableArray *modelItems = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *dir in modelDirs) {
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:dir isDirectory:&isDir] || !isDir) continue;
        NSArray *contents = [[fm contentsOfDirectoryAtPath:dir error:nil] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
        for (NSString *name in contents) {
            NSString *sub = [dir stringByAppendingPathComponent:name];
            BOOL subDir = NO;
            if ([fm fileExistsAtPath:sub isDirectory:&subDir] && subDir) {
                NSString *json = [sub stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.model.json", name]];
                if ([fm fileExistsAtPath:json]) {
                    NSString *title = [name stringByReplacingOccurrencesOfString:@"asuna_" withString:@"Образ #"];
                    [modelItems addObject:@{@"name": title, @"id": name}];
                }
            }
        }
        if (modelItems.count > 0) break;
    }
    if (modelItems.count == 0) {
        for (int i = 1; i <= 56; i++) {
            NSString *mid = [NSString stringWithFormat:@"asuna_%02d", i];
            [modelItems addObject:@{@"name": [NSString stringWithFormat:@"Образ #%02d", i], @"id": mid}];
        }
    }

    __weak typeof(self) weakSelf = self;
    UIAlertController *al = [UIAlertController alertControllerWithTitle:@"Выбор модели Live2D"
                                                                message:[NSString stringWithFormat:@"Доступно образов: %lu", (unsigned long)modelItems.count]
                                                         preferredStyle:UIAlertControllerStyleAlert];
    for (NSDictionary *m in modelItems) {
        [al addAction:[UIAlertAction actionWithTitle:m[@"name"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            [self->_live2dCharacterView loadModelNamed:m[@"id"]];
            SettingsManager *sm = [SettingsManager shared];
            sm.currentAvatar = m[@"id"];
            [sm save];
            self->_speechBubbleLabel.text = [NSString stringWithFormat:@"Модель: %@", m[@"name"]];
            [self speakTextLocally:@"Образ изменен. Как тебе?"];
        }]];
    }
    [al addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:al animated:YES completion:nil];
}

- (void)onChipTapped {
    SettingsManager *sm = [SettingsManager shared];
    NSString *curr = sm.currentProvider;
    NSString *next = [curr isEqualToString:@"gemini"] ? @"openrouter" : @"gemini";
    sm.currentProvider = next;
    [sm save];
    
    NSString *msg = [NSString stringWithFormat:@"ИИ: %@ (%@)", next.uppercaseString, [sm activeModel]];
    _speechBubbleLabel.text = msg;
    [self speakTextLocally:[NSString stringWithFormat:@"Провайдер переключен на %@", next]];
}

- (void)openSettingsSheet {
    ModelsSettingsViewController *settingsVC = [[ModelsSettingsViewController alloc] init];
    __weak typeof(self) weakSelf = self;
    settingsVC.onBackgroundChanged = ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        [self updateBackgroundDisplay];
        self->_live2dCharacterView.displayPreset = [SettingsManager shared].displayPreset;
    };
    settingsVC.onDisplayChanged = ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self->_live2dCharacterView.displayPreset = [SettingsManager shared].displayPreset;
        self->_live2dCharacterView.freeScale = [SettingsManager shared].freeScale;
        self->_live2dCharacterView.freeOffsetX = [SettingsManager shared].freeOffsetX;
        self->_live2dCharacterView.freeOffsetY = [SettingsManager shared].freeOffsetY;
    };
    settingsVC.onEnterAdjustMode = ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        [self enterCharacterAdjustMode];
    };
    settingsVC.onDismissed = ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        [self updateBackgroundDisplay];
        self->_live2dCharacterView.displayPreset = [SettingsManager shared].displayPreset;
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settingsVC];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    nav.preferredContentSize = CGSizeMake(520, 600);
    [self presentViewController:nav animated:YES completion:nil];
}

@end

// --- App Delegate ---
@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    AsunaMainViewController *mainVC = [[AsunaMainViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:mainVC];
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
    return YES;
}

- (UIInterfaceOrientationMask)application:(UIApplication *)application supportedInterfaceOrientationsForWindow:(UIWindow *)window {
    return UIInterfaceOrientationMaskPortrait;
}

@end

int main(int argc, char * argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
