//
//  BeaconRegionManager.m
//  iBeacon_Manager
//
//  Created by David Crow on 10/3/13.
//  Copyright (c) 2013 David Crow. All rights reserved.
//

#import "BeaconRegionManager.h"
#import "BeaconManagerValues.h"
#import "UAPush.h"

@interface BeaconRegionManager ()

@property (strong, nonatomic) BeaconListManager *listManager;//writable declaration


@end

@implementation BeaconRegionManager {
    @private
        //temporary store for detailed ranging
        NSMutableDictionary *_currentRangedBeacons;
}

+ (BeaconRegionManager *)shared {
    DEFINE_SHARED_INSTANCE_USING_BLOCK(^{
        return [[self alloc] init];
    });
}

-(BeaconRegionManager *)init {
    self = [super init];
    
    _listManager = [[BeaconListManager alloc] init];
    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
    _currentRangedBeacons = [[NSMutableDictionary alloc] init];
    return self;
}

-(void)startManager {
    //clear monitoring on store location manager regions
    [self stopMonitoringAllBeaconRegions];
    
    //initialize ibeacon manager, load iBeacon plist, load available regions, start monitoring available regions
    [self startMonitoringAllAvailableBeaconRegions];
    [self loadBeaconStats];
}

-(void)stopManager {
    //clear monitoring on store location manager regions
    [self stopMonitoringAllBeaconRegions];
}

-(void)removeAllBeaconTags {
    for (CLBeaconRegion *beaconRegion in [[self listManager] availableBeaconRegionsList]) {
        [[UAPush shared] removeTagFromCurrentDevice:[NSString stringWithFormat:@"%@%@", kExitTagPreamble, beaconRegion.identifier]];
        [[UAPush shared] removeTagFromCurrentDevice:[NSString stringWithFormat:@"%@%@", kEntryTagPreamble, beaconRegion.identifier]];
    }
    [[UAPush shared] updateRegistration];
}

//helper method to return a properly formatted (short style) date
-(NSString *)dateStringFromInterval:(NSTimeInterval)interval {
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:interval];
    NSString *dateString = [NSDateFormatter localizedStringFromDate:date
                                                          dateStyle:NSDateFormatterShortStyle
                                                          timeStyle:NSDateFormatterNoStyle];
    return dateString;
}

#pragma monitoring stop/start helpers

-(void)startMonitoringBeaconInRegion:(CLBeaconRegion *)beaconRegion {
    if (beaconRegion != nil) {
        beaconRegion.notifyOnEntry = YES;
        beaconRegion.notifyOnExit = YES;
        beaconRegion.notifyEntryStateOnDisplay = NO;
        [self.locationManager startRangingBeaconsInRegion:beaconRegion];
        [self.locationManager startMonitoringForRegion:beaconRegion];
    }
}

-(void)stopMonitoringBeaconInRegion:(CLBeaconRegion *)beaconRegion {
    if (beaconRegion != nil) {
        beaconRegion.notifyOnEntry = NO;
        beaconRegion.notifyOnExit = NO;
        beaconRegion.notifyEntryStateOnDisplay = NO;
        [self.locationManager stopRangingBeaconsInRegion:beaconRegion];
        [self.locationManager stopMonitoringForRegion:beaconRegion];
    }
}

//helper method to start monitoring all available beacon regions with no notifications
-(void)startMonitoringAllAvailableBeaconRegions {
    for (CLBeaconRegion *beaconRegion in [[self listManager] availableBeaconRegionsList]){
        if (beaconRegion != nil){
            [self startMonitoringBeaconInRegion:beaconRegion];
        }
    }
}

//helper method to stop monitoring all available beacon regions
-(void)stopMonitoringAllAvailableBeaconRegions {
    for (CLBeaconRegion *beaconRegion in [[self listManager] availableBeaconRegionsList]) {
        [self stopMonitoringBeaconInRegion:beaconRegion];
        //reset monitored region count
    }
}

