//
//  StartupViewController.h
//  iMessageAnalyzer
//
//  Created by Ryan D'souza on 1/10/16.
//  Copyright © 2016 Ryan D'souza. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@protocol StartupViewControllerDelegate <NSObject>

- (void) didWishToContinue;
- (void) didWishToExit;

@end

@interface StartupViewController : NSViewController

@property (weak, nonatomic) id<StartupViewControllerDelegate> delegate;

@end
