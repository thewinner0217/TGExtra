#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "Headers.h"
#import <objc/runtime.h>

#define kEnableScheduledMessages @"enableScheduledMessages"
#define kChannelsReadHistory 0xDEADBEEF

// ==========================
// Dichiarazioni minime
// ==========================
@interface TGModernConversationInputController : NSObject
- (id)currentMessageObject;
- (void)sendMessage:(id)message scheduleTime:(NSTimeInterval)time;
@end

@interface TGMediaPickerSendActionSheetController : NSObject
- (void)schedulePressed;
@end

// ==========================
// Utility per debug
// ==========================
static void TGExtra_appendDebug(NSString *line) {
    NSString *logPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/tg_schedule_debug.txt"];
    @try {
        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:logPath];
        if (!h) {
            NSError *err = nil;
            [line writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:&err];
        } else {
            [h seekToEndOfFile];
            [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [h closeFile];
        }
    } @catch (NSException *e) {
        NSLog(@"[TGExtra-Debug] TGExtra_appendDebug EX: %@", e);
    }
}

// ==========================
// MTRequest hook originale
// ==========================
%hook MTRequest
%property (nonatomic, strong) NSData *fakeData;
%property (nonatomic, strong) NSNumber *functionID;

- (void)setPayload:(NSData *)payload metadata:(id)metadata shortMetadata:(id)shortMetadata responseParser:(id (^)(NSData *))responseParser {
    int32_t functionID = 0;
    @try { [payload getBytes:&functionID length:4]; } @catch (...) { functionID = 0; }
    self.functionID = @(functionID);

    id(^hooked_block)(NSData *) = ^(NSData *inputData) {
        NSData *processed = [TLParser handleResponse:inputData functionID:@(functionID)];
        return responseParser(processed ?: inputData);
    };

    // Esegui handlers esistenti
    switch (functionID) {
        case kAccountUpdateOnlineStatus: handleOnlineStatus(self, payload); break;
        case kMessagesSetTypingAction: handleSetTyping(self, payload); break;
        case kMessagesReadHistory: handleMessageReadReceipt(self, payload); break;
        case kStoriesReadStories: handleStoriesReadReceipt(self, payload); break;
        case kGetSponsoredMessages: handleGetSponsoredMessages(self, payload); break;
        case kChannelsReadHistory: handleChannelsReadReceipt(self, payload); break;
        default: break;
    }

    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"disableForwardRestriction"]) {
        %orig(payload, metadata, shortMetadata, hooked_block);
    } else {
        %orig(payload, metadata, shortMetadata, responseParser);
    }
}
%end

// ==========================
// TGModernConversationInputController hook
// ==========================
%hook TGModernConversationInputController

- (void)sendCurrentMessage {
    id message = nil;
    @try { message = [self currentMessageObject]; } @catch (...) { message = nil; }

    BOOL autoScheduled = [[NSUserDefaults standardUserDefaults] boolForKey:kEnableScheduledMessages];
    if (!message || !autoScheduled) {
        %orig;
        return;
    }

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval scheduledTime = now + 10.0; // ritardo di test

    @try {
        [message setValue:@(scheduledTime) forKey:@"scheduleDate"];
        int32_t flags = [[message valueForKey:@"flags"] intValue];
        flags |= (1 << 10); // abilita scheduling
        [message setValue:@(flags) forKey:@"flags"];
    } @catch (...) {}

    // Crea attributo di scheduling se esiste la classe
    NSArray *candidateNames = @[@"OutgoingScheduleInfoMessageAttribute",
                                @"_TtC12TelegramCore36OutgoingScheduleInfoMessageAttribute",
                                @"TelegramCoreOutgoingScheduleInfoMessageAttribute"];
    Class attrClass = nil;
    for (NSString *n in candidateNames) {
        attrClass = NSClassFromString(n);
        if (attrClass) break;
    }
    if (attrClass) {
        @try {
            id attr = [[attrClass alloc] init];
            @try { [attr setValue:@(scheduledTime) forKey:@"scheduleTime"]; } @catch (...) {}
            NSMutableArray *attrs = nil;
            @try { attrs = [NSMutableArray arrayWithArray:[message valueForKey:@"attributes"]]; } @catch (...) { attrs = [NSMutableArray array]; }
            [attrs addObject:attr];
            @try { [message setValue:attrs forKey:@"attributes"]; } @catch (...) {}
        } @catch (...) {}
    }

    // Debug
    TGExtra_appendDebug([NSString stringWithFormat:@"Scheduled message at %.0f, class=%s\n", now, object_getClassName(message)]);

    // Chiama funzione nativa
    if ([self respondsToSelector:@selector(sendMessage:scheduleTime:)]) {
        @try { [self sendMessage:message scheduleTime:scheduledTime]; } @catch (...) {}
        return; // evita duplicati
    }

    %orig;
}
%end

// ==========================
// TGMediaPickerSendActionSheetController hook
// ==========================
%hook TGMediaPickerSendActionSheetController
- (void)schedulePressed {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *logPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/tg_schedule_debug.txt"];
        NSError *err = nil;
        NSString *content = [NSString stringWithContentsOfFile:logPath encoding:NSUTF8StringEncoding error:&err];
        if (!content) content = [NSString stringWithFormat:@"No debug file or empty. err=%@", err];
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"TGExtra Debug Log"
                                                                   message:content
                                                            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        UIViewController *vc = [UIApplication sharedApplication].keyWindow.rootViewController;
        while (vc.presentedViewController) vc = vc.presentedViewController;
        [vc presentViewController:a animated:YES completion:nil];
    });
    %orig;
}
%end
