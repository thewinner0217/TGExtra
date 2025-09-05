#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import "Icons.h"
#import "Headers.h"

#define TGLoc(key) [TGExtraLocalization localizedStringForKey:(key)]
#define kEnableScheduledMessages @"enableScheduledMessages"

@interface TGExtra ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSString *cacheSize;
@end

@implementation TGExtra

- (void)viewDidLoad {
    [self setupTableView];
    [self setupIconAsHeader];
    [self setupApplyButton];
    [self setupNavigationTitleWithIcon];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didChangeLanguage)
                                                 name:@"LanguageChangedNotification"
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didChangeFakeLocation)
                                                 name:@"TGExtraLocationChanged"
                                               object:nil];
}

- (void)didChangeLanguage {
    [self.tableView reloadData];
}

- (void)didChangeFakeLocation {
    NSIndexSet *section = [NSIndexSet indexSetWithIndex:4];
    [self.tableView reloadSections:section withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;

    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

// Nuovo metodo per titolo con icona a destra
- (void)setupNavigationTitleWithIcon {
    UIView *titleView = [[UIView alloc] init];
    titleView.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"TGExtra FE";
    titleLabel.font = [UIFont boldSystemFontOfSize:17];
    titleLabel.textColor = [UIColor labelColor];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    NSData *imageData = [[NSData alloc] initWithBase64EncodedString:GHOSTPNG options:NSDataBase64DecodingIgnoreUnknownCharacters];
    UIImage *icon = [UIImage imageWithData:imageData scale:[UIScreen mainScreen].scale];

    UIImageView *iconView = [[UIImageView alloc] initWithImage:icon];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.translatesAutoresizingMaskIntoConstraints = NO;

    [titleView addSubview:titleLabel];
    [titleView addSubview:iconView];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.leadingAnchor constraintEqualToAnchor:titleView.leadingAnchor],
        [titleLabel.centerYAnchor constraintEqualToAnchor:titleView.centerYAnchor],

        [iconView.leadingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor constant:1],
        [iconView.trailingAnchor constraintEqualToAnchor:titleView.trailingAnchor],
        [iconView.centerYAnchor constraintEqualToAnchor:titleLabel.centerYAnchor],
    ]];

    [titleView.widthAnchor constraintEqualToConstant:140].active = YES;
    [titleView.heightAnchor constraintEqualToConstant:24].active = YES;

    self.navigationItem.titleView = titleView;
}

- (void)setupIconAsHeader {
    UIView *logoContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.frame.size.width, 100)];

    // Logo Image
    NSData *imageData = [[NSData alloc] initWithBase64EncodedString:TW02PNG options:NSDataBase64DecodingIgnoreUnknownCharacters];
    UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage imageWithData:imageData]];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.layer.cornerRadius = 100 / 4;
    iconView.userInteractionEnabled = YES;
    iconView.clipsToBounds = YES;
    iconView.contentMode = UIViewContentModeScaleAspectFill;

    [logoContainer addSubview:iconView];

    [NSLayoutConstraint activateConstraints:@[
        [iconView.centerYAnchor constraintEqualToAnchor:logoContainer.centerYAnchor],
        [iconView.centerXAnchor constraintEqualToAnchor:logoContainer.centerXAnchor],
        [iconView.widthAnchor constraintEqualToConstant:100],
        [iconView.heightAnchor constraintEqualToConstant:100]
    ]];

    self.tableView.tableHeaderView = logoContainer;
}

- (void)setupApplyButton {
    UIButton *applyChangesButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *applyImage = [UIImage systemImageNamed:@"checkmark.square"];
    applyImage = [applyImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    applyChangesButton.tintColor = [UIColor systemPinkColor];
    [applyChangesButton setImage:applyImage forState:UIControlStateNormal];
    [applyChangesButton addTarget:self action:@selector(applyChanges) forControlEvents:UIControlEventTouchUpInside];
    UIBarButtonItem *applyButtonItem = [[UIBarButtonItem alloc] initWithCustomView:applyChangesButton];
    self.navigationItem.rightBarButtonItems = @[applyButtonItem];
}

- (void)applyChanges {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:TGLoc(@"APPLY")
                                                                   message:TGLoc(@"APPLY_CHANGES")
                                                            preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *okAction = [UIAlertAction actionWithTitle:TGLoc(@"OK")
                                                       style:UIAlertActionStyleDefault
                                                     handler:^(UIAlertAction * _Nonnull action) {
        [[UIApplication sharedApplication] performSelector:@selector(suspend)];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            exit(0);
        });
    }];

    [alert addAction:okAction];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:TGLoc(@"CANCEL")
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];
    [alert addAction:cancelAction];
    [self presentViewController:alert animated:YES completion:nil];
}

