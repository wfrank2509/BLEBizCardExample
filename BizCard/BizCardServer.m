//
//  CardManager.m
//  BizCard
//
//  Created by Wolfgang Frank on 21.05.13.
//  Copyright (c) 2013 arconsis IT-Solutions GmbH. All rights reserved.
//

#import "BizCardServer.h"
#import <CoreBluetooth/CoreBluetooth.h>

#define NOTIFY_MTU      20

@interface BizCardServer ()  <CBPeripheralManagerDelegate>

@property (nonatomic, strong) CBPeripheralManager *peripheralManager;
@property (nonatomic, strong) CBMutableService *cardService;
@property (nonatomic, strong) CBMutableCharacteristic *cardCharacteristic;


@property (strong, nonatomic) NSData *dataToSend;
@property (nonatomic, readwrite) NSInteger sendDataIndex;

@end


@implementation BizCardServer

// First create the peripheral manager to act as server (manager) for data
-(id)init
{

    if (self = [super init]) {
        self.peripheralManager = [[CBPeripheralManager alloc] initWithDelegate:self queue:dispatch_queue_create("BLE_Queue", nil)];
    }

    return self;
}


// Check if Bluetooth LE is available and setup service
- (void)peripheralManagerDidUpdateState:(CBPeripheralManager *)peripheral
{
    switch (peripheral.state) {
        case CBPeripheralManagerStatePoweredOn:
            [self setupService];
            break;
        default:
            NSLog(@"Peripheral Manager did update state");
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Bluetooth Info"
                                                            message:@"Bluetooth LE is not available or activated" delegate:nil
                                                  cancelButtonTitle:@"OK"
                                                  otherButtonTitles:nil, nil];
            [alert show];
            break;
    }
}


// Construct a new service and publish it
- (void)setupService
{
    // Create characteristic
    self.cardCharacteristic = [[CBMutableCharacteristic alloc] initWithType:[CBUUID UUIDWithString:kCardCharacteristicUUID]
                                                                 properties:CBCharacteristicPropertyNotify
                                                                      value:nil
                                                                permissions:CBAttributePermissionsReadable];

    // Create service and add characteristic
    self.cardService = [[CBMutableService alloc] initWithType:[CBUUID UUIDWithString:kCardServiceUUID]
                                                      primary:YES];
    // Set the characteristic for service
    [self.cardService setCharacteristics:@[self.cardCharacteristic]];
    // Publish service
    [self.peripheralManager addService:self.cardService];
}


// When service is added start advertising it via Bluetooth LE
- (void)peripheralManager:(CBPeripheralManager *)peripheral
            didAddService:(CBService *)service
                    error:(NSError *)error
{
    
    if (error == nil) {
        NSLog(@"Service Setup (not advertised yet)");
    }
}


- (void)startAdvertisingBizCardService
{
    // Start advertising the service
    [self.peripheralManager startAdvertising:@{ CBAdvertisementDataLocalNameKey     : @"BCS",
                                                CBAdvertisementDataServiceUUIDsKey  : @[ [CBUUID UUIDWithString:kCardServiceUUID] ] }];
}

- (void)stopAdvertisingBizCardService
{
    // Start advertising the service
    [self.peripheralManager stopAdvertising];
}



// Recognise when the central unsubscribes
- (void)peripheralManager:(CBPeripheralManager *)peripheral central:(CBCentral *)central didUnsubscribeFromCharacteristic:(CBCharacteristic *)characteristic
{
    NSLog(@"Central unsubscribed from characteristic");
}

// Catch when someone subscribes to our characteristic, then start sending them data
- (void)peripheralManager:(CBPeripheralManager *)peripheral central:(CBCentral *)central didSubscribeToCharacteristic:(CBCharacteristic *)characteristic
{

    if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:kCardCharacteristicUUID]]) {
        NSLog(@"Central subscribed to kCardCharacteristicUUID");
        // Get the data
        self.dataToSend = [@"{'firstName' : 'Peter', 'lastName' : 'Pan','organization' : 'New kids on the block', 'location' : 'Neverland','contact' : 'pp@neverland.org'}!" dataUsingEncoding:NSUTF8StringEncoding];

        // Reset the index
        self.sendDataIndex = 0;

        // Start sending
        [self sendData];
    }

}

// Sends the next amount of data to the connected central
- (void)sendData
{
    // First up, check if we're meant to be sending an EOM
    static BOOL sendingEOM = NO;

    if (sendingEOM) {
        // send EOM
        if ([self.peripheralManager updateValue:[@"EOM" dataUsingEncoding:NSUTF8StringEncoding]
                                         forCharacteristic:self.cardCharacteristic
                           onSubscribedCentrals:nil]) {
            // Mark it as sent
            sendingEOM = NO;
            NSLog(@"Sent: EOM");
        } else {
            // It didn't send, so we'll exit and wait for peripheralManagerIsReadyToUpdateSubscribers to call sendData again
            return;
        }
    }

    // We're not sending an EOM, so we're sending data
    // Data left to send?
    if (self.sendDataIndex >= self.dataToSend.length) {
        return; // No data left.  Do nothing
    }

    // There's data left, so send until the callback fails, or we're done.
    BOOL didSend = YES;

    // Make the next chunk
    while (didSend) {
        // How big should chunk be
        NSInteger amountToSend = self.dataToSend.length - self.sendDataIndex;

        // Can't be longer than 20 bytes
        if (amountToSend > NOTIFY_MTU) {
            amountToSend = NOTIFY_MTU;
        }

        // Copy out the data we want
        NSData *chunk = [NSData dataWithBytes:self.dataToSend.bytes+self.sendDataIndex length:amountToSend];

        // Send next chunk of data
        if ( [self.peripheralManager updateValue:chunk forCharacteristic:self.cardCharacteristic onSubscribedCentrals:nil] ) {

            NSString *stringFromData = [[NSString alloc] initWithData:chunk encoding:NSUTF8StringEncoding];
            NSLog(@"Sent: %@", stringFromData);

            // Update our index
            self.sendDataIndex += amountToSend;

            // Was it the last one?
            if (self.sendDataIndex >= self.dataToSend.length) {
                // It was - send an EOM
                // Set this so if the send fails, we'll send it next time
                sendingEOM = YES;
                // Send EOM
                if ([self.peripheralManager updateValue:[@"EOM" dataUsingEncoding:NSUTF8StringEncoding]
                                                 forCharacteristic:self.cardCharacteristic
                                   onSubscribedCentrals:nil]) {
                    // we're all done
                    sendingEOM = NO;
                    NSLog(@"Sent: EOM");
                } else {
                    return;
                }
            }
        } else {
            // Didn't work - drop out and wait for the callback
            return;
        }
    }
}

//This callback comes in when the PeripheralManager is ready to send the next chunk of data.
// This is to ensure that packets will arrive in the order they are sent
- (void)peripheralManagerIsReadyToUpdateSubscribers:(CBPeripheralManager *)peripheral
{
    // Start sending again
    [self sendData];
}


-(void)startBizCardServer
{
    [self startAdvertisingBizCardService];
    NSLog(@"Start advertising");
}


-(void)stopBizCardServer
{
    [self stopAdvertisingBizCardService];
    NSLog(@"Stopped advertising");
}

@end
