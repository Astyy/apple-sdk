//
//  TKSessionManager.m
//  TravelKit
//
//  Created by Michal Zelinka on 29/06/17.
//  Copyright © 2017 Tripomatic. All rights reserved.
//

#import "TKSessionManager+Private.h"
#import "TKDatabaseManager+Private.h"
#import "TKUserSettings+Private.h"
#import "TKAPI+Private.h"
#import "TKSSOAPI+Private.h"

#import "Foundation+TravelKit.h"
#import "NSObject+Parsing.h"


@interface TKSessionManager ()

@property (nonatomic, strong) TKDatabaseManager *database;
@property (nonatomic, strong) TKUserSettings *settings;

@end


@implementation TKSessionManager

+ (TKSessionManager *)sharedSession
{
    static dispatch_once_t once = 0;
    static TKSessionManager *shared = nil;
    dispatch_once(&once, ^{ shared = [[self alloc] init]; });
    return shared;
}

- (instancetype)init
{
	if (self = [super init])
	{
		_database = [TKDatabaseManager sharedManager];
		_settings = [TKUserSettings sharedSettings];

		[self loadState];
	}

	return self;
}


#pragma mark -
#pragma mark Generic methods


- (void)loadState
{
	_credentials = [[TKUserCredentials alloc] initFromDictionary:_settings.userCredentials];

	[TKAPI sharedAPI].accessToken = _credentials.accessToken;
}

- (void)saveState
{
	_settings.userCredentials = [_credentials asDictionary];

	[_settings commit];
}

- (void)clearUserData
{
	// Clear Favorites
	[_database runQuery:@"DELETE FROM %@;" tableName:kDatabaseTableFavorites];

	// Reset User settings
	[[TKUserSettings sharedSettings] reset];

	// Reload Session state
	[self loadState];

	// Re-save new Session state
	[self saveState];
}


#pragma mark -
#pragma mark User Credentials


- (void)setCredentials:(TKUserCredentials *)credentials
{
	_credentials = credentials;

	[TKAPI sharedAPI].accessToken = _credentials.accessToken;

	[self saveState];
}


#pragma mark -
#pragma mark Authentication


- (void)performDeviceCredentialsFetchWithSuccess:(void (^)(TKUserCredentials *))success
    failure:(void (^)(NSError *))failure
{
	[[TKSSOAPI sharedAPI] performDeviceCredentialsFetchWithSuccess:^(TKUserCredentials *credentials) {

		self.credentials = credentials;

		if (success) success(credentials);

	} failure:failure];
}

- (void)performUserCredentialsAuthWithUsername:(NSString *)username password:(NSString *)password
    success:(void (^)(TKUserCredentials *))success failure:(void (^)(NSError *))failure
{
	[[TKSSOAPI sharedAPI] performUserCredentialsAuthWithUsername:username
	password:password success:^(TKUserCredentials *credentials) {

		self.credentials = credentials;

		if (success) success(credentials);

	} failure:failure];
}

- (void)performUserSocialAuthWithFacebookToken:(NSString *)facebookToken
	success:(void (^)(TKUserCredentials * _Nonnull))success failure:(void (^)(NSError * _Nonnull))failure
{
	[[TKSSOAPI sharedAPI] performUserSocialAuthWithFacebookToken:facebookToken
	googleToken:nil success:^(TKUserCredentials *credentials) {

		self.credentials = credentials;

		if (success) success(credentials);

	} failure:failure];
}

- (void)performUserSocialAuthWithGoogleToken:(NSString *)googleToken
	success:(void (^)(TKUserCredentials * _Nonnull))success failure:(void (^)(NSError * _Nonnull))failure
{
	[[TKSSOAPI sharedAPI] performUserSocialAuthWithFacebookToken:nil
	googleToken:googleToken success:^(TKUserCredentials *credentials) {

		self.credentials = credentials;

		if (success) success(credentials);

	} failure:failure];
}

- (void)performJWTAuthWithToken:(NSString *)jwtToken
	success:(void (^)(TKUserCredentials * _Nonnull))success failure:(void (^)(NSError * _Nonnull))failure
{
	[[TKSSOAPI sharedAPI] performJWTAuthWithToken:jwtToken success:^(TKUserCredentials *credentials) {

		self.credentials = credentials;

		if (success) success(credentials);

	} failure:failure];
}

