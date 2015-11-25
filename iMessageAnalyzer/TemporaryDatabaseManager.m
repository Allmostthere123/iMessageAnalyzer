//
//  TemporaryDatabaseManager.m
//  iMessageAnalyzer
//
//  Created by Ryan D'souza on 11/25/15.
//  Copyright © 2015 Ryan D'souza. All rights reserved.
//

#define MAX_DB_TRIES 40

#import "TemporaryDatabaseManager.h"

static NSString *myMessagesTable = @"myMessagesTable";
static NSString *otherMessagesTable = @"otherMessagesTable";

@interface TemporaryDatabaseManager ()

@property (strong, nonatomic) Person *person;
@property (strong, nonatomic) NSCalendar *calendar;
@property sqlite3 *database;

@end

@implementation TemporaryDatabaseManager

- (instancetype) initWithPerson:(Person *)person messages:(NSMutableArray *)messages {
    self = [super init];
    
    if(self) {
        self.person = person;
        
        self.calendar = [NSCalendar currentCalendar];
        [self.calendar setTimeZone:[NSTimeZone systemTimeZone]];
        
        //[self filePath]
        if(sqlite3_open("file::memory:", &_database) == SQLITE_OK) {
            printf("OPENED TEMPORARY DATABASE\n");
            
            [self createMyMessagesTable];
            [self createOtherMessagesTable];
            
            [self addMessagesToDatabase:messages];
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void) {
                [self addOtherMessagesToDatabase:[[DatabaseManager getInstance] getTemporaryInformationForAllConversationsExceptWith:person]];
            });
        }
        else {
            printf("ERROR OPENING TEMPORARY DATABASE: %s\n", sqlite3_errmsg(_database));
        }
    }
    
    return self;
}


/****************************************************************
 *
 *              INSERT MY MESSAGES
 *
*****************************************************************/

# pragma mark INSERT_MY_MESSAGES

- (NSString*) insertMessageQuery:(Message*)message
{
    int date = [message.dateSent timeIntervalSinceReferenceDate];
    int dateRead = message.dateRead ? [message.dateRead timeIntervalSinceReferenceDate] : 0;
    NSString *service = message.isIMessage ? @"iMessage" : @"SMS";
    int isFromMe = message.isFromMe ? 1 : 0;
    int cache_has_attachments = message.hasAttachment || message.attachments ? 1 : 0;
    int wordCount = (int)[message.messageText componentsSeparatedByString:@" "].count;
    NSString *text = [message.messageText stringByReplacingOccurrencesOfString:@"'" withString:@"''"];
    return [NSString stringWithFormat:@"INSERT INTO %@(ROWID, guid, text, handle_id, service, date, date_read, is_from_me, cache_has_attachments, wordCount) VALUES ('%d', '%@', '%@', '%d', '%@', '%d', '%d', '%d', '%d', '%d')", myMessagesTable, (int)message.messageId, message.messageGUID, text, (int) message.handleId, service, date, dateRead, isFromMe, cache_has_attachments, wordCount];
}

- (void) addMessagesToDatabase:(NSMutableArray*)messages
{
    char *errorMessage;
    
    sqlite3_exec(_database, "BEGIN TRANSACTION", NULL, NULL, &errorMessage);
    
    for(Message *message in messages) {
        NSString *query = [self insertMessageQuery:message];
        [self executeSQLStatement:[query UTF8String] errorMessage:errorMessage];
    }
    
    sqlite3_exec(_database, "COMMIT TRANSACTION", NULL, NULL, &errorMessage);
}


/****************************************************************
 *
 *              INSERT OTHER MESSAGES
 *
 *****************************************************************/

# pragma mark INSERT_OTHER_MESSAGES

- (void) addOtherMessagesToDatabase:(NSMutableArray*)otherMessages
{
    char *errorMessage;
    
    sqlite3_exec(_database, "BEGIN TRANSACTION", NULL, NULL, &errorMessage);
    
    for(NSDictionary *otherMessage in otherMessages) {
        NSString *query = [self insertOtherMessageQuery:otherMessage];
        [self executeSQLStatement:[query UTF8String] errorMessage:errorMessage];
    }
    
    sqlite3_exec(_database, "COMMIT TRANSACTION", NULL, NULL, &errorMessage);
}