//stops monitoring all beacons in the current location monitor list
-(void)stopMonitoringAllBeaconRegions {
    for (CLBeaconRegion *beaconRegion in [self.locationManager monitoredRegions]) {
        if (beaconRegion != nil) {
            beaconRegion.notifyOnEntry = NO;
            beaconRegion.notifyOnExit = NO;
            beaconRegion.notifyEntryStateOnDisplay = NO;
            [self.locationManager stopRangingBeaconsInRegion:beaconRegion];
            [self.locationManager stopMonitoringForRegion:beaconRegion];
            //reset monitored region count
        }
    }
}

#pragma location manager callbacks

//this gets called once for each beacon regions at 1 hz
- (void)locationManager:(CLLocationManager *)manager didRangeBeacons:(NSArray *)beacons inRegion:(CLBeaconRegion *)region {
    // CoreLocation will call this delegate method at 1 Hz once for each region
    
    //if a mutable array exists under key region.identifier, replace it's contents with the ranged beacons
    if ([_currentRangedBeacons objectForKey:region.identifier] && [[_currentRangedBeacons objectForKey:region.identifier] isKindOfClass:[NSMutableArray class]]) {
        
        NSMutableArray *currentBeaconsInRegion = [_currentRangedBeacons objectForKey:region.identifier];
        currentBeaconsInRegion = [NSMutableArray arrayWithArray:beacons];
        [_currentRangedBeacons setObject:currentBeaconsInRegion forKey:region.identifier];
    }
    //if no mutable array exists under key, allocate mutable array and replace with ranged beacons
    else{
        NSMutableArray *currentBeaconsInRegion = [[NSMutableArray alloc] initWithArray:beacons];
        //place current ranged beacons for this region under this region's key
        [_currentRangedBeacons setObject:currentBeaconsInRegion forKey:region.identifier];
    }
    
    //this notification is used to update views that rely on ranging
    [[NSNotificationCenter defaultCenter]
     postNotificationName:@"managerDidRangeBeacons"
     object:self];
}

- (void)locationManager:(CLLocationManager *)manager didEnterRegion:(CLRegion *)region {
    //swap default entry/exit tags
    [[UAPush shared] removeTagFromCurrentDevice:[NSString stringWithFormat:@"%@%@", kExitTagPreamble, region.identifier]];
    [[UAPush shared] addTagToCurrentDevice:[NSString stringWithFormat:@"%@%@", kEntryTagPreamble, region.identifier]];

    //set user-provided entry tags and remove user-provided exit tags
    [self addEntryTagsForBeaconRegion:[self beaconRegionWithId:region.identifier]];
    [self removeExitTagsForBeaconRegion:[self beaconRegionWithId:region.identifier]];

    UA_LDEBUG(@"Updating tags");
    [[UAPush shared] updateRegistration];
    UA_LDEBUG(@"Timestamping didEnterRegion '%@'", region.identifier);
    [self timestampEntryForBeaconRegion:[self beaconRegionWithId:region.identifier]];
}

- (void)locationManager:(CLLocationManager *)manager didExitRegion:(CLRegion *)region {
    //swap default entry/exit tags
    [[UAPush shared] removeTagFromCurrentDevice:[NSString stringWithFormat:@"%@%@", kEntryTagPreamble, region.identifier]];
    [[UAPush shared] addTagToCurrentDevice:[NSString stringWithFormat:@"%@%@", kExitTagPreamble, region.identifier]];
    
    //set user-provided exit tags and remove user-provided entry tags
    [self addExitTagsForBeaconRegion:[self beaconRegionWithId:region.identifier]];
    [self removeEntryTagsForBeaconRegion:[self beaconRegionWithId:region.identifier]];

    UA_LDEBUG(@"Updating tags");
    [[UAPush shared] updateRegistration];
    UA_LDEBUG(@"Timestamping didExitRegion '%@'", region.identifier);
    //exit timestamp includes cumulative time measurement
    [self timestampExitForBeaconRegion:[self beaconRegionWithId:region.identifier]];
}