- (void)performMagicLinkAuthWithToken:(NSString *)magicToken
    success:(void (^)(TKUserCredentials *))success failure:(void (^)(NSError *))failure
{
	[[TKSSOAPI sharedAPI] performMagicAuthWithMagicLink:magicToken success:^(TKUserCredentials *credentials) {

		self.credentials = credentials;

		if (success) success(credentials);

	} failure:failure];
}

- (void)performUserRegisterWithToken:(NSString *)accessToken
  fullName:(NSString *)fullName email:(NSString *)email password:(NSString *)password
    success:(void (^)(void))success failure:(void (^)(NSError *))failure
{
	[[TKSSOAPI sharedAPI] performUserRegisterWithToken:accessToken
		fullName:fullName email:email password:password success:success failure:failure];
}

- (void)performUserResetPasswordWithToken:(NSString *)accessToken email:(NSString *)email
	success:(void (^)(void))success failure:(void (^)(NSError * _Nonnull))failure
{
	[[TKSSOAPI sharedAPI] performUserResetPasswordWithToken:accessToken
		email:email success:success failure:failure];
}

- (void)performMagicLinkeFetchWithToken:(NSString *)accessToken
	success:(void (^)(NSString *magicLinkToken))success failure:(void (^)(NSError *))failure
{
	[[TKSSOAPI sharedAPI] performMagicLinkFetchWithToken:accessToken success:^(NSString *magicLink) {
		if (success && magicLink) success(magicLink);
		if (failure && !magicLink) failure([TKAPIError errorWithCode:87234 userInfo:nil]);
	} failure:^(TKAPIError *err) {
		if (failure) failure(err);
	}];
}

- (void)performSignOutWithCompletion:(void (^)(void))completion
{
	[self clearUserData];

	if (completion) completion();
}


#pragma mark -
#pragma mark Favorites


- (NSArray<NSString *> *)favoritePlaceIDs
{
	NSArray *results = [_database runQuery:
		@"SELECT id FROM %@ WHERE state >= 0;" tableName:kDatabaseTableFavorites];

	return [results mappedArrayUsingBlock:^NSString *(NSDictionary *res) {
		return [res[@"id"] parsedString];
	}];
}

- (void)updateFavoritePlaceID:(NSString *)favoriteID setFavorite:(BOOL)favorite
{
	if (!favoriteID) return;

	if (favorite)
		[_database runQuery:@"INSERT OR IGNORE INTO %@ VALUES (?, 1);"
			tableName:kDatabaseTableFavorites data:@[ favoriteID ]];
	else
		[_database runQuery:@"UPDATE %@ SET state = -1 WHERE id = ?;"
			tableName:kDatabaseTableFavorites data:@[ favoriteID ]];
}

- (NSDictionary<NSString *,NSNumber *> *)favoritePlaceIDsToSynchronize
{
	NSArray<NSDictionary *> *results = [_database runQuery:
		@"SELECT * FROM %@ WHERE state != 0;" tableName:kDatabaseTableFavorites];

	NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity:results.count];

	for (NSDictionary *f in results)
	{
		NSString *ID = [f[@"id"] parsedString];
		NSNumber *state = [f[@"state"] parsedNumber];

		if (!ID || ABS(state.integerValue) != 1) continue;

		dict[ID] = state;
	}

	return dict;
}

- (void)storeServerFavoriteIDsAdded:(NSArray<NSString *> *)addedIDs removed:(NSArray<NSString *> *)removedIDs
{
	NSString *(^joinIDs)(NSArray<NSString *> *) = ^NSString *(NSArray<NSString *> *arr) {
		if (!arr.count) return nil;
		return [NSString stringWithFormat:@"'%@'", [arr componentsJoinedByString:@"','"]];
	};

	NSString *addString = joinIDs(addedIDs);
	NSString *remString = joinIDs(removedIDs);

	if (addString) [_database runQuery:[NSString stringWithFormat:
		@"UPDATE %@ SET state = 0 WHERE id IN (%@);", kDatabaseTableFavorites, addString]];

	for (NSString *ID in addedIDs)
		[_database runQuery:@"INSERT OR IGNORE INTO %@ (id) VALUES (?);"
			tableName:kDatabaseTableFavorites data:@[ ID ]];

	if (remString) [_database runQuery:[NSString stringWithFormat:
		@"DELETE FROM %@ WHERE id IN (%@);", kDatabaseTableFavorites, remString]];
}

@end
