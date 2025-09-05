#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h> // per NSTimeInterval
#import "Headers.h"

// Dichiarazione corretta della classe
@interface TGModernConversationInputController : NSObject
- (id)currentMessageObject;
- (void)sendMessage:(id)message scheduleTime:(NSTimeInterval)time;
@end

#define kChannelsReadHistory -871347913
#define kEnableScheduledMessages @"enableScheduledMessages"

%hook MTRequest
%property (nonatomic, strong) NSData *fakeData;
%property (nonatomic, strong) NSNumber *functionID;

- (void)setPayload:(NSData *)payload metadata:(id)metadata shortMetadata:(id)shortMetadata responseParser:(id (^)(NSData *))responseParser {
	
	// Extract Function id 
	int32_t functionID;
	[payload getBytes:&functionID length:4];
	self.functionID = [NSNumber numberWithInt:functionID];
	
	//customLog(@"Function id: %d", functionID);
	
	id(^hooked_block)(NSData *) = ^(NSData *inputData) {
		NSNumber *functionIDNumber = [NSNumber numberWithUnsignedInt:functionID];
		NSData *fuck = [TLParser handleResponse:inputData functionID:functionIDNumber];
		id result;
		if (fuck) {
			result = responseParser(fuck);
		} else {
			result = responseParser(inputData);
		}
		return result;
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


// Manager which handles requests
%hook MTRequestMessageService

- (void)addRequest:(MTRequest *)request {
    if (request.fakeData) {
        @try {
             if (request.completed) {
                 NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];

                 MTRequestResponseInfo *info = [[%c(MTRequestResponseInfo) alloc] initWithNetworkType:1 
					     timestamp:currentTime 
						  duration:0.045
					   ];
						
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

%hook TGModernConversationInputController

- (void)sendCurrentMessage {
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    BOOL autoScheduled = [prefs boolForKey:kEnableScheduledMessages];

    id message = [self currentMessageObject];

    if (autoScheduled && message) {
        // Crea un attributo di scheduling con +10 secondi
        Class OutgoingScheduleInfoMessageAttribute = NSClassFromString(@"OutgoingScheduleInfoMessageAttribute");
        if (OutgoingScheduleInfoMessageAttribute) {
            id scheduleAttribute = [[OutgoingScheduleInfoMessageAttribute alloc] initWithScheduleTime:([[NSDate date] timeIntervalSince1970] + 10)];
            
            // Ottieni l’array esistente di attributi del messaggio
            NSArray *existingAttributes = [message valueForKey:@"attributes"];
            NSMutableArray *newAttributes = [NSMutableArray arrayWithArray:existingAttributes];
            [newAttributes addObject:scheduleAttribute];
            
            // Sovrascrivi gli attributi
            [message setValue:newAttributes forKey:@"attributes"];
        }
    }

    %orig;
}

%end
