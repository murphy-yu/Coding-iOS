//
//  AppDelegate.m
//  Coding_iOS
//
//  Created by 王 原闯 on 14-7-29.
//  Copyright (c) 2014年 Coding. All rights reserved.
//


#define UMSYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(v) ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending) 
#define _IPHONE80_ 80000

#if DEBUG
#import <FLEX/FLEXManager.h>
#import "RRFPSBar.h"
#endif

#import "AppDelegate.h"
#import "RootTabViewController.h"
#import "LoginViewController.h"
#import "AFNetworking.h"
#import "AFNetworkActivityIndicatorManager.h"
#import "Login.h"
#import "UnReadManager.h"
#import "XGPush.h"
#import "EaseStartView.h"
#import "BaseNavigationController.h"
#import "PasswordViewController.h"
#import "IntroductionViewController.h"
#import "TweetSendViewController.h"
#import "ProjectToChooseListViewController.h"
#import "OTPListViewController.h"
#import "WikiEditViewController.h"

#import "FunctionIntroManager.h"
#import <evernote-cloud-sdk-ios/ENSDK/ENSDK.h>
#import "Coding_NetAPIManager.h"
#import "EADeviceToServerLog.h"
#import <UMSocialCore/UMSocialCore.h>

#import "Tweet.h"
#import "sys/utsname.h"

@implementation AppDelegate

@synthesize managedObjectContext = _managedObjectContext;
@synthesize managedObjectModel = _managedObjectModel;
@synthesize persistentStoreCoordinator = _persistentStoreCoordinator;

#pragma mark XGPush
- (void)registerPush{
    UIMutableUserNotificationCategory *categorys = [[UIMutableUserNotificationCategory alloc] init];
    UIUserNotificationSettings *userSettings = [UIUserNotificationSettings settingsForTypes:UIUserNotificationTypeBadge|UIUserNotificationTypeSound|UIUserNotificationTypeAlert
                                                                                 categories:[NSSet setWithObject:categorys]];
    [[UIApplication sharedApplication] registerUserNotificationSettings:userSettings];
}

#pragma mark UserAgent
- (void)registerUserAgent{
    NSString *userAgent = [NSString userAgentStr];
    NSDictionary *dictionary = @{@"UserAgent" : userAgent};//User-Agent
    [[NSUserDefaults standardUserDefaults] registerDefaults:dictionary];
}

#pragma lifeCycle
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions{
    if (kTarget_Enterprise) {//这是很早之前为测试弄的吧
        [NSObject preCookieHandle];//cookie 设置
    }

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    // Override point for customization after application launch.
    self.window.backgroundColor = [UIColor whiteColor];
    
    //网络
    [[AFNetworkActivityIndicatorManager sharedManager] setEnabled:YES];
    [[AFNetworkReachabilityManager sharedManager] startMonitoring];
    
    //sd加载的数据类型
    [[[SDWebImageManager sharedManager] imageDownloader] setValue:@"text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8" forHTTPHeaderField:@"Accept"];
    
    //设置导航条样式
    [self customizeInterface];
    [[UIApplication sharedApplication] setStatusBarHidden:NO withAnimation:UIStatusBarAnimationFade];
    
    //UIWebView 的 User-Agent
    [self registerUserAgent];

    if ([Login isLogin]) {
        [self setupTabViewController];
    }else{
        [UIApplication sharedApplication].applicationIconBadgeNumber = 0;
        [self setupIntroductionViewController];
    }
    [self.window makeKeyAndVisible];
    [FunctionIntroManager showIntroPage];

    if (kTarget_Enterprise) {
        [self completionStartAnimationWithOptions:launchOptions];
    }else{
        EaseStartView *startView = [EaseStartView new];
        @weakify(self);
        [startView startAnimationWithCompletionBlock:^(EaseStartView *easeStartView) {
            @strongify(self);
            [self completionStartAnimationWithOptions:launchOptions];
        }];
    }
    
#if DEBUG
    [[RRFPSBar sharedInstance] setShowsAverage:YES];
    [[RRFPSBar sharedInstance] setHidden:NO];
#endif
    return YES;
}

