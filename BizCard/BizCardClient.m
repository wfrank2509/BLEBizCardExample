//
//  BizCardClient.m
//  BizCard
//
//  Created by Wolfgang Frank on 07.06.13.
//  Copyright (c) 2013 arconsis IT-Solutions GmbH. All rights reserved.
//

#import "BizCardClient.h"
#import <CoreBluetooth/CoreBluetooth.h>

#define kUpperProximityRSSILimit -15
#define kLowerProximityRSSILimit -32

@interface BizCardClient ()  <CBCentralManagerDelegate, CBPeripheralDelegate>

@property (nonatomic, strong) CBCentralManager *centralManager;
@property (nonatomic, strong) CBPeripheral *connectedPeripheral;
@property (nonatomic, strong) NSMutableData *data;

@end


@implementation BizCardClient

// First create the central manager to act as client (manager) for data
-(id)init
{

    if (self = [super init]) {
        _centralManager = [[CBCentralManager alloc] initWithDelegate:self queue:dispatch_queue_create("BLE_Queue", nil)];
        _data = [[NSMutableData alloc] init];
    }

    return self;
}

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    switch (central.state) {
        case CBCentralManagerStatePoweredOn:
            // Scans for any peripheral
            //[self scan];
            NSLog(@"Central Manager ready to scan fro services");
            break;
        default:
            NSLog(@"Central Manager did change state");
            break;
    }
}


- (void)scan
{
    [self.centralManager scanForPeripheralsWithServices:@[ [CBUUID UUIDWithString:kCardServiceUUID] ]
                                                options:@{CBCentralManagerScanOptionAllowDuplicatesKey : @YES }];
}

- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral
     advertisementData:(NSDictionary *)advertisementData
                  RSSI:(NSNumber *)RSSI {

    // Reject any where the value is above reasonable range
    // Reject if the signal strength is too low to be close enough (Close is around -22dB)
    if (RSSI.integerValue > kUpperProximityRSSILimit || RSSI.integerValue < kLowerProximityRSSILimit) {
        NSLog(@"Too far RSSI: %@", RSSI);
        return;
    }
    
    // Stops scanning for peripheral if close enough
    [self.centralManager stopScan];

    if (self.connectedPeripheral != peripheral) {
        self.connectedPeripheral = peripheral;
        NSLog(@"Connecting to peripheral %@", peripheral);
        NSLog(@"Advertisement Data %@ : %@",    [advertisementData objectForKey:CBAdvertisementDataLocalNameKey],
                                                [advertisementData objectForKey:CBAdvertisementDataServiceUUIDsKey]);
        NSLog(@"RSSI: %@", RSSI);

        // Connects to the discovered peripheral
        [self.centralManager connectPeripheral:peripheral options:nil];
    }
}


- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral
{
    NSLog(@"didConnectPeripheral");

    // Clears the data
    [self.data setLength:0];
    // Set peripheral delegate
    peripheral.delegate = self;
    // Asks peripheral to discover service
    [peripheral discoverServices:@[ [CBUUID UUIDWithString:kCardServiceUUID] ]];
}

- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
    if (error) {
        NSLog(@"Error connecting to peripheral: %@", [error localizedDescription]);
        [self cleanup];
        return;
    }
}

- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
    if (error) {
        NSLog(@"Error disconnecting peripheral: %@", [error localizedDescription]);
    }
    [self cleanup];
    self.connectedPeripheral = nil;
    // Disconnected ==> start scanning again
    //[self scan];
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error
{
    if (error) {
        NSLog(@"Error discovering service: %@", [error localizedDescription]);
        [self cleanup];
        return;
    }

    for (CBService *service in peripheral.services) {
        NSLog(@"Service found with UUID: %@", service.UUID);

        // Discovers the characteristics for a given service
        if ([service.UUID isEqual:[CBUUID UUIDWithString:kCardServiceUUID]]) {
            [peripheral discoverCharacteristics:@[[CBUUID UUIDWithString:kCardCharacteristicUUID]]
                                                   forService:service];
        }
    }
}


- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error
{
    if (error) {
        NSLog(@"Error discovering characteristic: %@", [error localizedDescription]);
        [self cleanup];
        return;
    }
    
    if ([service.UUID isEqual:[CBUUID UUIDWithString:kCardServiceUUID]]) {
        for (CBCharacteristic *characteristic in service.characteristics) {
            if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:kCardCharacteristicUUID]]) {
                // Subscribe to characteristic
                [peripheral setNotifyValue:YES forCharacteristic:characteristic];
            }
        }
    }
}


// This callback lets us know more data has arrived via notification on the characteristic
- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    if (error) {
        NSLog(@"Error discovering characteristics: %@", [error localizedDescription]);
        [self cleanup];
        return;
    }

    NSString *stringFromData = [[NSString alloc] initWithData:characteristic.value encoding:NSUTF8StringEncoding];

    // Have we got everything we need?
    if ([stringFromData isEqualToString:@"EOM"]) {

        // We have, so show the data,
        NSString *receivedData = [[NSString alloc] initWithData:self.data encoding:NSUTF8StringEncoding];
        NSLog(@"Received Data so far: %@", receivedData);

        // Cancel our subscription to the characteristic
        [peripheral setNotifyValue:NO forCharacteristic:characteristic];

        // and disconnect from the peripehral
        [self.centralManager cancelPeripheralConnection:peripheral];

        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Received" message:@"Data arrived" delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
            [alert show];
        });
    }

    // Otherwise, just add the data on to what we already have
    [self.data appendData:characteristic.value];

    // Log it
    NSLog(@"Received: %@", stringFromData);
}


// The peripheral letting us know whether our subscribe/unsubscribe happened or not
- (void)peripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    if (error) {
        NSLog(@"Error changing notification state: %@", error.localizedDescription);
    }

    // Exit if it's not the transfer characteristic
    if (![characteristic.UUID isEqual:[CBUUID UUIDWithString:kCardCharacteristicUUID]]) {
        return;
    }

    // Notification has started
    if (characteristic.isNotifying) {
        NSLog(@"Notification began on %@", characteristic);
    }

    // Notification has stopped
    else {
        // so disconnect from the peripheral
        NSLog(@"Notification stopped on %@.  Disconnecting", characteristic);
        [self.centralManager cancelPeripheralConnection:peripheral];
    }
}


/** Call this when things either go wrong, or you're done with the connection.
 *  This cancels any subscriptions if there are any, or straight disconnects if not.
 *  (didUpdateNotificationStateForCharacteristic will cancel the connection if a subscription is involved)
 */
- (void)cleanup
{
    // Don't do anything if we're not connected
    if (!self.connectedPeripheral.isConnected) {
        return;
    }

    // See if we are subscribed to a characteristic on the peripheral
    if (self.connectedPeripheral.services != nil) {
        for (CBService *service in self.connectedPeripheral.services) {
            if (service.characteristics != nil) {
                for (CBCharacteristic *characteristic in service.characteristics) {
                    if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:kCardCharacteristicUUID]]) {
                        if (characteristic.isNotifying) {
                            // It is notifying, so unsubscribe
                            [self.connectedPeripheral setNotifyValue:NO forCharacteristic:characteristic];

                            // And we're done.
                            return;
                        }
                    }
                }
            }
        }
    }

    // If we've got this far, we're connected, but we're not subscribed, so we just disconnect
    [self.centralManager cancelPeripheralConnection:self.connectedPeripheral];
}



-(void)startBizCardClient
{
    [self scan];
    NSLog(@"Start scanning");
}


-(void)stopBizCardClient
{
    [self.centralManager stopScan];
    [self cleanup];
    NSLog(@"Stopped scanning");
}


@end
