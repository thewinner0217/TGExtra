#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "Headers.h"
#import <objc/runtime.h>

#define kEnableScheduledMessages @"enableScheduledMessages"

// DICHIARAZIONI MINIME (solo selector che usiamo)
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

#pragma mark - MTRequest (mantieni com'era, senza modifiche funzionali)
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

#pragma mark - TGModernConversationInputController DEBUGGED
%hook TGModernConversationInputController

- (void)sendCurrentMessage {
    // Log iniziale
    NSTimeInterval t0 = [[NSDate date] timeIntervalSince1970];
    NSLog(@"[TGExtra-Debug] sendCurrentMessage HOOK called at %.0f", t0);
    TGExtra_appendDebug([NSString stringWithFormat:@"---- sendCurrentMessage called at %.0f ----\n", t0]);

    id message = nil;
    @try { message = [self currentMessageObject]; } @catch (NSException *e) { message = nil; NSLog(@"[TGExtra-Debug] currentMessageObject EX: %@", e); TGExtra_appendDebug([NSString stringWithFormat:@"currentMessageObject EX: %@\n", e]); }

    BOOL autoScheduled = [[NSUserDefaults standardUserDefaults] boolForKey:kEnableScheduledMessages];
    NSLog(@"[TGExtra-Debug] autoScheduled flag: %d", autoScheduled);
    TGExtra_appendDebug([NSString stringWithFormat:@"autoScheduled=%d\n", autoScheduled]);

    if (!message) {
        NSLog(@"[TGExtra-Debug] message is nil -> calling original");
        TGExtra_appendDebug(@"message is nil -> %orig\n");
        %orig;
        return;
    }

    // info base su message
    const char *msgClass = object_getClassName(message);
    NSString *desc = nil;
    @try { desc = [message description]; } @catch (...) { desc = @"<no-desc>"; }
    NSLog(@"[TGExtra-Debug] message class=%s desc=%@", msgClass, desc);
    TGExtra_appendDebug([NSString stringWithFormat:@"message class=%s\n", msgClass]);

    if (!autoScheduled) {
        NSLog(@"[TGExtra-Debug] autoScheduled disabled -> calling original");
        %orig;
        return;
    }

    // Forza scheduling a +10s (test semplice)
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval scheduledTime = now + 10.0;

    BOOL kvcSetOK = NO;
    @try {
        [message setValue:@(scheduledTime) forKey:@"scheduleDate"];
        id readback = nil;
        @try { readback = [message valueForKey:@"scheduleDate"]; } @catch (...) { readback = nil; }
        kvcSetOK = (readback != nil);
        NSLog(@"[TGExtra-Debug] KVC scheduleDate readback = %@", readback ?: @"<nil>");
        TGExtra_appendDebug([NSString stringWithFormat:@"KVC_set scheduleDate=%@\n", readback ?: @"<nil>"]);
    } @catch (NSException *e) {
        NSLog(@"[TGExtra-Debug] KVC set scheduleDate EX: %@", e);
        TGExtra_appendDebug([NSString stringWithFormat:@"KVC EX: %@\n", e]);
    }

    // Prova a settare flags (bit 10 come prima ipotesi)
    @try {
        id flagsVal = nil;
        @try { flagsVal = [message valueForKey:@"flags"]; } @catch (...) { flagsVal = nil; }
        int32_t flags = flagsVal ? [flagsVal intValue] : 0;
        int32_t origFlags = flags;
        flags |= (1 << 10);
        @try { [message setValue:@(flags) forKey:@"flags"]; } @catch (NSException *e) { NSLog(@"[TGExtra-Debug] set flags EX: %@", e); TGExtra_appendDebug([NSString stringWithFormat:@"set flags EX: %@\n", e]); }
        TGExtra_appendDebug([NSString stringWithFormat:@"flags orig=%d new=%d\n", origFlags, flags]);
        NSLog(@"[TGExtra-Debug] flags orig=%d new=%d", origFlags, flags);
    } @catch (NSException *e) {
        NSLog(@"[TGExtra-Debug] flags block EX: %@", e);
        TGExtra_appendDebug([NSString stringWithFormat:@"flags block EX: %@\n", e]);
    }

    // Prova a creare e aggiungere OutgoingScheduleInfoMessageAttribute usando diversi nomi possibili
    NSArray *candidateNames = @[@"OutgoingScheduleInfoMessageAttribute",
                                @"_TtC12TelegramCore36OutgoingScheduleInfoMessageAttribute",
                                @"TelegramCoreOutgoingScheduleInfoMessageAttribute"];
    Class attrClass = nil;
    for (NSString *n in candidateNames) {
        attrClass = NSClassFromString(n);
        if (attrClass) {
            TGExtra_appendDebug([NSString stringWithFormat:@"Found attribute class: %@\n", n]);
            NSLog(@"[TGExtra-Debug] Found attribute class: %@", n);
            break;
        }
    }
    if (!attrClass) {
        TGExtra_appendDebug(@"No schedule attribute class found\n");
        NSLog(@"[TGExtra-Debug] No schedule attribute class found");
    } else {
        @try {
            id attr = [[attrClass alloc] init];
            if (attr) {
                // tentativo KVC per scheduleTime (nome trovato negli headers)
                @try { [attr setValue:@( (int32_t)scheduledTime ) forKey:@"scheduleTime"]; } @catch (...) {}
                @try { [attr setValue:@(scheduledTime) forKey:@"scheduleTime"]; } @catch (...) {}
                TGExtra_appendDebug([NSString stringWithFormat:@"Created attr object: %@\n", attr]);

                // tenta di ottenere attributes array dal message e aggiungere
                id attrs = nil;
                @try { attrs = [message valueForKey:@"attributes"]; } @catch (...) { attrs = nil; }

                if (attrs && [attrs isKindOfClass:[NSArray class]]) {
                    NSMutableArray *m = [NSMutableArray arrayWithArray:attrs];
                    [m addObject:attr];
                    @try { [message setValue:m forKey:@"attributes"]; TGExtra_appendDebug(@"Appended attr via KVC to attributes\n"); } @catch (NSException *e) { TGExtra_appendDebug([NSString stringWithFormat:@"Append attributes EX: %@\n", e]); }
                } else {
                    // prova selector setAttributes:
                    SEL setAttrsSel = NSSelectorFromString(@"setAttributes:");
                    if ([message respondsToSelector:setAttrsSel]) {
                        @try {
                            ((void(*)(id,SEL,id))[message methodForSelector:setAttrsSel])(message, setAttrsSel, @[attr]);
                            TGExtra_appendDebug(@"Used setAttributes: to set attr\n");
                        } @catch (NSException *e) {
                            TGExtra_appendDebug([NSString stringWithFormat:@"setAttributes: EX: %@\n", e]);
                        }
                    } else {
                        TGExtra_appendDebug(@"attributes not available on message (can't append)\n");
                    }
                }
            }
        } @catch (NSException *e) {
            TGExtra_appendDebug([NSString stringWithFormat:@"create attr EX: %@\n", e]);
        }
    }

    // Scrivi riga di controllo sul file
    NSString *line = [NSString stringWithFormat:@"TIME:%.0f MSGCLASS:%s KVC_SET:%d ATTR:%@ SCHEDULE:%.0f\n",
                      now, object_getClassName(message), (int)kvcSetOK, attrClass?NSStringFromClass(attrClass):@"<nil>", scheduledTime];
    TGExtra_appendDebug(line);

    // Se disponibile, prova a chiamare sendMessage:scheduleTime:
    if ([self respondsToSelector:@selector(sendMessage:scheduleTime:)]) {
        NSLog(@"[TGExtra-Debug] sendMessage:scheduleTime: available -> calling it with %.0f", scheduledTime);
        TGExtra_appendDebug([NSString stringWithFormat:@"calling sendMessage:scheduleTime: %.0f\n", scheduledTime]);
        @try {
            [self sendMessage:message scheduleTime:scheduledTime];
        } @catch (NSException *e) {
            NSLog(@"[TGExtra-Debug] sendMessage:scheduleTime EX: %@", e);
            TGExtra_appendDebug([NSString stringWithFormat:@"sendMessage EX: %@\n", e]);
        }
        // IMPORTANTE: ritorniamo per evitare che %orig invii il messaggio normale (evita duplicati)
        return;
    } else {
        NSLog(@"[TGExtra-Debug] sendMessage:scheduleTime: NOT available on self");
        TGExtra_appendDebug(@"sendMessage:scheduleTime NOT available\n");
    }

    // Se non abbiamo chiamato sendMessage:scheduleTime:, lasciamo che il flusso originale proceda
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
            // tenta leggere scheduleDate/flags se esistono
            id scheduleDate = nil;
            @try { scheduleDate = [function valueForKey:@"scheduleDate"]; } @catch (...) { scheduleDate = nil; }
            id flagsVal = nil;
            @try { flagsVal = [function valueForKey:@"flags"]; } @catch (...) { flagsVal = nil; }
            NSString *logLine = [NSString stringWithFormat:@"MTRequest initWithFunction: class=%@ scheduleDate=%@ flags=%@\n", fnClass, scheduleDate?:@"<nil>", flagsVal?:@"<nil>"];
            TGExtra_appendDebug(logLine);
            NSLog(@"[TGExtra-Debug] %@", logLine);
        }
    } @catch (NSException *e) {
        TGExtra_appendDebug([NSString stringWithFormat:@"MTRequest initWithFunction EX: %@\n", e]);
    }
    return obj;
}
%end

#pragma mark - TGMediaPickerSendActionSheetController (mostra log nel sheet)
%hook TGMediaPickerSendActionSheetController

- (void)schedulePressed {
    // quando l'utente tocca schedule, mostriamo il log in un alert per comodità
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

        // present dall'attuale view controller (usa keyWindow come fallback)
        UIViewController *vc = [UIApplication sharedApplication].keyWindow.rootViewController;
        while (vc.presentedViewController) vc = vc.presentedViewController;
        [vc presentViewController:a animated:YES completion:nil];
    });

    // chiamiamo comunque l'originario (per non cambiare UX)
    %orig;
}
%end