- (void)completionStartAnimationWithOptions:(NSDictionary *)launchOptions{
    if ([Login isLogin]) {
        NSDictionary *remoteNotification = [launchOptions valueForKey:UIApplicationLaunchOptionsRemoteNotificationKey];
        if (remoteNotification) {
            [BaseViewController handleNotificationInfo:remoteNotification applicationState:UIApplicationStateInactive];
        }
    }
    
    //    UMENG 统计
    UMConfigInstance.appKey = kUmeng_AppKey;
    [MobClick startWithConfigure:UMConfigInstance];
    
    if (!kTarget_Enterprise) {
        //UMSocialManager & 第三方登录
        [[UMSocialManager defaultManager] openLog:YES];
        [UMSocialGlobal shareInstance].isUsingHttpsWhenShareContent = NO;
        [[UMSocialManager defaultManager] setUmSocialAppkey:kUmeng_AppKey];
        [[UMSocialManager defaultManager] setPlaform:UMSocialPlatformType_WechatSession appKey:kSocial_WX_ID appSecret:kSocial_WX_Secret redirectURL:nil];
        [[UMSocialManager defaultManager] setPlaform:UMSocialPlatformType_QQ appKey:kSocial_QQ_ID  appSecret:kSocial_QQ_Secret redirectURL:nil];
        [[UMSocialManager defaultManager] setPlaform:UMSocialPlatformType_Sina appKey:kSocial_Sina_ID  appSecret:kSocial_Sina_Secret redirectURL:kSocial_Sina_RedirectURL];
        [ENSession setSharedSessionConsumerKey:kSocial_EN_Key consumerSecret:kSocial_EN_Secret optionalHost:nil];
    }
    
    //    信鸽推送
    [XGPush startApp:kXGPush_Id appKey:kXGPush_Key];
    [Login setXGAccountWithCurUser];
    //注销之后需要再次注册前的准备
    @weakify(self);
    void (^successCallback)(void) = ^(void){
        //如果变成需要注册状态
        if([XGPush isUnRegisterStatus] && [Login isLogin]){
            @strongify(self);
            [self registerPush];
        }
    };
    [XGPush initForReregister:successCallback];
    
    //[XGPush registerPush];  //注册Push服务，注册后才能收到推送
    
    //推送反馈(app不在前台运行时，点击推送激活时。统计而已)
    [XGPush handleLaunching:launchOptions];
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
    if ([[BaseViewController presentingVC] isKindOfClass:[WikiEditViewController class]]) {
        [(WikiEditViewController *)[BaseViewController presentingVC] saveWikiDraft];
    }
    [[ImageSizeManager shareManager] save];
    [[Tweet tweetForSend] saveSendData];
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later. 
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    if ([Login isLogin]) {
        [[UnReadManager shareManager] updateUnRead];
        UIViewController *presentingVC = [BaseViewController presentingVC];
        SEL selector = NSSelectorFromString(@"refresh");
        if ([presentingVC isKindOfClass:NSClassFromString(@"Message_RootViewController")]
            && [presentingVC respondsToSelector:selector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [presentingVC performSelector:selector];
#pragma clang diagnostic pop
        }
    }
    //    CODING 报告
    [[EADeviceToServerLog shareManager] tryToStart];
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Saves changes in the application's managed object context before the application terminates.
    [self saveContext];
}

#ifndef Target_Enterprise

// Universal Links - 个人版支持的东西
#pragma mark Universal Links

- (BOOL)application:(UIApplication *)application continueUserActivity:(NSUserActivity *)userActivity restorationHandler:(void(^)(NSArray * __nullable restorableObjects))restorationHandler{
    if ([userActivity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb]) {
//        UIViewController *vc = [BaseViewController analyseVCFromLinkStr:userActivity.webpageURL.absoluteString];
//        if (vc) {
//            [BaseViewController presentVC:vc];
//        }
        [BaseViewController presentLinkStr:userActivity.webpageURL.absoluteString];//支持的链接就 native 打开，不支持的就用 web 打开
    }else{
        [[UIApplication sharedApplication] openURL:userActivity.webpageURL];
    }
    return YES;
}

#endif

#pragma mark - XGPush Message
- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken
{
    NSString * deviceTokenStr = [XGPush registerDevice:deviceToken];
    DebugLog(@"deviceTokenStr : %@", deviceTokenStr);
}

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo
{
    DebugLog(@"didReceiveRemoteNotification-userInfo:-----\n%@", userInfo);
    [XGPush handleReceiveNotification:userInfo];
    [BaseViewController handleNotificationInfo:userInfo applicationState:[application applicationState]];
}

- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error{
    DebugLog(@"%@", error);
}

- (void)application:(UIApplication *)application didRegisterUserNotificationSettings:(UIUserNotificationSettings *)notificationSettings{
    DebugLog(@"%@", notificationSettings);
    [application registerForRemoteNotifications];
}

#pragma mark - Methods Private
- (void)setupLoginViewController{
#ifdef Target_Enterprise
    
    IntroductionViewController *introductionVC = [[IntroductionViewController alloc] init];
    [self.window setRootViewController:introductionVC];
    [introductionVC presentLoginUI];

#else
    
    LoginViewController *loginVC = [[LoginViewController alloc] init];
    [self.window setRootViewController:[[UINavigationController alloc] initWithRootViewController:loginVC]];
    
#endif
}

- (void)setupIntroductionViewController{
    if (kTarget_Enterprise) {
        IntroductionViewController *introductionVC = [[IntroductionViewController alloc] init];
        [self.window setRootViewController:introductionVC];
    }else{
        [self setupLoginViewController];//猥琐换
//        IntroductionViewController *introductionVC = [[IntroductionViewController alloc] init];
//        [self.window setRootViewController:introductionVC];
    }
}

- (void)setupTabViewController{
    RootTabViewController *rootVC = [[RootTabViewController alloc] init];
    rootVC.tabBar.translucent = YES;
    
    [self.window setRootViewController:rootVC];
}

- (void)customizeInterface {
    {//UIBarButtonItem 颜色&字体
        NSDictionary *textAttributes = @{
                                         NSFontAttributeName: [UIFont systemFontOfSize:kBackButtonFontSize],
                                         NSForegroundColorAttributeName: kColorLightBlue,
                                         };
        [[UIBarButtonItem appearance] setTitleTextAttributes:textAttributes forState:UIControlStateNormal];
        [[UIBarButtonItem appearance] setTitleTextAttributes:@{NSFontAttributeName: [UIFont systemFontOfSize:kBackButtonFontSize]} forState:UIControlStateDisabled];
        [[UIBarButtonItem appearance] setTitleTextAttributes:@{NSFontAttributeName: [UIFont systemFontOfSize:kBackButtonFontSize]} forState:UIControlStateHighlighted];
    }
    //设置Nav的背景色和title色
    UINavigationBar *navigationBarAppearance = [UINavigationBar appearance];
    [navigationBarAppearance setBackgroundImage:[UIImage imageWithColor:[NSObject baseURLStrIsProduction]? kColorNavBG: kColorActionYellow] forBarMetrics:UIBarMetricsDefault];
    [navigationBarAppearance setTintColor:kColorLightBlue];//返回按钮的箭头颜色
    NSDictionary *textAttributes = @{
                                     NSFontAttributeName: [UIFont systemFontOfSize:kNavTitleFontSize],
                                     NSForegroundColorAttributeName: kColorNavTitle,
                                     };
    [navigationBarAppearance setTitleTextAttributes:textAttributes];
    navigationBarAppearance.backIndicatorImage = [UIImage imageNamed:@"back_green_Nav"];
    navigationBarAppearance.backIndicatorTransitionMaskImage = [UIImage imageNamed:@"back_green_Nav"];

    [[UITextField appearance] setTintColor:kColorLightBlue];//设置UITextField的光标颜色
    [[UITextView appearance] setTintColor:kColorLightBlue];//设置UITextView的光标颜色
    [[UISearchBar appearance] setBackgroundImage:[UIImage imageWithColor:kColorTableSectionBg] forBarPosition:0 barMetrics:UIBarMetricsDefault];
}

#pragma mark URL Schemes
- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options{
    DebugLog(@"path: %@, params: %@", [url path], [url queryParams]);
    if ([url.absoluteString hasPrefix:kCodingAppScheme]) {
        NSDictionary *queryParams = [url queryParams];
        if ([url.host isEqualToString:@"safepay"]) {//支付宝支付
            [self p_handlePayURL:url];
        }else if (queryParams[@"email"] && queryParams[@"key"]) {//重置密码
            [self showPasswordWithURL:url];
        }else if ([queryParams[@"type"] isEqualToString:@"tweet"]){//发冒泡
            if ([Login isLogin]) {
                [TweetSendViewController presentWithParams:queryParams];
            }else{
                [NSObject showHudTipStr:@"未登录"];
            }
        }else{//一般模式解析网页
            [BaseViewController presentLinkStr:url.absoluteString];
        }
    }else if ([url.scheme isEqualToString:kSocial_WX_ID] && [url.host isEqualToString:@"pay"]){//微信支付
        [self p_handlePayURL:url];
    }else if ([url.absoluteString hasPrefix:@"en-:"]){
        return [[ENSession sharedSession] handleOpenURL:url];
    }else{
        return [[UMSocialManager defaultManager] handleOpenURL:url options:options];
    }
    return YES;
}

//- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation{
//    DebugLog(@"path: %@, params: %@", [url path], [url queryParams]);
//    if ([url.absoluteString hasPrefix:kCodingAppScheme]) {
//        NSDictionary *queryParams = [url queryParams];
//        if ([url.host isEqualToString:@"safepay"]) {//支付宝支付
//            [self p_handlePayURL:url];
//        }else if (queryParams[@"email"] && queryParams[@"key"]) {//重置密码
//            [self showPasswordWithURL:url];
//        }else if ([queryParams[@"type"] isEqualToString:@"tweet"]){//发冒泡
//            if ([Login isLogin]) {
//                [TweetSendViewController presentWithParams:queryParams];
//            }else{
//                [NSObject showHudTipStr:@"未登录"];
//            }
//        }else{//一般模式解析网页
//            [BaseViewController presentLinkStr:url.absoluteString];
//        }
//    }else if ([url.scheme isEqualToString:kSocial_WX_ID] && [url.host isEqualToString:@"pay"]){//微信支付
//        [self p_handlePayURL:url];
//    }else if ([url.absoluteString hasPrefix:@"en-:"]){
//        return [[ENSession sharedSession] handleOpenURL:url];
//    }else{
//        return [[UMSocialManager defaultManager] handleOpenURL:url sourceApplication:sourceApplication annotation:annotation];
//    }
//    return YES;
//}

- (void)p_handlePayURL:(NSURL *)url{
    UIViewController *vc = [BaseViewController presentingVC];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
    if ([vc respondsToSelector:@selector(handlePayURL:)]) {
        [vc performSelector:@selector(handlePayURL:) withObject:url];
    }
#pragma clang diagnostic pop
}

- (BOOL)showPasswordWithURL:(NSURL *)url{
    PasswordType type;
    NSString *email, *key;
    
    if ([[url lastPathComponent] isEqualToString:@"resetPassword"]) {
        type = PasswordReset;
    }else if ([[url lastPathComponent] isEqualToString:@"activate"]){
        type = PasswordActivate;
    }else{
        return NO;
    }
    email = [[url queryParams] objectForKey:@"email"];
    key = [[url queryParams] objectForKey:@"key"];
    if (email.length <= 0 || key.length <= 0) {
        return NO;
    }
    
    //弹出临时会话
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        PasswordViewController *vc = [PasswordViewController passwordVCWithType:type email:[email URLDecoding] andKey:key];
        vc.successBlock = ^(PasswordViewController *presentVC, id data){
            [presentVC dismissViewControllerAnimated:YES completion:^{
                NSString *tipStr;
                switch (presentVC.type) {
                    case PasswordReset:
                        tipStr = @"修改密码成功～";
                        break;
                    case PasswordActivate:
                        tipStr = @"账号激活成功～";
                        break;
                    default:
                        tipStr = @"操作成功";
                        break;
                }
                kTipAlert(@"%@", tipStr);
            }];
        };
        [BaseViewController presentVC:vc];
    });
    return YES;
}