//this is redundant but ensures all regions are tagged as inside or outside
- (void)locationManager:(CLLocationManager *)manager didDetermineState:(CLRegionState)state forRegion:(CLRegion *)region {
    // A user can transition in or out of a region while the application is not running.
    // When this happens CoreLocation will launch the application momentarily, call this delegate method

    if(state == CLRegionStateInside) {
        //set default entry tag (implied entry)
        [[UAPush shared] addTagToCurrentDevice:[NSString stringWithFormat:@"%@%@", kEntryTagPreamble, region.identifier]];
        //set user-provided entry tags
        [self addEntryTagsForBeaconRegion:[self beaconRegionWithId:region.identifier]];
        //remove all exit tags (implied entry
        [self removeExitTagsForBeaconRegion:[self beaconRegionWithId:region.identifier]];
        [[UAPush shared] updateRegistration];
        UA_LDEBUG( @"Beacon Manager Updated State: Entered Region '%@'", region.identifier );
        
        //if lastEntry is null then entry is when the app started in the region
        if (![self lastEntryForIdentifier:region.identifier]){
            [self timestampEntryForBeaconRegion:[self beaconRegionWithId:region.identifier]];
        }
    }
    else if(state == CLRegionStateOutside) {
        //Remove default entry tag and any user defined entry tags and update registration
        [[UAPush shared] removeTagFromCurrentDevice:[NSString stringWithFormat:@"%@%@", kEntryTagPreamble, region.identifier]];
        [self removeEntryTagsForBeaconRegion:[self beaconRegionWithId:region.identifier]];
        [[UAPush shared] updateRegistration];
       UA_LDEBUG(@"Beacon Manager Updated State: Exited Region '%@'", region.identifier);
    }
    UALOG(@"Updating tag");
    [[UAPush shared] updateRegistration];
}

- (void)locationManager:(CLLocationManager *)manager rangingBeaconsDidFailForRegion:(CLBeaconRegion *)region withError:(NSError *)error {
    UA_LDEBUG(@"%@", error);
    NSLog(@"%@", error);
}


- (void)locationManager:(CLLocationManager *)manager monitoringDidFailForRegion:(CLRegion *)region withError:(NSError *)error {
    UA_LDEBUG(@"%@", error);
    NSLog(@"%@", error);
}


#pragma beacon stats helpers

-(void)loadBeaconStats {
    if ([[NSUserDefaults standardUserDefaults] objectForKey:kiBeaconStats]){
        self.beaconStats = [[NSMutableDictionary alloc] initWithDictionary:[[NSUserDefaults standardUserDefaults] objectForKey:kiBeaconStats]];
    }
    else{
        self.beaconStats = [[NSMutableDictionary alloc] init];
        [self saveBeaconStats];
    }
}

-(void)saveBeaconStats {
    [[NSUserDefaults standardUserDefaults] setObject:self.beaconStats forKey:kiBeaconStats];
}

-(void)clearAllBeaconStats {
    self.beaconStats = nil;
    [[NSUserDefaults standardUserDefaults] setObject:self.beaconStats forKey:kiBeaconStats];
}

-(void)clearBeaconStatsForBeaconRegion:(CLBeaconRegion *)beaconRegion {
    if ([self.beaconStats objectForKey:beaconRegion.identifier]){
    [self.beaconStats setObject:nil forKey:beaconRegion.identifier];
    }
    [self saveBeaconStats];
}

-(NSMutableDictionary *)beaconStatsForIdentifier:(NSString *)identifier {
    if (self.beaconStats && [self.beaconStats objectForKey:identifier]) {
        return [self.beaconStats objectForKey:identifier];
    }
    //NSLog(@"No beacon stats for that identifier are available");
    return nil;
}

-(double)lastEntryForIdentifier:(NSString *)identifier {
    if (self.beaconStats && [self.beaconStats objectForKey:identifier]) {
        NSDictionary *stats = [self.beaconStats objectForKey:identifier];
        if ([stats objectForKey:kLastEntry]){
            return [[stats objectForKey:kLastEntry] doubleValue];
        }
        
    }
    //NSLog(@"No lastEntry for that identifier is available");
    return 0;
}

-(double)lastExitForIdentifier:(NSString *)identifier {
    if (self.beaconStats && [self.beaconStats objectForKey:identifier]) {
        
        NSDictionary *stats = [self.beaconStats objectForKey:identifier];
        if ([stats objectForKey:kLastExit]){
            return [[stats objectForKey:kLastExit] doubleValue];
        }
        
    }
    //NSLog(@"No lastExit for that identifier is available");
    return 0;
}

