//
//  CalendarPopUpViewController.m
//  iMessageAnalyzer
//
//  Created by Ryan D'souza on 11/2/15.
//  Copyright © 2015 Ryan D'souza. All rights reserved.
//

#import "CalendarPopUpViewController.h"

@interface CalendarPopUpViewController ()

@property (strong) IBOutlet NSDatePicker *datePicker;
@property (strong) IBOutlet NSButton *resetToAllButton;

@end

@implementation CalendarPopUpViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self.datePicker setDateValue:[NSDate date]];
    
}
- (IBAction)resetToAllButtonClick:(id)sender {
    
}

- (void) datePickerCell:(NSDatePickerCell *)aDatePickerCell validateProposedDateValue:(NSDate *__autoreleasing  _Nonnull *)proposedDateValue timeInterval:(NSTimeInterval *)proposedTimeInterval
{
    NSDateFormatter *d = [[NSDateFormatter alloc] init];
    [d setDateFormat:@"MM/dd/yyyy HH:mm"];
    NSString *aDate = [d stringFromDate:*proposedDateValue];
    NSLog(@"Date: %@", aDate);
}



@end