#pragma mark - Methods Core Data

- (void)saveContext
{
    NSError *error = nil;
    NSManagedObjectContext *managedObjectContext = self.managedObjectContext;
    if (managedObjectContext != nil) {
        if ([managedObjectContext hasChanges] && ![managedObjectContext save:&error]) {
             // Replace this implementation with code to handle the error appropriately.
             // abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development. 
            DebugLog(@"Unresolved error %@, %@", error, [error userInfo]);
            abort();
        } 
    }
}

#pragma mark - Core Data stack

// Returns the managed object context for the application.
// If the context doesn't already exist, it is created and bound to the persistent store coordinator for the application.
- (NSManagedObjectContext *)managedObjectContext
{
    if (_managedObjectContext != nil) {
        return _managedObjectContext;
    }
    
    NSPersistentStoreCoordinator *coordinator = [self persistentStoreCoordinator];
    if (coordinator != nil) {
        _managedObjectContext = [[NSManagedObjectContext alloc] init];
        [_managedObjectContext setPersistentStoreCoordinator:coordinator];
    }
    return _managedObjectContext;
}

// Returns the managed object model for the application.
// If the model doesn't already exist, it is created from the application's model.
- (NSManagedObjectModel *)managedObjectModel
{
    if (_managedObjectModel != nil) {
        return _managedObjectModel;
    }
    NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"Coding_iOS" withExtension:@"momd"];
    _managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    return _managedObjectModel;
}