-(double)cumulativeTimeForIdentifier:(NSString *)identifier {
    if (self.beaconStats && [self.beaconStats objectForKey:identifier]) {
        NSDictionary *stats = [self.beaconStats objectForKey:identifier];
        if ([stats objectForKey:kCumulativeTime]){
            return [[stats objectForKey:kCumulativeTime] doubleValue];
        }
    }
    //NSLog(@"No cumulativeTime for that identifier is available");
    return 0;
}

//directly caluclates dumb average dwell time and returns it for display
-(double)averageVisitTimeForIdentifier:(NSString *)identifier {
    
    if ([self cumulativeTimeForIdentifier:identifier] && [self visitsForIdentifier:identifier])
        return [self cumulativeTimeForIdentifier:identifier]/[self visitsForIdentifier:identifier];
    else
        return 0;
}

-(int)visitsForIdentifier:(NSString *)identifier {
    if (self.beaconStats && [self.beaconStats objectForKey:identifier]) {
        NSDictionary *stats = [self.beaconStats objectForKey:identifier];
        if ([stats objectForKey:kVisits]){
            return [[stats objectForKey:kVisits] intValue];
        }
    }
    //NSLog(@"No visits for that identifier are available");
    return 0;
}

//saves last entry time to the last entry time key in NSUderDefaults
-(void)timestampEntryForBeaconRegion:(CLBeaconRegion *)beaconRegion {
    if (beaconRegion.identifier){
        if ([self.beaconStats objectForKey:beaconRegion.identifier]) {
            NSMutableDictionary *beaconRegionStats = [[NSMutableDictionary alloc] initWithDictionary:[self.beaconStats objectForKey:beaconRegion.identifier]];
            [beaconRegionStats setObject:[NSNumber numberWithDouble:[[NSDate date] timeIntervalSince1970]] forKey:kLastEntry];
            [self.beaconStats setObject:beaconRegionStats forKey:beaconRegion.identifier];

        }
        else {
            //create new dictionary for this region and add it to stats
            NSMutableDictionary *beaconRegionStats = [NSMutableDictionary new];
            [beaconRegionStats setObject:[NSNumber numberWithDouble:[[NSDate date] timeIntervalSince1970]] forKey:kLastEntry];
            [self.beaconStats setObject:beaconRegionStats forKey:beaconRegion.identifier];
        }
        [self saveBeaconStats];
    }
    
    //record a visit on entry after necessary dictionary check is made
    [self recordVisitForBeaconRegion:beaconRegion];
}

//saves last exit time to the last exit time key in NSUderDefaults
-(void)timestampExitForBeaconRegion:(CLBeaconRegion *)beaconRegion {
    if (beaconRegion.identifier) {
        if ([self.beaconStats objectForKey:beaconRegion.identifier]) {
            NSMutableDictionary *beaconRegionStats = [[NSMutableDictionary alloc] initWithDictionary:[self.beaconStats objectForKey:beaconRegion.identifier]];
            [beaconRegionStats setObject:[NSNumber numberWithDouble:[[NSDate date] timeIntervalSince1970]] forKey:kLastExit];
            [self.beaconStats setObject:beaconRegionStats forKey:beaconRegion.identifier];

        }
        else {
            //create new dictionary for this region and add it to stats
            NSMutableDictionary *beaconRegionStats = [NSMutableDictionary new];
            [beaconRegionStats setObject:[NSNumber numberWithDouble:[[NSDate date] timeIntervalSince1970]] forKey:kLastExit];
            [self.beaconStats setObject:beaconRegionStats forKey:beaconRegion.identifier];
        }
        [self saveBeaconStats];
    }
    
    [self recordCumulativeTimeForBeaconRegion:beaconRegion];
}

