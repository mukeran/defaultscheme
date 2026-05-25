#import "DSSettingsViewController.h"

@interface DSSettingsViewController ()
@end

@implementation DSSettingsViewController

- (instancetype)initWithRecordsMatchedOnly:(BOOL)recordsMatchedOnly {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _recordsMatchedOnly = recordsMatchedOnly;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Settings";
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"DSSettingsCell"];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @"Log";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DSSettingsCell" forIndexPath:indexPath];
    UIListContentConfiguration *content = [UIListContentConfiguration cellConfiguration];
    content.text = @"Only Record Matched Rules";
    cell.contentConfiguration = content;

    UISwitch *toggle = [[UISwitch alloc] initWithFrame:CGRectZero];
    toggle.on = self.recordsMatchedOnly;
    [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = toggle;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (void)toggleChanged:(UISwitch *)sender {
    self.recordsMatchedOnly = sender.isOn;
    if (self.saveHandler) {
        self.saveHandler(self.recordsMatchedOnly);
    }
    [self.tableView reloadData];
}

@end
