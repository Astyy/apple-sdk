//
//  TKSessionManager.h
//  TravelKit
//
//  Created by Michal Zelinka on 29/06/17.
//  Copyright © 2017 Tripomatic. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <TravelKit/TKSession.h>

NS_ASSUME_NONNULL_BEGIN

@interface TKSessionManager : NSObject

/// Shared Session managing instance.
@property (class, readonly, strong) TKSessionManager *sharedManager;

+ (instancetype)new  UNAVAILABLE_ATTRIBUTE;
- (instancetype)init UNAVAILABLE_ATTRIBUTE;

@property (nonatomic, strong, nullable, readonly) TKSession *session;

///---------------------------------------------------------------------------------------
/// @name Generic methods
///---------------------------------------------------------------------------------------

/**
 Clears all cached and persisting user data.
 */
- (void)clearUserData;

///---------------------------------------------------------------------------------------
/// @name Authentication
///---------------------------------------------------------------------------------------

/// :nodoc:

- (void)performDeviceSessionFetchWithSuccess:(void (^)(TKSession *))success
    failure:(void (^)(NSError *))failure;

- (void)performUserCredentialsAuthWithUsername:(NSString *)username password:(NSString *)password
    success:(void (^)(TKSession *))success failure:(void (^)(NSError *))failure;

- (void)performUserSocialAuthWithFacebookAccessToken:(NSString *)facebookAccessToken
    success:(void (^)(TKSession *))success failure:(void (^)(NSError *))failure;

- (void)performUserSocialAuthWithGoogleIDToken:(NSString *)googleIDToken
    success:(void (^)(TKSession *))success failure:(void (^)(NSError *))failure;

- (void)performJWTAuthWithToken:(NSString *)jwtToken
    success:(void (^)(TKSession *))success failure:(void (^)(NSError *))failure;

- (void)performMagicLinkAuthWithToken:(NSString *)magicToken
    success:(void (^)(TKSession *))success failure:(void (^)(NSError *))failure;

- (void)performUserRegisterWithToken:(NSString *)accessToken
  fullName:(NSString *)fullName email:(NSString *)email password:(NSString *)password
    success:(void (^)(void))success failure:(void (^)(NSError *))failure;

- (void)performUserResetPasswordWithToken:(NSString *)accessToken email:(NSString *)email
    success:(void (^)(void))success failure:(void (^)(NSError *))failure;

- (void)performMagicLinkeFetchWithToken:(NSString *)accessToken
	success:(void (^)(NSString *magicLinkToken))success failure:(void (^)(NSError *))failure;

- (void)performSignOutWithCompletion:(void (^)(void))completion;

@end

NS_ASSUME_NONNULL_END