//calculates beacon region's visit count and saves it to the visits key in NSUderDefaults
-(void)recordVisitForBeaconRegion:(CLBeaconRegion *)beaconRegion {
    int visits;
    if (beaconRegion.identifier) {
        //NSLog(@"visit recorded");
        //if beaconstats dict is present
        if ([self.beaconStats objectForKey:beaconRegion.identifier]) {
            NSMutableDictionary *beaconRegionStats = [[NSMutableDictionary alloc] initWithDictionary:[self.beaconStats objectForKey:beaconRegion.identifier]];
            
            if ([self visitsForIdentifier:beaconRegion.identifier]) {
                visits = [self visitsForIdentifier:beaconRegion.identifier] + 1;
            }
            else {
                visits = 1;
            }
            
            [beaconRegionStats setObject:[NSNumber numberWithInteger:visits] forKey:kVisits];
            [self.beaconStats setObject:beaconRegionStats forKey:beaconRegion.identifier];
            
        }
        [self saveBeaconStats];
    }
}

//calculates cumulative time in beacon region and saves it to the cumulative time key in NSUderDefaults
-(void)recordCumulativeTimeForBeaconRegion:(CLBeaconRegion *)beaconRegion {
    NSTimeInterval cumulativeTime = [self cumulativeTimeForIdentifier:beaconRegion.identifier];
    NSTimeInterval entryTime = [self lastEntryForIdentifier:beaconRegion.identifier];
    NSTimeInterval exitTime = [self lastExitForIdentifier:beaconRegion.identifier];
    
    NSMutableDictionary *beaconRegionStats = [[NSMutableDictionary alloc] initWithDictionary:[self.beaconStats objectForKey:beaconRegion.identifier]];
    
    if (entryTime > 0) {
        cumulativeTime = cumulativeTime + (exitTime - entryTime);
        [beaconRegionStats setObject:[NSNumber numberWithDouble:cumulativeTime] forKey:kCumulativeTime];
        [self.beaconStats setObject:beaconRegionStats forKey:beaconRegion.identifier];
        
    }
    else {
        [beaconRegionStats setObject:@0 forKey:kCumulativeTime];
        [self.beaconStats setObject:beaconRegionStats forKey:beaconRegion.identifier];
        
    }
    [self saveBeaconStats];
}


//checks NSUserDefaults for tags array at the key "ua-beaconmanager-<identifier>-entry-tags" and applies them if it exists
-(void)addEntryTagsForBeaconRegion:(CLBeaconRegion *)beaconRegion {
    if (beaconRegion.identifier){
        NSString *beaconEntryTagsKey = [NSString stringWithFormat:@"ua-beaconmanager-%@-entry-tags",beaconRegion.identifier];
        if ([[NSUserDefaults standardUserDefaults] objectForKey:beaconEntryTagsKey]){
            [[UAPush shared] addTagsToCurrentDevice:[[NSUserDefaults standardUserDefaults] objectForKey:beaconEntryTagsKey]];
        }
        else{
            UALOG(@"No exit tags set for key %@", beaconEntryTagsKey);
        }
    }
}

//just looks in NSUserDefaults for tags array at the key "ua-beaconmanager-<identifier>-exit-tags" and applies them if it exists
-(void)addExitTagsForBeaconRegion:(CLBeaconRegion *)beaconRegion {
    if (beaconRegion.identifier){
        NSString *beaconExitTagsKey = [NSString stringWithFormat:@"ua-beaconmanager-%@-exit-tags",beaconRegion.identifier];
        if ([[NSUserDefaults standardUserDefaults] objectForKey:beaconExitTagsKey]) {
            [[UAPush shared] addTagsToCurrentDevice:[[NSUserDefaults standardUserDefaults] objectForKey:beaconExitTagsKey]];
        }
        else {
            UALOG(@"No exit tags set for key %@", beaconExitTagsKey);
        }
    }
}

//checks NSUserDefaults for tags array at the key "ua-beaconmanager-<identifier>-entry-tags" and applies them if it exists
-(void)removeEntryTagsForBeaconRegion:(CLBeaconRegion *)beaconRegion {
    if (beaconRegion.identifier) {
        NSString *beaconEntryTagsKey = [NSString stringWithFormat:@"ua-beaconmanager-%@-entry-tags",beaconRegion.identifier];
        if ([[NSUserDefaults standardUserDefaults] objectForKey:beaconEntryTagsKey]){
            [[UAPush shared] removeTagsFromCurrentDevice:[[NSUserDefaults standardUserDefaults] objectForKey:beaconEntryTagsKey]];
        }
        else {
            UALOG(@"No exit tags set for key %@", beaconEntryTagsKey);
        }
    }
}