- (NSString*) insertOtherMessageQuery:(NSDictionary*)otherMessage
{
    int rowID = [otherMessage[@"ROWID"] intValue];
    int date = [otherMessage[@"date"] intValue];
    int wordCount = [otherMessage[@"wordCount"] intValue];
    int isFromMe = [otherMessage[@"is_from_me"] intValue];
    int hasAttachment = [otherMessage[@"cache_has_attachments"] intValue];
    return [NSString stringWithFormat:@"INSERT INTO %@(ROWID, date, wordCount, is_from_me, cache_has_attachments) VALUES (%d, %d, %d, %d, %d)", otherMessagesTable, rowID, date, wordCount, isFromMe, hasAttachment];
}


/****************************************************************
 *
 *              GET MY MESSAGES
 *
 *****************************************************************/

# pragma mark GET_MY_MESSAGES

- (NSMutableArray*) getAllMessagesForPerson:(Person *)person onDay:(NSDate *)day
{
    long startTime = [self timeAtBeginningOfDayForDate:day];
    long endTime = [self timeAtEndOfDayForDate:day];
    return [self getAllMessagesForPerson:person startTimeInSeconds:startTime endTimeInSeconds:endTime];
}

- (NSMutableArray*) getAllMessagesForPerson:(Person *)person
{
    Statistics *statistics = [[Statistics alloc] init];
    
    NSMutableArray *allMessagesForChat = [self getAllMessagesForConversationFromTimeInSeconds:0 endTimeInSeconds:INT_MAX statistics:&statistics];
    person.statistics = statistics;
    
    [[MessageManager getInstance] updateMessagesWithAttachments:allMessagesForChat person:person];
    
    return allMessagesForChat;
}

- (NSMutableArray*) getAllMessagesForPerson:(Person *)person startTimeInSeconds:(long)startTimeInSeconds endTimeInSeconds:(long)endTimeInSeconds
{
    Statistics *secondaryStatistics = [[Statistics alloc] init];
    
    NSMutableArray *messages = [self getAllMessagesForConversationFromTimeInSeconds:startTimeInSeconds endTimeInSeconds:endTimeInSeconds statistics:&secondaryStatistics];
    person.secondaryStatistics = secondaryStatistics;
    
    [[MessageManager getInstance] updateMessagesWithAttachments:messages person:person];
    
    return messages;
}

- (NSMutableArray*) getAllMessagesForConversationFromTimeInSeconds:(long)startTimeInSeconds endTimeInSeconds:(long)endTimeInSeconds statistics:(Statistics**)statisticsPointer
{
    NSMutableArray *allMessagesForChat = [[NSMutableArray alloc] init];
    
    if(*statisticsPointer == nil) {
        *statisticsPointer = [[Statistics alloc] init];
    }
    
    Statistics *statistics = *statisticsPointer;
    
    const char *query = [[NSString stringWithFormat:@"SELECT ROWID, guid, text, service, date, date_read, is_from_me, cache_has_attachments, handle_id FROM %@ WHERE (date > %ld AND date < %ld) ORDER BY date", myMessagesTable, startTimeInSeconds, endTimeInSeconds] UTF8String];
    
    sqlite3_stmt *statement;
    
    if(sqlite3_prepare_v2(_database, query, -1, &statement, NULL) == SQLITE_OK) {
        while(sqlite3_step(statement) == SQLITE_ROW) {
            int32_t messageID = sqlite3_column_int(statement, 0);
            NSString *guid = [NSString stringWithFormat:@"%s", sqlite3_column_text(statement, 1)];
            
            NSString *text = @"";
            if(sqlite3_column_text(statement, 2)) {
                text = [NSString stringWithUTF8String:sqlite3_column_text(statement, 2)];
                text = [text stringByReplacingOccurrencesOfString:@"''" withString:@"'"];
            }
            
            BOOL isIMessage = [self isIMessage:sqlite3_column_text(statement, 3)];
            int32_t dateInt = sqlite3_column_int(statement, 4);
            int32_t dateReadInt = sqlite3_column_int(statement, 5);
            
            BOOL isFromMe = sqlite3_column_int(statement, 6) == 1 ? YES : NO;
            BOOL hasAttachment = sqlite3_column_int(statement, 7) == 1 ? YES: NO;
            int32_t handleID = sqlite3_column_int(statement, 8);
            
            if(isFromMe) {
                statistics.numberOfSentMessages++;
                if(hasAttachment) {
                    statistics.numberOfSentAttachments++;
                }
            }
            else {
                statistics.numberOfReceivedMessages++;
                if(hasAttachment) {
                    statistics.numberOfReceivedAttachments++;
                }
            }
            
            NSDate *date = [NSDate dateWithTimeIntervalSinceReferenceDate:dateInt];
            NSDate *dateRead = dateReadInt == 0 ? nil : [NSDate dateWithTimeIntervalSinceReferenceDate:dateReadInt];
            
            Message *message = [[Message alloc] initWithMessageId:messageID handleId:handleID messageGUID:guid messageText:text dateSent:date dateRead:dateRead isIMessage:isIMessage isFromMe:isFromMe hasAttachment:hasAttachment];
            [allMessagesForChat addObject:message];
        }
    }
    else {
        NSLog(@"ERROR COMPILING ALL MESSAGES QUERY: %s", sqlite3_errmsg(_database));
    }
    
    sqlite3_finalize(statement);
    
    return allMessagesForChat;
}

