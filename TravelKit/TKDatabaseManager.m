//
//  TKDatabaseManager.m
//  TravelKit
//
//  Created by Michal Zelinka on 9/7/2014.
//  Copyright (c) 2014 Tripomatic. All rights reserved.
//

#import "TKDatabaseManager+Private.h"

#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"
#import "FMDatabaseQueue.h"

#import "NSObject+Parsing.h"

#define NSStringMultiline(...) @#__VA_ARGS__


// Database path
NSString * const kDatabaseFilename = @"database.sqlite";

// Database scheme
NSUInteger const kDatabaseSchemeVersionLatest = 20170621;

// Table names // ABI-EXPORTED
NSString * const kDatabaseTablePlaces = @"places";
NSString * const kDatabaseTablePlaceDetails = @"place_details";
NSString * const kDatabaseTablePlaceParents = @"place_parents";
NSString * const kDatabaseTableMedia = @"media";
NSString * const kDatabaseTableReferences = @"references";
NSString * const kDatabaseTableFavorites = @"favorites";


#pragma mark Private category


@interface TKDatabaseManager ()

@property (nonatomic) NSUInteger databaseVersion;

@property (atomic) BOOL databaseCreatedRecently;
@property (nonatomic, strong) FMDatabaseQueue *databaseQueue;

@end


#pragma mark -
#pragma mark Implementation


@implementation TKDatabaseManager

+ (TKDatabaseManager *)sharedInstance
{
    static dispatch_once_t once = 0;
    static TKDatabaseManager *shared = nil;
    dispatch_once(&once, ^{ shared = [[self alloc] init]; });
    return shared;
}

+ (NSString *)databasePath
{
	static NSString *path = nil;

	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{

		path = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];

#if TARGET_OS_MAC
		NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
		if (!bundleID) @throw @"Database initialization error";
		path = [path stringByAppendingPathComponent:bundleID];
#endif

		path = [path stringByAppendingPathComponent:@"TravelKit"];
		path = [path stringByAppendingPathComponent:kDatabaseFilename];
	});

	return path;
}

- (instancetype)init
{
	if (self = [super init])
	{
		if (![self isMemberOfClass:[TKDatabaseManager class]])
			@throw @"TKDatabaseManager class cannot be inherited";

		[self initializeDatabase];
	}

	return self;
}

- (void)initializeDatabase
{
	@synchronized (self) {

		if (!_databaseQueue) {

			NSFileManager *fm = [NSFileManager defaultManager];

			// Prepare paths
			NSString *databasePath = [TKDatabaseManager databasePath];
			NSString *databaseDir = [databasePath stringByDeletingLastPathComponent];

			// Check for DB existance
			BOOL exists = [fm fileExistsAtPath:databasePath];

			if (!exists && ![fm fileExistsAtPath:databaseDir isDirectory:nil])
				if (![fm createDirectoryAtPath:databaseDir withIntermediateDirectories:YES attributes:nil error:nil])
					@throw @"Database initialization error";

			if (!exists) [fm createFileAtPath:databasePath contents:nil attributes:nil];

			// Initialize DB accessor on the file
			_databaseQueue = [FMDatabaseQueue databaseQueueWithPath:databasePath];

			// Try to handle some basic error cases
			if (!_databaseQueue && exists)
			{
				[fm removeItemAtPath:databasePath error:nil];
				_databaseQueue = [FMDatabaseQueue databaseQueueWithPath:databasePath];
			}

			// Throw on error
			if (!_databaseQueue) @throw @"Database initialization error";

			// Check consistency
			[self checkConsistency];
		}
	}
}


#pragma mark -
#pragma mark Version checking


- (NSUInteger)databaseVersion
{
	return [[[[self runQuery:@"PRAGMA user_version;"] lastObject]
		[@"user_version"] parsedNumber] unsignedIntegerValue];
}

- (void)setDatabaseVersion:(NSUInteger)databaseVersion
{
	NSString *userVersionQuery = [NSString stringWithFormat:
		@"PRAGMA user_version = %tu;", databaseVersion];
	[self runQuery:userVersionQuery tableName:nil data:nil];
}


#pragma mark -
#pragma mark Migrations


- (void)checkConsistency
{
	//////////////////////////////////
	// Set journal mode

	[self runQuery:@"PRAGMA journal_mode = 'TRUNCATE';" tableName:nil data:nil];

	//////////////////////////////////
	// Check Database scheme

	[self checkScheme];

	//////////////////////////////////
	// Check Database indexes

	[self checkIndexes];
}

