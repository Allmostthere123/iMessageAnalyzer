//
//  DatabaseManager.h
//  iMessageAnalyzer
//
//  Created by Ryan D'souza on 10/8/15.
//  Copyright © 2015 Ryan D'souza. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <sqlite3.h>

#include <string.h>

#import "Message.h"

@interface DatabaseManager : NSObject

+ (instancetype) getInstance;

@end
