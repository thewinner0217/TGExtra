#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "Headers.h"
#import <objc/runtime.h>

#define kEnableScheduledMessages @"enableScheduledMessages"
#define kChannelsReadHistory 0xDEADBEEF
#define kMessagesSendScheduledMessage 0xb86e380e

// DICHIARAZIONI MINIME
@interface TGModernConversationInputController : NSObject
- (id)currentMessageObject;
- (void)sendMessage:(id)message scheduleTime:(NSTimeInterval)time;
@end

@interface TGMediaPickerSendActionSheetController : NSObject
- (void)schedulePressed;
@end

#pragma mark - Utility: append to debug file
static void TGExtra_appendDebug(NSString *line) {
    NSString *logPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/tg_schedule_debug.txt"];
    @try {
        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:logPath];
        if (!h) {
            NSError *err = nil;
            [line writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:&err];
            if (err) {
                NSLog(@"[TGExtra-Debug] writeToFile error: %@", err);
            }
        } else {
            [h seekToEndOfFile];
            [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [h closeFile];
        }
    } @catch (NSException *e) {
        NSLog(@"[TGExtra-Debug] TGExtra_appendDebug EX: %@", e);
    }
}

#pragma mark - MTRequest hook
%hook MTRequest
%property (nonatomic, strong) NSData *fakeData;
%property (nonatomic, strong) NSNumber *functionID;

- (void)setPayload:(NSData *)payload metadata:(id)metadata shortMetadata:(id)shortMetadata responseParser:(id (^)(NSData *))responseParser {
    int32_t functionID = 0;
    @try { [payload getBytes:&functionID length:4]; } @catch (...) { functionID = 0; }
    self.functionID = [NSNumber numberWithInt:functionID];

    id(^hooked_block)(NSData *) = ^(NSData *inputData) {
        NSNumber *functionIDNumber = [NSNumber numberWithUnsignedInt:functionID];
        NSData *processed = [TLParser handleResponse:inputData functionID:functionIDNumber];
        if (processed) return responseParser(processed);
        return responseParser(inputData);
    };

    switch (functionID) {
        case kAccountUpdateOnlineStatus:
            handleOnlineStatus(self, payload);
            break;
        case kMessagesSetTypingAction:
            handleSetTyping(self, payload);
            break;
        case kMessagesReadHistory:
            handleMessageReadReceipt(self, payload);
            break;
        case kStoriesReadStories:
            handleStoriesReadReceipt(self, payload);
            break;
        case kGetSponsoredMessages:
            handleGetSponsoredMessages(self, payload);
            break;
        case kChannelsReadHistory:
            handleChannelsReadReceipt(self, payload);
            break;
        case kMessagesSendScheduledMessage:
            TGExtra_appendDebug(@"[Schedule] MTRequest messages.sendScheduledMessage triggered\n");
            break;
        default:
            break;
    }

    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"disableForwardRestriction"]) {
        %orig(payload, metadata, shortMetadata, hooked_block);
    } else {
        %orig(payload, metadata, shortMetadata, responseParser);
    }
}
%end

#pragma mark - TGModernConversationInputController
%hook TGModernConversationInputController

- (void)sendCurrentMessage {
    NSTimeInterval t0 = [[NSDate date] timeIntervalSince1970];
    TGExtra_appendDebug([NSString stringWithFormat:@"---- sendCurrentMessage called at %.0f ----\n", t0]);

    id message = nil;
    @try { message = [self currentMessageObject]; } @catch (NSException *e) { message = nil; }

    BOOL autoScheduled = [[NSUserDefaults standardUserDefaults] boolForKey:kEnableScheduledMessages];
    TGExtra_appendDebug([NSString stringWithFormat:@"autoScheduled=%d\n", autoScheduled]);

    if (!message) {
        TGExtra_appendDebug(@"message is nil -> %orig\n");
        %orig;
        return;
    }

    if (!autoScheduled) {
        %orig;
        return;
    }

    // Forza scheduling a +10s
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval scheduledTime = now + 10.0;

    // === PARTE CHIAVE: crea request messages.sendScheduledMessage ===
    @try {
        Class reqClass = NSClassFromString(@"TLMessagesSendMessage");
        if (reqClass) {
            id req = [[reqClass alloc] init];
            [req setValue:message forKey:@"message"];
            [req setValue:@((int32_t)scheduledTime) forKey:@"scheduleDate"];

            TGExtra_appendDebug([NSString stringWithFormat:@"[Schedule] Created TLMessagesSendMessage with scheduleDate=%.0f\n", scheduledTime]);

            // Crea MTRequest e invialo via TGTelegraph
            id mtReq = [[objc_getClass("MTRequest") alloc] initWithFunction:req];
            if (mtReq) {
                [mtReq setValue:@(kMessagesSendScheduledMessage) forKey:@"functionID"];
                id telegraph = [objc_getClass("TGTelegraph") performSelector:@selector(instance)];
                if (telegraph) {
                    [telegraph performSelector:@selector(request:) withObject:mtReq];
                    TGExtra_appendDebug(@"[Schedule] Sent MTRequest via TGTelegraph\n");
                } else {
                    TGExtra_appendDebug(@"[Schedule] TGTelegraph.instance not found\n");
                }
            }
            return; // evita %orig (niente messaggi duplicati)
        } else {
            TGExtra_appendDebug(@"[Schedule] TLMessagesSendMessage class not found\n");
        }
    } @catch (NSException *e) {
        TGExtra_appendDebug([NSString stringWithFormat:@"[Schedule] Exception: %@\n", e]);
    }

    // fallback: messaggio normale
    %orig;
}
%end

#pragma mark - MTRequest initWithFunction Hook (logging)
%hook MTRequest
- (instancetype)initWithFunction:(id)function {
    id obj = %orig;
    @try {
        if (function) {
            NSString *fnClass = NSStringFromClass([function class]);
            id scheduleDate = nil;
            @try { scheduleDate = [function valueForKey:@"scheduleDate"]; } @catch (...) { scheduleDate = nil; }
            id flagsVal = nil;
            @try { flagsVal = [function valueForKey:@"flags"]; } @catch (...) { flagsVal = nil; }
            NSString *logLine = [NSString stringWithFormat:@"MTRequest initWithFunction: class=%@ scheduleDate=%@ flags=%@\n", fnClass, scheduleDate?:@"<nil>", flagsVal?:@"<nil>"];
            TGExtra_appendDebug(logLine);
        }
    } @catch (NSException *e) {
        TGExtra_appendDebug([NSString stringWithFormat:@"MTRequest initWithFunction EX: %@\n", e]);
    }
    return obj;
}
%end

#pragma mark - TGMediaPickerSendActionSheetController
%hook TGMediaPickerSendActionSheetController

- (void)schedulePressed {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *logPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/tg_schedule_debug.txt"];
        NSError *err = nil;
        NSString *content = [NSString stringWithContentsOfFile:logPath encoding:NSUTF8StringEncoding error:&err];
        if (!content || content.length == 0) {
            content = [NSString stringWithFormat:@"No debug file or empty. err=%@", err];
        }
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"TGExtra Debug Log"
                                                                   message:content
                                                            preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *ok = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
        [a addAction:ok];

        UIViewController *vc = [UIApplication sharedApplication].keyWindow.rootViewController;
        while (vc.presentedViewController) vc = vc.presentedViewController;
        [vc presentViewController:a animated:YES completion:nil];
    });

    %orig;
}
%end
