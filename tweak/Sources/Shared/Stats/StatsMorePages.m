#import "Stats.h"
#import "SGStatsStore.h"
#import "SGStatsModel.h"
#import "SGStatsArtwork.h"
#import "Core/SGCore.h"
#import "Settings/SGPage.h"
#import "Settings/SGPageStyle.h"

static NSString *durationText(int64_t ms) {
    int64_t minutes = llround((double)ms / 60000.0);
    if (minutes < 60) return [NSString stringWithFormat:@"%lld min", minutes];
    return [NSString stringWithFormat:@"%lldh %lldm", minutes / 60, minutes % 60];
}

static NSString *countText(NSInteger count) {
    static NSNumberFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ formatter = [NSNumberFormatter new]; formatter.numberStyle = NSNumberFormatterDecimalStyle; });
    return [formatter stringFromNumber:@(count)];
}

static NSString *dateTimeText(int64_t ts, NSString *format) {
    static NSMutableDictionary<NSString *, NSDateFormatter *> *formatters;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ formatters = [NSMutableDictionary dictionary]; });
    NSDateFormatter *formatter = formatters[format];
    if (!formatter) { formatter = [NSDateFormatter new]; formatter.dateFormat = format; formatters[format] = formatter; }
    return [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:ts]];
}

static SGStatsEntry *entryForPlay(SGStatsPlay *play) {
    SGStatsEntry *entry = [SGStatsEntry new];
    entry.name = play.title;
    entry.subtitle = play.artist;
    entry.uri = play.trackURI;
    entry.artwork = play.artwork;
    return entry;
}

static void styleArtworkCell(UITableViewCell *cell, SGStatsEntry *entry, SGStatsEntity kind) {
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.imageView.contentMode = UIViewContentModeScaleAspectFill;
    cell.imageView.clipsToBounds = YES;
    cell.imageView.layer.cornerRadius = 6;
    [SGStatsArtwork fill:cell.imageView entry:entry kind:kind];
}

static UITableViewCell *artworkCell(UITableView *table, SGStatsEntry *entry, SGStatsEntity kind) {
    UITableViewCell *cell = [table dequeueReusableCellWithIdentifier:@"row"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"row"];
    cell.textLabel.text = entry.name;
    cell.detailTextLabel.text = entry.subtitle;
    styleArtworkCell(cell, entry, kind);
    return cell;
}

#pragma mark - recent history

@interface SGStatsHistoryPageController : SGPage
@end

@implementation SGStatsHistoryPageController {
    NSArray<NSString *> *_days;
    NSArray<NSArray<SGStatsPlay *> *> *_playsByDay;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Recent plays";
    NSArray<SGStatsPlay *> *plays = [SGStatsStore.shared recentLimit:400];
    NSMutableArray<NSString *> *days = [NSMutableArray array];
    NSMutableArray<NSArray<SGStatsPlay *> *> *groups = [NSMutableArray array];
    for (SGStatsPlay *play in plays) {
        NSString *day = dateTimeText(play.ts, @"EEEE d MMM yyyy");
        if (![days.lastObject isEqualToString:day]) { [days addObject:day]; [groups addObject:[NSMutableArray array]]; }
        [(NSMutableArray *)groups.lastObject addObject:play];
    }
    _days = days;
    _playsByDay = groups;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return _playsByDay.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return _playsByDay[section].count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return _days[section]; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SGStatsPlay *play = _playsByDay[indexPath.section][indexPath.row];
    UITableViewCell *cell = artworkCell(tableView, entryForPlay(play), SGStatsEntityTrack);
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@ · %@", play.artist ?: @"", dateTimeText(play.ts, @"HH:mm"), durationText(play.ms)];
    return cell;
}

@end

UIViewController *SGStatsHistoryPage(void) {
    return [SGStatsHistoryPageController new];
}

#pragma mark - listening clock

@interface SGStatsClockView : UIView
@property (nonatomic, copy) NSArray<NSNumber *> *cells;
@end

@implementation SGStatsClockView

- (void)setCells:(NSArray<NSNumber *> *)cells { _cells = cells; [self setNeedsDisplay]; }

