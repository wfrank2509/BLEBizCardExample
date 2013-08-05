//
//  MasterViewController.m
//  BizCard
//
//  Created by Wolfgang Frank on 21.05.13.
//  Copyright (c) 2013 arconsis IT-Solutions GmbH. All rights reserved.
//

#import "MasterViewController.h"

#import "BizCardServer.h"
#import "BizCardClient.h"

@interface MasterViewController ()

@property (strong, nonatomic) BizCardServer *cardServer;
@property (strong, nonatomic) BizCardClient *cardClient;

@end

@implementation MasterViewController

- (void)awakeFromNib
{
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        self.contentSizeForViewInPopover = CGSizeMake(320.0, 600.0);
    }
    [super awakeFromNib];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.detailViewController = (DetailViewController *)[[self.splitViewController.viewControllers lastObject] topViewController];

}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}



- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{

}

- (IBAction)buttonClientModePressed:(id)sender {
    [self.cardServer stopBizCardServer];
    self.cardServer = nil;

    self.cardClient = [[BizCardClient alloc] init];
    [self.cardClient startBizCardClient];

    self.labelMode.text = @"CLIENT MODE";
}


- (IBAction)buttonServerModePressed:(id)sender {
    [self.cardClient stopBizCardClient];
    self.cardClient = nil;

    self.cardServer = [[BizCardServer alloc] init];
    [self.cardServer startBizCardServer];

    self.labelMode.text = @"SERVER MODE";
}

@end
