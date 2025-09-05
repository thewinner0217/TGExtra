#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "Headers.h"

// Dichiarazione corretta della classe
@interface TGModernConversationInputController : NSObject
- (id)currentMessageObject;
- (void)sendMessage:(id)message scheduleTime:(NSTimeInterval)time;
@end

#define kChannelsReadHistory -871347913
#define kEnableScheduledMessages @"enableScheduledMessages"

#pragma mark - MTRequest Hook
%hook MTRequest
%property (nonatomic, strong) NSData *fakeData;
%property (nonatomic, strong) NSNumber *functionID;

- (void)setPayload:(NSData *)payload metadata:(id)metadata shortMetadata:(id)shortMetadata responseParser:(id (^)(NSData *))responseParser {

    int32_t functionID;
    [payload getBytes:&functionID length:4];
    self.functionID = [NSNumber numberWithInt:functionID];

    id(^hooked_block)(NSData *) = ^(NSData *inputData) {
        NSNumber *functionIDNumber = [NSNumber numberWithUnsignedInt:functionID];
        NSData *processed = [TLParser handleResponse:inputData functionID:functionIDNumber];
        if (processed) {
            return responseParser(processed);
        } else {
            return responseParser(inputData);
        }
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

#pragma mark - MTRequestMessageService Hook
%hook MTRequestMessageService

- (void)addRequest:(MTRequest *)request {
    if (request.fakeData) {
        @try {
            if (request.completed) {
                NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
                MTRequestResponseInfo *info = [[%c(MTRequestResponseInfo) alloc] initWithNetworkType:1
                                                                                             timestamp:currentTime
                                                                                              duration:0.045];
                id result = request.responseParser(request.fakeData);
                request.completed(result, info, nil);
            }
        } @catch (NSException *exception) {
            customLog2(@"Exception in MTRequestMessageService hook: %@", exception);
        }
        return;
    }
    %orig;
}

%end

#pragma mark - TGModernConversationInputController Hook
%hook TGModernConversationInputController

- (void)sendCurrentMessage {
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    BOOL autoScheduled = [prefs boolForKey:kEnableScheduledMessages];

    id message = [self currentMessageObject];

    if (autoScheduled && message) {
        NSTimeInterval delay = 12; // default per testo/emoji/sticker
        NSString *messageType = @"text/emoji/sticker";
        unsigned long fileSize = 0;

        // Se contiene media, calcolo delay dinamico
        NSArray *mediaItems = [message valueForKey:@"media"];
        if (mediaItems && mediaItems.count > 0) {
            id media = mediaItems.firstObject;
            NSData *data = [media valueForKey:@"data"];
            if (data) {
                fileSize = data.length;
                delay = MAX(6, ceil((double)fileSize / 1048576.0 * 4.5));
                messageType = @"media";
            }
        }

        NSTimeInterval scheduledTime = [[NSDate date] timeIntervalSince1970] + delay;

        // Crea attributo di scheduling
        Class OutgoingScheduleInfoMessageAttribute = NSClassFromString(@"OutgoingScheduleInfoMessageAttribute");
        if (OutgoingScheduleInfoMessageAttribute) {
            id scheduleAttribute = [OutgoingScheduleInfoMessageAttribute new];
            [scheduleAttribute setValue:@(scheduledTime) forKey:@"scheduleTime"];

            NSArray *existingAttributes = [message valueForKey:@"attributes"];
            NSMutableArray *newAttributes = [NSMutableArray arrayWithArray:existingAttributes];
            [newAttributes addObject:scheduleAttribute];
            [message setValue:newAttributes forKey:@"attributes"];
        }

        // --- LOG DETTAGLIATO ---
NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
NSString *documentsDirectory = paths.firstObject;
NSString *logPath = [documentsDirectory stringByAppendingPathComponent:@"tg_schedule_log.txt"];

NSString *msgDesc = [NSString stringWithFormat:@"MessageType: %@, ScheduledTime: %.0f, Delay: %.2f, FileSize: %lu\n",
                     messageType, scheduledTime, delay, fileSize];
NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:logPath];
if (!file) {
    [msgDesc writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
} else {
    [file seekToEndOfFile];
    [file writeData:[msgDesc dataUsingEncoding:NSUTF8StringEncoding]];
    [file closeFile];
}

        // --- INVIO DEL MESSAGGIO CON TRY/CATCH ---
        @try {
            [self sendMessage:message scheduleTime:scheduledTime];
            // Log conferma invio
            NSString *successLog = [NSString stringWithFormat:@"sendMessage: scheduled successfully\n"];
            NSFileHandle *f = [NSFileHandle fileHandleForWritingAtPath:logPath];
            if (f) {
                [f seekToEndOfFile];
                [f writeData:[successLog dataUsingEncoding:NSUTF8StringEncoding]];
                [f closeFile];
            }
        }
        @catch (NSException *exception) {
            NSString *errorLog = [NSString stringWithFormat:@"sendMessage ERROR: %@\n", exception];
            NSFileHandle *f = [NSFileHandle fileHandleForWritingAtPath:logPath];
            if (f) {
                [f seekToEndOfFile];
                [f writeData:[errorLog dataUsingEncoding:NSUTF8StringEncoding]];
                [f closeFile];
            }
        }

        return;
    }

    %orig;
}

%end

#pragma mark - MTRequest initWithFunction Hook per scheduling universale
%hook MTRequest

- (instancetype)initWithFunction:(id)function {
    self = %orig;
    if (self) {
        BOOL autoScheduled = [[NSUserDefaults standardUserDefaults] boolForKey:kEnableScheduledMessages];
        if (autoScheduled && function) {
            @try {
                NSString *className = NSStringFromClass([function class]);
                int32_t baseTime = (int32_t)([[NSDate date] timeIntervalSince1970]);
                int delay = 12; // default

                if ([className containsString:@"sendMedia"] ||
                    [className containsString:@"sendMultiMedia"] ||
                    [className containsString:@"sendInlineBotResult"]) {

                    NSNumber *size = nil;

                    // Media singolo
                    @try { size = [function valueForKeyPath:@"media.file.size"]; } @catch (...) {}

                    // Media multiplo
                    if (!size) {
                        @try {
                            NSArray *mediaArray = [function valueForKey:@"media"];
                            double totalSize = 0;
                            for (id media in mediaArray) {
                                @try {
                                    totalSize += [[media valueForKeyPath:@"file.size"] doubleValue];
                                } @catch (...) {}
                            }
                            size = @(totalSize);
                        } @catch (...) {}
                    }

                    if (size) {
                        double mbSize = [size doubleValue] / 1048576.0;
                        delay = (int)ceil(mbSize * 4.5);
                        if (delay < 6) delay = 6;
                    }
                }

                int32_t scheduleDate = baseTime + delay;
                [function setValue:@(scheduleDate) forKey:@"scheduleDate"];

                int32_t flags = [[function valueForKey:@"flags"] intValue];
                flags |= (1 << 10); // abilita scheduleDate
                [function setValue:@(flags) forKey:@"flags"];

                NSLog(@"[TGExtra] %@ programmato a +%ds", className, delay);

            } @catch (NSException *e) {
                NSLog(@"[TGExtra] Schedule patch failed: %@", e);
            }
        }
    }
    return self;
}

%end