#pragma mark GET_COUNTS

- (int) getConversationMessageCountStartTime:(int)startTime endTime:(int)endTime
{
    NSString *query = [NSString stringWithFormat:@"SELECT COUNT(*) FROM %@ WHERE (date > %d AND date < %d)", myMessagesTable, startTime, endTime];
    return [self getSimpleCountFromQuery:query];
}

- (int) getOtherMessagesCountStartTime:(int)startTime endTime:(int)endTime
{
    NSString *query = [NSString stringWithFormat:@"SELECT COUNT(*) FROM %@ WHERE (date > %d AND date < %d)", otherMessagesTable, startTime, endTime];
    return [self getSimpleCountFromQuery:query];
}

- (int) getMySentMessagesCountInConversationStartTime:(int)startTime endTime:(int)endTime
{
    NSString *query = [NSString stringWithFormat:@"SELECT COUNT(*) FROM %@ WHERE (date > %d AND date < %d) AND is_from_me=1", myMessagesTable, startTime, endTime];
    return [self getSimpleCountFromQuery:query];
}

- (int) getMySentOtherMessagesCountStartTime:(int)startTime endTime:(int)endTime
{
    NSString *query = [NSString stringWithFormat:@"SELECT COUNT(*) FROM %@ WHERE (date > %d AND date < %d) AND is_from_me=1", otherMessagesTable, startTime, endTime];
    return [self getSimpleCountFromQuery:query];
}

- (int) getReceivedMessagesCountInConversationStartTime:(int)startTime endTime:(int)endTime
{
    NSString *query = [NSString stringWithFormat:@"SELECT COUNT(*) FROM %@ WHERE (date > %d AND date < %d) AND is_from_me=0", myMessagesTable, startTime, endTime];
    return [self getSimpleCountFromQuery:query];
}

- (int) getReceivedOtherMessagesCountStartTime:(int)startTime endTime:(int)endTime
{
    NSString *query = [NSString stringWithFormat:@"SELECT COUNT(*) FROM %@ WHERE (date > %d AND date < %d) AND is_from_me=0", otherMessagesTable, startTime, endTime];
    return [self getSimpleCountFromQuery:query];
}

- (int) getSimpleCountFromQuery:(NSString*)queryString
{
    const char *query = [queryString UTF8String];
    int result = 0;
    sqlite3_stmt *statement;
    
    if(sqlite3_prepare(_database, query, -1, &statement, NULL) == SQLITE_OK) {
        while(sqlite3_step(statement) == SQLITE_ROW) {
            result = sqlite3_column_int(statement, 0);
        }
    }
    
    sqlite3_finalize(statement);
    return result;
}


/****************************************************************
 *
 *              SQLITE_HELPERS
 *
*****************************************************************/

# pragma mark SQLITE_HELPERS