- (void)drawRect:(CGRect)rect {
    NSArray<NSNumber *> *cells = self.cells;
    if (cells.count < 168) return;
    int64_t max = 1;
    for (NSNumber *cell in cells) if (cell.longLongValue > max) max = cell.longLongValue;

    CGFloat label = 30, top = 4;
    CGFloat width = (CGRectGetWidth(rect) - label) / 24.0;
    CGFloat height = (CGRectGetHeight(rect) - top - 16) / 7.0;
    NSArray<NSString *> *weekdays = @[@"Sun", @"Mon", @"Tue", @"Wed", @"Thu", @"Fri", @"Sat"];
    NSDictionary *labelAttrs = @{NSFontAttributeName: [UIFont systemFontOfSize:9], NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.5]};

    for (NSInteger weekday = 0; weekday < 7; weekday++) {
        [weekdays[weekday] drawAtPoint:CGPointMake(0, top + weekday * height + height / 2 - 5) withAttributes:labelAttrs];
        for (NSInteger hour = 0; hour < 24; hour++) {
            int64_t ms = cells[weekday * 24 + hour].longLongValue;
            CGFloat intensity = ms > 0 ? 0.15 + 0.85 * (CGFloat)ms / (CGFloat)max : 0.05;
            CGRect cellRect = CGRectMake(label + hour * width + 0.5, top + weekday * height + 0.5, width - 1, height - 1);
            [[UIColor colorWithWhite:1 alpha:intensity] setFill];
            [[UIBezierPath bezierPathWithRoundedRect:cellRect cornerRadius:2] fill];
        }
    }
    for (NSInteger hour = 0; hour < 24; hour += 3) {
        [([NSString stringWithFormat:@"%ld", (long)hour]) drawAtPoint:CGPointMake(label + hour * width, top + 7 * height + 2) withAttributes:labelAttrs];
    }
}

@end

@interface SGStatsClockPageController : SGPage
@end

@implementation SGStatsClockPageController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Listening clock";
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 260)];
    SGStatsClockView *clock = [[SGStatsClockView alloc] initWithFrame:CGRectInset(header.bounds, 16, 8)];
    clock.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    clock.cells = [SGStatsStore.shared clockSince:0];
    [header addSubview:clock];
    self.tableView.tableHeaderView = header;
}

@end

UIViewController *SGStatsClockPage(void) {
    return [SGStatsClockPageController new];
}

#pragma mark - discover

@interface SGStatsDiscoverPageController : SGPage
@end

@implementation SGStatsDiscoverPageController {
    SGStatsDiscover _kind;
    SGStatsEntity _entity;
    SGStatsRange _range;
    NSArray<SGStatsEntry *> *_entries;
}

- (instancetype)initWithKind:(SGStatsDiscover)kind entity:(SGStatsEntity)entity range:(SGStatsRange)range {
    if ((self = [super init])) { _kind = kind; _entity = entity; _range = range; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = _kind == SGStatsDiscoverOnRepeat ? @"On repeat" : (_kind == SGStatsDiscoverNew ? @"New this period" : @"Forgotten favourites");
    int64_t since = SGStatsRangeSince(_range);
    _entries = [SGStatsStore.shared discover:_kind entity:_entity since:since until:0 limit:100];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return _entries.count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @"Plays"; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SGStatsEntry *entry = _entries[indexPath.row];
    UITableViewCell *cell = artworkCell(tableView, entry, _entity);
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@%@ plays · %@",
                                 entry.subtitle.length ? [entry.subtitle stringByAppendingString:@" · "] : @"",
                                 countText(entry.plays), durationText(entry.ms)];
    return cell;
}

@end

UIViewController *SGStatsDiscoverPage(SGStatsDiscover kind, SGStatsEntity entity, SGStatsRange range) {
    return [[SGStatsDiscoverPageController alloc] initWithKind:kind entity:entity range:range];
}

#pragma mark - detail

@interface SGStatsDetailPageController : SGPage
@end

@implementation SGStatsDetailPageController {
    SGStatsEntry *_entry;
    SGStatsEntity _entity;
    NSArray<NSString *> *_labels;
    NSArray<NSString *> *_values;
}

