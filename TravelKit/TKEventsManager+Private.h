//
//  TKEventsManager+Private.h
//  TravelKit
//
//  Created by Michal Zelinka on 23/01/2018.
//  Copyright © 2018 Tripomatic. All rights reserved.
//

#import "TKEventsManager.h"

NS_ASSUME_NONNULL_BEGIN

@interface TKEventsManager ()

@property (nonatomic, copy, nullable) void (^expiredSessionCredentialsHandler)(void);

@end

NS_ASSUME_NONNULL_END