- (UIColor *)dynamicColorBW {
    static dispatch_once_t token;
    static UIColor *cached;
    dispatch_once(&token, ^{
        cached = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
            if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) {
                return [UIColor whiteColor];
            } else {
                return [UIColor blackColor];
            }
        }];
    });
    return cached;
}

# pragma mark - UITableViewDataSource

typedef NS_ENUM(NSInteger, TABLE_VIEW_SECTIONS) {
    FE_OPTIONS = 0,
    GHOST_MODE = 1,
    READ_RECEIPT = 2,
    MISC = 3,
    FILE_FIXER = 4,
    FAKE_LOCATION = 5,
    LANGUAGE = 6,
    CREDITS = 7,
};

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 8;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case FE_OPTIONS: return 1;
        case GHOST_MODE: return 17;
        case READ_RECEIPT: return 2;
        case MISC: return 2;
        case FILE_FIXER: return 2;
        case FAKE_LOCATION: return 2;
        case LANGUAGE: return 1;
        case CREDITS: return 2;
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case FE_OPTIONS: return @"FE OPTIONS";
        case GHOST_MODE: return TGLoc(@"GHOST_MODE_SECTION_HEADER");
        case READ_RECEIPT: return TGLoc(@"READ_RECEIPT_SECTION_HEADER");
        case MISC: return TGLoc(@"MISC_SECTION_HEADER");
        case FILE_FIXER: return TGLoc(@"FILE_FIXER_SECTION_HEADER");
        case FAKE_LOCATION: return TGLoc(@"FAKE_LOCATION_SECTION_HEADER");
        case LANGUAGE: return TGLoc(@"LANGUAGE_SECTION_HEADER");
        case CREDITS: return TGLoc(@"CREDITS_SECTION_HEADER");
        default: return nil;
    }
}

- (UITableViewCell *)switchCellFromTableView:(UITableView *)tableView {
    UITableViewCell *switchCell = [tableView dequeueReusableCellWithIdentifier:@"switchCell"];
    if (!switchCell) {
        switchCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"switchCell"];
    }
    return switchCell;
}

- (UITableViewCell *)normalCellFromTableView:(UITableView *)tableView {
    UITableViewCell *normalCell = [tableView dequeueReusableCellWithIdentifier:@"normalCell"];
    if (!normalCell) {
        normalCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"normalCell"];
    }
    return normalCell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell;

    // ======= FE OPTIONS (Scheduled Messages) =======
    if (indexPath.section == FE_OPTIONS) {
        cell = [self switchCellFromTableView:tableView];
        cell.imageView.image = nil;

        if (indexPath.row == 0) {
            cell.textLabel.text = TGLoc(@"ENABLE_SCHEDULED_MESSAGES_TITLE");
            cell.detailTextLabel.text = TGLoc(@"ENABLE_SCHEDULED_MESSAGES_SUBTITLE");

            cell.textLabel.numberOfLines = 0;
            cell.detailTextLabel.numberOfLines = 0;

            UISwitch *toggle = [[UISwitch alloc] init];
            toggle.on = [[NSUserDefaults standardUserDefaults] boolForKey:kEnableScheduledMessages];
            [toggle removeTarget:nil action:NULL forControlEvents:UIControlEventValueChanged];
            [toggle addTarget:self action:@selector(toggleAutoSchedule:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
        }
        return cell;
    }

    // ======= ALTRE SEZIONI =======
    cell = [self normalCellFromTableView:tableView];
    cell.textLabel.text = @"Other Cell";
    cell.detailTextLabel.text = @"Subtitle";
    return cell;
}

#pragma mark - Scheduled Messages Toggle

- (void)toggleAutoSchedule:(UISwitch *)sender {
    [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:kEnableScheduledMessages];
    [[NSUserDefaults standardUserDefaults] synchronize];
    NSLog(@"Scheduled Messages %@", sender.isOn ? @"Enabled" : @"Disabled");
}

@end