// Returns the persistent store coordinator for the application.
// If the coordinator doesn't already exist, it is created and the application's store added to it.
- (NSPersistentStoreCoordinator *)persistentStoreCoordinator
{
    if (_persistentStoreCoordinator != nil) {
        return _persistentStoreCoordinator;
    }
    
    NSURL *storeURL = [[self applicationDocumentsDirectory] URLByAppendingPathComponent:@"Coding_iOS.sqlite"];
    
    NSError *error = nil;
    _persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[self managedObjectModel]];
    if (![_persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil error:&error]) {
        /*
         Replace this implementation with code to handle the error appropriately.
         
         abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development. 
         
         Typical reasons for an error here include:
         * The persistent store is not accessible;
         * The schema for the persistent store is incompatible with current managed object model.
         Check the error message to determine what the actual problem was.
         
         
         If the persistent store is not accessible, there is typically something wrong with the file path. Often, a file URL is pointing into the application's resources directory instead of a writeable directory.
         
         If you encounter schema incompatibility errors during development, you can reduce their frequency by:
         * Simply deleting the existing store:
         [[NSFileManager defaultManager] removeItemAtURL:storeURL error:nil]
         
         * Performing automatic lightweight migration by passing the following dictionary as the options parameter:
         @{NSMigratePersistentStoresAutomaticallyOption:@YES, NSInferMappingModelAutomaticallyOption:@YES}
         
         Lightweight migration will only work for a limited set of schema changes; consult "Core Data Model Versioning and Data Migration Programming Guide" for details.
         
         */
        DebugLog(@"Unresolved error %@, %@", error, [error userInfo]);
        abort();
    }    
    
    return _persistentStoreCoordinator;
}

