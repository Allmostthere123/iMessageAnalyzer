//
//  CalendarPopUpViewController.h
//  iMessageAnalyzer
//
//  Created by Ryan D'souza on 11/2/15.
//  Copyright © 2015 Ryan D'souza. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@protocol CalendarPopUpViewControllerDelegate <NSObject>

- (void) resetToAll:(BOOL)resetToAll;
- (void) fromDayChosen:(NSDate*)fromDayChosen toDayChosen:(NSDate*)toDayChosen;

@end

@interface CalendarPopUpViewController : NSViewController <NSDatePickerCellDelegate>

@property (weak, nonatomic) id<CalendarPopUpViewControllerDelegate> delegate;
@property (strong, nonatomic) NSDate *dateToShow;

@end