- (instancetype)initWithEntry:(SGStatsEntry *)entry entity:(SGStatsEntity)entity {
    if ((self = [super init])) { _entry = entry; _entity = entity; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = _entry.name;

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 120)];
    UIImageView *art = [[UIImageView alloc] initWithFrame:CGRectMake(16, 12, 96, 96)];
    art.contentMode = UIViewContentModeScaleAspectFill;
    art.clipsToBounds = YES;
    art.layer.cornerRadius = 8;
    [SGStatsArtwork fill:art entry:_entry kind:_entity];
    [header addSubview:art];

    UILabel *name = [[UILabel alloc] initWithFrame:CGRectMake(124, 22, header.bounds.size.width - 140, 44)];
    name.numberOfLines = 2;
    name.font = [UIFont boldSystemFontOfSize:17];
    name.text = _entry.name;
    [header addSubview:name];
    UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(124, 70, header.bounds.size.width - 140, 20)];
    sub.font = [UIFont systemFontOfSize:13];
    sub.textColor = [UIColor colorWithWhite:1 alpha:0.6];
    sub.text = _entry.subtitle;
    [header addSubview:sub];
    self.tableView.tableHeaderView = header;

    double seconds = _entry.ms / 1000.0;
    double skipRate = _entry.plays ? (double)_entry.skips / (double)_entry.plays * 100.0 : 0;
    _labels = @[@"Plays", @"Minutes", @"Average", @"Skipped", @"First played", @"Last played"];
    _values = @[countText(_entry.plays),
                durationText(_entry.ms),
                _entry.plays ? [NSString stringWithFormat:@"%.1f min", seconds / 60.0 / _entry.plays] : @"—",
                _entry.plays ? [NSString stringWithFormat:@"%ld%%", (long)llround(skipRate)] : @"—",
                _entry.first ? dateTimeText(_entry.first, @"d MMM yyyy") : @"—",
                _entry.last ? dateTimeText(_entry.last, @"d MMM yyyy") : @"—"];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return _labels.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"stat"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"stat"];
    cell.textLabel.text = _labels[indexPath.row];
    cell.detailTextLabel.text = _values[indexPath.row];
    cell.imageView.image = nil;
    return cell;
}

@end

UIViewController *SGStatsDetailPage(SGStatsEntry *entry, SGStatsEntity entity) {
    return [[SGStatsDetailPageController alloc] initWithEntry:entry entity:entity];
}

#pragma mark - wrapped

static UIImage *wrappedImage(SGStatsEntity entity) {
    int64_t since = SGStatsRangeSince(SGStatsRangeYear);
    SGStatsSummary *summary = [SGStatsStore.shared summarySince:since];
    NSArray<SGStatsEntry *> *top = [SGStatsStore.shared top:entity order:SGStatsOrderMinutes since:since until:0 limit:5];

    CGSize size = CGSizeMake(640, 900);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGContextRef ctx = context.CGContext;
        [[UIColor colorWithRed:0.05 green:0.05 blue:0.06 alpha:1] setFill];
        CGContextFillRect(ctx, CGRectMake(0, 0, size.width, size.height));
        [[UIColor systemGreenColor] setFill];
        CGContextFillRect(ctx, CGRectMake(0, 0, size.width, 8));

        NSDictionary *titleAttrs = @{NSFontAttributeName: [UIFont boldSystemFontOfSize:40], NSForegroundColorAttributeName: UIColor.whiteColor};
        NSDictionary *subAttrs = @{NSFontAttributeName: [UIFont systemFontOfSize:22], NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.7]};
        NSDictionary *rowAttrs = @{NSFontAttributeName: [UIFont systemFontOfSize:26], NSForegroundColorAttributeName: UIColor.whiteColor};

        [@"Your year in music" drawAtPoint:CGPointMake(40, 60) withAttributes:titleAttrs];
        [([NSString stringWithFormat:@"%@ · %@ plays · %@", durationText(summary.ms), countText(summary.plays), SGStatsEntityName(entity).lowercaseString]) drawAtPoint:CGPointMake(40, 116) withAttributes:subAttrs];

        CGFloat y = 200;
        for (NSInteger i = 0; i < (NSInteger)top.count; i++) {
            SGStatsEntry *entry = top[i];
            NSString *line = [NSString stringWithFormat:@"%ld.  %@", (long)(i + 1), entry.name];
            [line drawAtPoint:CGPointMake(40, y) withAttributes:rowAttrs];
            [([NSString stringWithFormat:@"      %@ plays · %@", countText(entry.plays), durationText(entry.ms)]) drawAtPoint:CGPointMake(40, y + 32) withAttributes:subAttrs];
            y += 100;
        }
        [@"spoti.pw" drawAtPoint:CGPointMake(40, size.height - 60) withAttributes:subAttrs];
    }];
}

void SGStatsShareWrapped(UIViewController *owner, SGStatsEntity entity) {
    UIImage *image = wrappedImage(entity);
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[image] applicationActivities:nil];
    share.popoverPresentationController.sourceView = owner.view;
    [owner presentViewController:share animated:YES completion:nil];
}