#pragma mark - Application's Documents directory

// Returns the URL to the application's Documents directory.
- (NSURL *)applicationDocumentsDirectory
{
    return [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
}

#pragma mark 3D Touch
- (void)application:(UIApplication *)application performActionForShortcutItem:(UIApplicationShortcutItem *)shortcutItem completionHandler:(void(^)(BOOL succeeded))completionHandler{
    if ([shortcutItem.type isEqualToString:@"shortcut_2FA"]){
        OTPListViewController *vc = [OTPListViewController new];
        [BaseViewController presentVC:vc];
    }else if (![Login isLogin]) {
        UIViewController *presentingVC = [BaseViewController presentingVC];
        if (![presentingVC isKindOfClass:[LoginViewController class]]) {
            LoginViewController *vc = [[LoginViewController alloc] init];
            vc.showDismissButton = YES;
            UINavigationController *nav = [[BaseNavigationController alloc] initWithRootViewController:vc];
            [presentingVC presentViewController:nav animated:YES completion:nil];
        }
    }else{
        if ([kKeyWindow.rootViewController isKindOfClass:[RootTabViewController class]]) {
            RootTabViewController *vc = (RootTabViewController *)kKeyWindow.rootViewController;
            vc.selectedIndex = ([shortcutItem.type isEqualToString:@"shortcut_task"]? 1:
                                2);
        }
        if ([shortcutItem.type isEqualToString:@"shortcut_task"]) {
            ProjectToChooseListViewController *chooseVC = [[ProjectToChooseListViewController alloc] init];
            [BaseViewController goToVC:chooseVC];
        }else if ([shortcutItem.type isEqualToString:@"shortcut_tweet"]){
            TweetSendViewController *vc = [[TweetSendViewController alloc] init];
            vc.sendNextTweet = ^(Tweet *nextTweet){
                [[Coding_NetAPIManager sharedManager] request_Tweet_DoTweet_WithObj:nextTweet andBlock:^(id data, NSError *error) {
                    if (data) {
                        if ([[BaseViewController presentingVC] respondsToSelector:NSSelectorFromString(@"refresh")]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                            [[BaseViewController presentingVC] performSelector:NSSelectorFromString(@"refresh")];
#pragma clang diagnostic pop
 
                        }
                        [Tweet deleteSendData];//发送成功后删除草稿
                    }else{
                        [nextTweet saveSendData];//发送失败，保存草稿
                    }
                }];
            };
            [BaseViewController presentVC:vc];
        }
    }
    completionHandler(YES);
}
@end
