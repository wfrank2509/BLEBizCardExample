//
//  MasterViewController.h
//  BizCard
//
//  Created by Wolfgang Frank on 21.05.13.
//  Copyright (c) 2013 arconsis IT-Solutions GmbH. All rights reserved.
//

#import <UIKit/UIKit.h>

@class DetailViewController;


@interface MasterViewController : UIViewController

@property (strong, nonatomic) DetailViewController *detailViewController;

@property (strong, nonatomic) IBOutlet UILabel *labelMode;


- (IBAction)buttonClientModePressed:(id)sender;
- (IBAction)buttonServerModePressed:(id)sender;

@end