- (BOOL) executeSQLStatement:(const char *)sqlStatement errorMessage:(char*)errorMessage
{
    int counter = 0;
    while(counter < MAX_DB_TRIES) {
        int result = sqlite3_exec(_database, sqlStatement, NULL, NULL, &errorMessage);
        if(result != SQLITE_OK) {
            counter++;
            if(result == SQLITE_BUSY || result == SQLITE_LOCKED) {
                printf("SQLITE_BUSY/LOCKED ERROR IN EXEC: %s\t%s\n", sqlStatement, sqlite3_errmsg(_database));
                [NSThread sleepForTimeInterval:0.01];
            }
            else {
                if(result == SQLITE_CONSTRAINT) {
                    //printf("Duplicate ROWID for insert: %s\n", sqlStatement);
                    return YES;
                }
                else {
                    printf("IN EXEC, ERROR: %s\t%d\t%s\t\n", sqlite3_errmsg(_database), result, sqlStatement);
                }
                return NO;
            }
        }
        else {
            return YES;
        }
    }
    printf("LEFT EXEC SQL STATEMENT AT MAX DB TRIES: %s\n", sqlStatement);
    return NO;
}

- (void) createOtherMessagesTable
{
    //CREATE TABLE %@ (ROWID INTEGER PRIMARY KEY, date INTEGER, wordCount INTEGER, is_from_me INTEGER DEFAULT 0, cache_has_attachments INTEGER
    NSString *createQuery = [NSString stringWithFormat:@"CREATE TABLE %@ (ROWID INTEGER PRIMARY KEY, date INTEGER, wordCount INTEGER, is_from_me INTEGER, cache_has_attachments INTEGER)", otherMessagesTable];
    [self createTable:otherMessagesTable createTableStatement:createQuery];
}

- (void) createMyMessagesTable
{
    NSString *createQuery = [NSString stringWithFormat:@"CREATE TABLE %@ (ROWID INTEGER PRIMARY KEY, guid TEXT UNIQUE NOT NULL, text TEXT, handle_id INTEGER DEFAULT 0, service TEXT, date INTEGER, date_read INTEGER, is_from_me INTEGER DEFAULT 0, cache_has_attachments INTEGER DEFAULT 0, wordCount INTEGER)", myMessagesTable];
    [self createTable:myMessagesTable createTableStatement:createQuery];
}

- (void) createTable:(NSString*)tableName createTableStatement:(NSString*)createTableStatement
{
    char *errorMessage;
    if(sqlite3_exec(_database, [createTableStatement UTF8String], NULL, NULL, &errorMessage) == SQLITE_OK) {
        NSLog(@"SUCCESSFULLY CREATED %@", tableName);
    }
    else {
        printf("ERROR CREATING TABLE: %s\t%s\n", [tableName UTF8String], sqlite3_errmsg(_database));
    }
}

- (const char *)filePath
{
    NSArray *paths=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentDirectory=[paths objectAtIndex:0];
    return [[documentDirectory stringByAppendingPathComponent:@"LoginDatabase.sql"] UTF8String];
}


/****************************************************************
 *
 *              MISC METHODS
 *
*****************************************************************/

# pragma mark MISC_METHODS

- (long)timeAtEndOfDayForDate:(NSDate*)inputDate
{
    // Selectively convert the date components (year, month, day) of the input date
    NSDateComponents *dateComps = [self.calendar components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:inputDate];
    
    // Set the time components manually
    [dateComps setHour:23];
    [dateComps setMinute:59];
    [dateComps setSecond:59];
    
    // Convert back
    NSDate *endOfDay = [self.calendar dateFromComponents:dateComps];
    return [endOfDay timeIntervalSinceReferenceDate];
}

- (long)timeAtBeginningOfDayForDate:(NSDate*)inputDate
{
    // Selectively convert the date components (year, month, day) of the input date
    NSDateComponents *dateComps = [self.calendar components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:inputDate];
    
    // Set the time components manually
    [dateComps setHour:0];
    [dateComps setMinute:0];
    [dateComps setSecond:0];
    
    // Convert back
    NSDate *beginningOfDay = [self.calendar dateFromComponents:dateComps];
    return [beginningOfDay timeIntervalSinceReferenceDate];
}

- (BOOL) isIMessage:(char*)text {
    return strcmp(text, "iMessage") == 0;
}


@end