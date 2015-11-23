//
//  Attachment.m
//  iMessageAnalyzer
//
//  Created by Ryan D'souza on 10/6/15.
//  Copyright © 2015 Ryan D'souza. All rights reserved.
//

#import "Attachment.h"

@implementation Attachment

- (instancetype) initWithAttachmentID:(int32_t)attachmentID attachmentGUID:(NSString *)guid filePath:(NSString *)filePath fileType:(NSString *)fileType sentDate:(NSDate *)sentDate attachmentSize:(long)attachmentSize messageID:(int32_t)messageID fileName:(NSString *)fileName
{
    self = [super init];
    
    if(self) {
        self.attachmentId = attachmentID;
        self.messageId = messageID;
        self.guid = guid;
        self.filePath = filePath;
        self.fileType = fileType;
        self.sentDate = sentDate;
        self.size = attachmentSize;
        self.fileName = fileName;
    }
    
    return self;
}


@end
