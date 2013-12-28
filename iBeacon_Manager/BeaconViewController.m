//
//  BeaconView.m
//  UABeacons
//
//  Created by David Crow on 10/3/13.
//  Copyright (c) 2013 David Crow. All rights reserved.
//

#import "BeaconViewController.h"
#import "BeaconSettingsViewController.h"
//remove this after debugging
#import "PlistManager.h"

@interface BeaconViewController ()

@end

@implementation BeaconViewController
{
    NSMutableDictionary *beacons;
    CLBeaconRegion *selectedBeaconRegion;
    CLBeacon *selectedBeacon;
    UIImage *whiteMarker;
    UIImage *greenMarker;
    int refreshCount;
}

- (id)initWithStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:style];
    if (self) {
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    //Load the available managed beacon regions and update monitored regions
    [[BeaconRegionManager shared] loadAvailableRegions];
    [[BeaconRegionManager shared] loadMonitoredRegions];

    //Initialize reused tableview images
    greenMarker = [[UIImage alloc] init];
    greenMarker = [UIImage imageWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"722-location-ping@2x" ofType:@"png"]];
    
    whiteMarker = [[UIImage alloc] init];
    whiteMarker = [UIImage imageWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"722-location-pin@2x" ofType:@"png"]];
    
    //register for ranging beacons notification
    [[NSNotificationCenter defaultCenter]
     addObserver:self
     selector:@selector(managerDidRangeBeacons)
     name:@"managerDidRangeBeacons"
     object:nil];
    
    refreshCount = 0;
}

- (void)managerDidRangeBeacons
{
    //reloads every 3 seconds for better responsiveness w/o table view jerk
    if (refreshCount > 2){
        refreshCount = 0;
        [self.tableView reloadData];
    }
    refreshCount++;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{

    int sections = 1;
    return sections;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [[BeaconRegionManager shared] availableManagedBeaconRegionsList].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"BeaconCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier forIndexPath:indexPath];
    
 
    NSArray *availableManagedBeaconRegionsList = [[BeaconRegionManager shared] availableManagedBeaconRegionsList]; //[NSArray arrayWithArray:[[[BeaconRegionManager shared] monitoredBeaconRegions] allObjects]];
    
    selectedBeaconRegion = availableManagedBeaconRegionsList[indexPath.row];
    selectedBeacon = [[BeaconRegionManager shared] beaconWithId:selectedBeaconRegion.identifier];
    
    // Configure the cell...
    if (cell == nil)
	{
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellIdentifier];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
	}
    
    [cell.textLabel setText:selectedBeaconRegion.identifier];
    
    //iBeacon is in range
    if ([selectedBeacon accuracy] > 0)
    {
        cell.imageView.image = greenMarker;
    }
    //iBeacon has been seen, but has gone out of range
    else if ([selectedBeacon accuracy] == -1)
    {
        //fade green marker to white
        [UIView animateWithDuration:1.0 delay:0.f options:UIViewAnimationOptionRepeat | UIViewAnimationOptionAutoreverse
                         animations:^{
                             cell.imageView.image = whiteMarker;
                         } completion:^(BOOL finished){
                             cell.imageView.alpha=1.f;
                         }];
    }
    //iBeacon has never been seen
    else{
        cell.imageView.image = whiteMarker;
    }
    
    cell.detailTextLabel.text = [NSString stringWithFormat:@"UUID: %@\nMajor: %@\nMinor: %@\n", [selectedBeaconRegion.proximityUUID UUIDString], selectedBeaconRegion.major ? selectedBeaconRegion.major : @"None", selectedBeaconRegion.minor ? selectedBeaconRegion.minor : @"None"];
    
    return cell;
}

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    //NOTE setting the selected beacon region and selected beacon in this way will cause issue if IDs are not unique
    selectedBeaconRegion = [[BeaconRegionManager shared] beaconRegionWithId:cell.textLabel.text];
    selectedBeacon = [[BeaconRegionManager shared] beaconWithId:cell.textLabel.text];
    [self performSegueWithIdentifier:@"beaconSettings" sender:self];
    
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    // Make sure your segue name in storyboard is the same as this line
    if ([[segue identifier] isEqualToString:@"beaconSettings"])
    {
        // Get reference to the destination view controller
        BeaconSettingsViewController *vc = [segue destinationViewController];

        vc.beaconRegion = selectedBeaconRegion;
        vc.beacon = selectedBeacon;
    }
}

@end