//just looks in NSUserDefaults for tags array at the key "ua-beaconmanager-<identifier>-exit-tags" and applies them if it exists
-(void)removeExitTagsForBeaconRegion:(CLBeaconRegion *)beaconRegion {
    if (beaconRegion.identifier) {
        NSString *beaconExitTagsKey = [NSString stringWithFormat:@"ua-beaconmanager-%@-exit-tags",beaconRegion.identifier];
        if ([[NSUserDefaults standardUserDefaults] objectForKey:beaconExitTagsKey]){
            [[UAPush shared] removeTagsFromCurrentDevice:[[NSUserDefaults standardUserDefaults] objectForKey:beaconExitTagsKey]];
        }
        else {
            UALOG(@"No exit tags set for key %@", beaconExitTagsKey);
        }
    }
}

//Getter that returns array of entry tags currently set for that beacon in NSUserDefaults
-(NSArray *)entryTagsForBeaconRegion:(CLBeaconRegion *)beaconRegion {
    if (beaconRegion.identifier) {
        //NSLog(@"timestamped exit");
        
        NSString *beaconEntryTagsKey = [NSString stringWithFormat:@"ua-beaconmanager-%@-entry-tags",beaconRegion.identifier];
        if ([[NSUserDefaults standardUserDefaults] objectForKey:beaconEntryTagsKey]) {
            return [[NSUserDefaults standardUserDefaults] objectForKey:beaconEntryTagsKey];
        }
        else {
            UALOG(@"No exit tags set for key %@", beaconEntryTagsKey);
        }
    }
    //probably want to return an empty array instead
    return nil;
}

//Getter that returns array of exit tags currently set for that beacon in NSUserDefaults
-(NSArray *)exitTagsForBeaconRegion:(CLBeaconRegion *)beaconRegion {
    if (beaconRegion.identifier) {
        //NSLog(@"timestamped exit");
        
        NSString *beaconExitTagsKey = [NSString stringWithFormat:@"ua-beaconmanager-%@-exit-tags",beaconRegion.identifier];
        if ([[NSUserDefaults standardUserDefaults] objectForKey:beaconExitTagsKey]){
            return [[NSUserDefaults standardUserDefaults] objectForKey:beaconExitTagsKey];
        }
        else{
            UALOG(@"No exit tags set for key %@", beaconExitTagsKey);
        }
    }
    return nil;
}

#pragma miscellaneous helpers

//helper method for checking if a specific beacon region is monitored
-(BOOL)isMonitored:(CLBeaconRegion *)beaconRegion {
    for (CLBeaconRegion *bRegion in [self.locationManager monitoredRegions]) {
        if ([bRegion.identifier isEqualToString:beaconRegion.identifier]) {
            return true;
        }
    }
    return false;
}

//returns a beacon from the ranged list given a identifier, else emits log and returns nil
-(CLBeacon *)beaconWithId:(NSString *)identifier {
    CLBeaconRegion *beaconRegion = [self beaconRegionWithId:identifier];
    NSMutableArray *beacons;
    //this lever of checking probably isn't completely necessary
    if ([_currentRangedBeacons objectForKey:identifier] && [[_currentRangedBeacons objectForKey:identifier] isKindOfClass:[NSMutableArray class]]) {
        beacons = [_currentRangedBeacons objectForKey:identifier];
        for (CLBeacon *beacon in beacons){
            if ([[beacon.proximityUUID UUIDString] isEqualToString:[beaconRegion.proximityUUID UUIDString]]) {
                return beacon;
            }
        }
    }
    //NSLog(@"No beacon available with this ID");
    //No beacon with the specified ID is within range
    return nil;
}

//returns a beacon regions from the available regions (all in plist) given an identifier
-(CLBeaconRegion *)beaconRegionWithId:(NSString *)identifier {
    for (CLBeaconRegion *beaconRegion in [[self listManager] availableBeaconRegionsList]){
        if ([beaconRegion.identifier isEqualToString:identifier]) {
            return beaconRegion;
        }
    }
    //No available beacon region with the specified ID was included in the available regions list
    return nil;
}

@end