- (void)checkIndexes
{
	// Drop obsolete redundant indexes
//	[self runUpdate:@"DROP INDEX IF EXISTS ...;"];

	// Create smart indexes as required
//	[self runUpdate:@"CREATE INDEX IF NOT EXISTS index_name ON %@ (quadkey ASC);"
//		  tableName:... data:nil];

//		NSString *sql = NSStringMultiline(
//
//CREATE INDEX IF NOT EXISTS medium_type ON "medium" ("type" ASC);
//
//CREATE INDEX IF NOT EXISTS medium_place_id ON "medium" ("place_id" ASC);
//
//CREATE INDEX IF NOT EXISTS place_rating ON "place" ("rating" DESC);
//
//CREATE INDEX IF NOT EXISTS place_quadkey ON "place" ("quadkey" ASC);
//
//CREATE INDEX IF NOT EXISTS place_categories ON "place" ("categories" ASC);
//
//CREATE INDEX IF NOT EXISTS place_parents_parent_id ON "place_parents" ("parent_id" ASC);
//
//CREATE INDEX IF NOT EXISTS place_parents_place_id ON "place_parents" ("place_id" ASC);
//
//CREATE INDEX IF NOT EXISTS reference_place_id ON "reference" ("place_id" ASC);
//
//		);
//
//		for (NSString *query in [sql componentsSeparatedByString:@";"])
//			if (query.length > 5)
//				[self runUpdate:query];
}

- (void)checkScheme
{
	//////////////////////////////////
	// Read current Database scheme & determine state

	NSUInteger currentScheme = [self databaseVersion];

	//////////////////////////////////
	// Check Database scheme version

	if (currentScheme == kDatabaseSchemeVersionLatest)
		return;

	//////////////
	// Perform migration rules

	// Favorites
	if (currentScheme < 20170621) {
		[self runUpdate:@"CREATE TABLE IF NOT EXISTS %@ "
			"(id text PRIMARY KEY NOT NULL);" tableName:kDatabaseTableFavorites];
	}

	//////////////
	// Update version pragma

	self.databaseVersion = kDatabaseSchemeVersionLatest;
}


#pragma mark -
#pragma mark Database methods


- (NSArray *)runQuery:(NSString *const)query
{
	return [self runQuery:query tableName:nil data:nil];
}

- (NSArray *)runQuery:(NSString *const)query tableName:(NSString *const)tableName
{
	return [self runQuery:query tableName:tableName data:nil];
}

- (NSArray *)runQuery:(NSString *const)query tableName:(NSString *const)tableName data:(NSArray *const)data
{
	// Fill in a table name
	NSString *workingQuery = [NSString stringWithFormat:query, tableName];

#ifdef LOG_SQL
	NSLog(@"[SQL] Query: '%@'  Data: %@", workingQuery, data);
#endif

	__block NSMutableArray *results = [NSMutableArray array];
	__block NSError *error = nil;

	[_databaseQueue inDatabase:^(FMDatabase *database){

		@autoreleasepool {

			FMResultSet *resultSet = [database executeQuery:workingQuery withArgumentsInArray:data];

			if ([database hadError]) {
				error = database.lastError;
				NSLog(@"[DATABASE] Error when executing query %@: %@", workingQuery, error);
				return;
			}

			while ([resultSet next])
				[results addObject:resultSet.resultDictionary];

			[resultSet close];
			resultSet = nil;

		}

	}];

	return results;
}

- (BOOL)runUpdate:(NSString *const)query
{
	return [self runUpdate:query tableName:nil data:nil];
}

- (BOOL)runUpdate:(NSString *const)query tableName:(NSString *const)tableName
{
	return [self runUpdate:query tableName:tableName data:nil];
}

- (BOOL)runUpdate:(NSString *const)query tableName:(NSString *const)tableName data:(NSArray *const)data
{

	// Fill in a table name
	NSString *workingQuery = [NSString stringWithFormat:query, tableName];

#ifdef LOG_SQL
	NSLog(@"[SQL] %@ with %@", workingQuery, data);
#endif

	__block BOOL isUpdateOk = YES;
	__block NSError *error = nil;
	__block int changes = 0;

	[_databaseQueue inDatabase:^(FMDatabase *database){

		isUpdateOk = [database executeUpdate:workingQuery withArgumentsInArray:data];
		if ([database hadError]) error = database.lastError;
		changes = database.changes;

	}];

	if (error) @throw @"Database update error";

	return isUpdateOk;
}

- (BOOL)runUpdateTransactionWithQueries:(NSArray *const)queries dataArray:(NSArray *const)dataArray
{
	__block BOOL isUpdateOk = YES;
	__block NSError *error = nil;

	[_databaseQueue inTransaction:^(FMDatabase *database, BOOL *rollback){

		NSUInteger index = 0;

		for (NSString *query in queries)
		{
			if (index >= dataArray.count)
				continue;

			NSArray *data = dataArray[index];

			isUpdateOk = [database executeUpdate:query withArgumentsInArray:data];

			if ([database hadError]) {
				error = database.lastError;
				NSLog(@"[DATABASE] Error when updating DB with query %@: %@", query, error);
				*rollback = YES;
				break;
			}

			index++;
		}

	}];

	return isUpdateOk;
}

- (BOOL)checkExistenceOfColumn:(NSString *)columnName inTable:(NSString *)tableName
{
	__block BOOL exists = NO;

	[_databaseQueue inDatabase:^(FMDatabase *database){
		exists = [database columnExists:columnName inTableWithName:tableName];
	}];

	return exists;
}

@end
