#import "Stats.h"
#import "SGStatsModel.h"
#import "SGStatsStore.h"
#import "SGStatsLog.h"
#import "Settings/SGPage.h"

static NSString *durationText(int64_t ms) {
    int64_t minutes = llround((double)ms / 60000.0);
    if (minutes < 60) return [NSString stringWithFormat:@"%lld min", minutes];
    return [NSString stringWithFormat:@"%lldh %lldm", minutes / 60, minutes % 60];
}

static NSString *dateSpan(int64_t since) {
    int64_t first = [SGStatsStore.shared earliestTsSince:since];
    int64_t last = [SGStatsStore.shared latestTsSince:since];
    if (!first) return @"No plays in this range";
    static NSDateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [NSDateFormatter new];
        formatter.dateFormat = @"d MMM yyyy";
    });
    return [NSString stringWithFormat:@"%@ – %@",
            [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:first]],
            [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:last]]];
}

static NSString *countText(NSInteger count) {
    static NSNumberFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ formatter = [NSNumberFormatter new]; formatter.numberStyle = NSNumberFormatterDecimalStyle; });
    return [formatter stringFromNumber:@(count)];
}

#pragma mark - chart

@interface SGStatsChartView : UIView
@property (nonatomic, copy) NSArray<SGStatsDay *> *days;
@end

@implementation SGStatsChartView

- (void)setDays:(NSArray<SGStatsDay *> *)days {
    _days = days;
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    NSArray<SGStatsDay *> *days = self.days;
    if (days.count < 2) return;
    int64_t max = 1;
    for (SGStatsDay *day in days) if (day.ms > max) max = day.ms;
    CGFloat gap = 2, width = (CGRectGetWidth(rect) - gap * (days.count - 1)) / days.count;
    [[UIColor colorWithWhite:1 alpha:0.85] setFill];
    for (NSInteger i = 0; i < (NSInteger)days.count; i++) {
        CGFloat height = MAX(2, CGRectGetHeight(rect) * (CGFloat)days[i].ms / (CGFloat)max);
        CGRect bar = CGRectMake(i * (width + gap), CGRectGetHeight(rect) - height, width, height);
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:bar cornerRadius:MIN(3, width / 2)];
        [path fill];
    }
}

@end

#pragma mark - artwork cache

// Artwork for a row. A track's picture is the album cover, so an album gets the picture of any track
// on it, and an artist gets theirs through a track's embed page, which carries the artist URI the
// import never has; the public oEmbed endpoint answers with the picture for a URI of any kind. What
// is found is remembered, so a row is fetched once.
@interface SGStatsArtwork : NSObject
+ (void)fill:(UIImageView *)view entry:(SGStatsEntry *)entry kind:(SGStatsEntity)kind;
@end

@implementation SGStatsArtwork

+ (UIImage *)tileFor:(NSString *)name {
    static NSMutableDictionary<NSString *, UIImage *> *tiles;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ tiles = [NSMutableDictionary dictionary]; });
    NSString *letter = name.length ? [[name substringToIndex:1] uppercaseString] : @"?";
    NSString *key = [NSString stringWithFormat:@"%@|%ld", letter, (long)(name.hash % 6)];
    UIImage *cached = tiles[key];
    if (cached) return cached;
    static NSArray<UIColor *> *colors;
    static dispatch_once_t colorsOnce;
    dispatch_once(&colorsOnce, ^{
        colors = @[[UIColor systemPinkColor], [UIColor systemPurpleColor], [UIColor systemBlueColor],
                   [UIColor systemTealColor], [UIColor systemGreenColor], [UIColor systemOrangeColor]];
    });
    CGSize size = CGSizeMake(44, 44);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    [[colors[(NSUInteger)(name.hash % colors.count)] colorWithAlphaComponent:0.85] setFill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, size.width, size.height) cornerRadius:6] fill];
    NSDictionary *attributes = @{NSFontAttributeName: [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold],
                                 NSForegroundColorAttributeName: UIColor.whiteColor};
    CGSize text = [letter sizeWithAttributes:attributes];
    [letter drawAtPoint:CGPointMake((size.width - text.width) / 2, (size.height - text.height) / 2) withAttributes:attributes];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    tiles[key] = image;
    return image;
}

static NSCache<NSString *, UIImage *> *imageCache(void) {
    static NSCache<NSString *, UIImage *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; });
    return cache;
}

static NSString *const kThumbs = @"spotifyglass.stats.thumb";
static NSString *const kAlbumThumbs = @"spotifyglass.stats.albumthumb.v2";
static NSString *const kArtistThumbs = @"spotifyglass.stats.artistthumb";
static NSString *const kArtistURIs = @"spotifyglass.stats.artisturi";

static NSString *persistGet(NSString *map, NSString *key) {
    NSDictionary *stored = [NSUserDefaults.standardUserDefaults dictionaryForKey:map];
    id value = stored[key];
    return [value isKindOfClass:NSString.class] ? value : nil;
}

static void persistSet(NSString *map, NSString *key, NSString *value) {
    if (!key.length || !value.length) return;
    NSDictionary *stored = [NSUserDefaults.standardUserDefaults dictionaryForKey:map];
    NSMutableDictionary *dict = stored ? [stored mutableCopy] : [NSMutableDictionary dictionary];
    dict[key] = value;
    [NSUserDefaults.standardUserDefaults setObject:dict forKey:map];
}

static NSString *webURLForURI(NSString *uri) {
    NSArray<NSString *> *parts = [uri componentsSeparatedByString:@":"];
    if (parts.count == 3 && [parts[0] isEqualToString:@"spotify"]) return [NSString stringWithFormat:@"https://open.spotify.com/%@/%@", parts[1], parts[2]];
    if ([uri hasPrefix:@"http"]) return uri;
    return nil;
}

static id dictValue(id object, NSString *key) {
    return [object isKindOfClass:NSDictionary.class] ? ((NSDictionary *)object)[key] : nil;
}

+ (void)load:(NSString *)url into:(UIImageView *)view token:(NSString *)token {
    if (!url.length) return;
    UIImage *cached = [imageCache() objectForKey:url];
    if (cached) { if ([view.accessibilityIdentifier isEqualToString:token]) view.image = cached; return; }
    NSURL *address = [NSURL URLWithString:url];
    if (!address) return;
    [[NSURLSession.sharedSession dataTaskWithURL:address completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        UIImage *image = data ? [UIImage imageWithData:data] : nil;
        if (!image) return;
        [imageCache() setObject:image forKey:url];
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([view.accessibilityIdentifier isEqualToString:token]) view.image = image;
        });
    }] resume];
}

+ (void)thumbForURI:(NSString *)uri completion:(void (^)(NSString *thumb))completion {
    if (!uri.length) { completion(nil); return; }
    NSString *cached = persistGet(kThumbs, uri);
    if (cached.length) { completion(cached); return; }
    NSString *web = webURLForURI(uri);
    if (!web) { completion(nil); return; }
    NSURLComponents *components = [NSURLComponents componentsWithString:@"https://open.spotify.com/oembed"];
    components.queryItems = @[[NSURLQueryItem queryItemWithName:@"url" value:web]];
    [[NSURLSession.sharedSession dataTaskWithURL:components.URL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        NSString *thumb = [json isKindOfClass:NSDictionary.class] ? json[@"thumbnail_url"] : nil;
        if (![thumb isKindOfClass:NSString.class] || !thumb.length) {
            SGStatsLogLine(@"oembed: no thumbnail for %@", uri);
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
            return;
        }
        persistSet(kThumbs, uri, thumb);
        dispatch_async(dispatch_get_main_queue(), ^{ completion(thumb); });
    }] resume];
}

// The track's embed page carries its artists' URIs, which an imported play has no other way to get.
+ (void)artistURIForTrack:(NSString *)trackURI name:(NSString *)artistName completion:(void (^)(NSString *uri))completion {
    NSString *cached = persistGet(kArtistURIs, artistName.lowercaseString);
    if (cached.length) { completion(cached); return; }
    NSString *web = webURLForURI(trackURI);
    if (!web) { completion(nil); return; }
    NSURL *embed = [NSURL URLWithString:[web stringByReplacingOccurrencesOfString:@"open.spotify.com/track/" withString:@"open.spotify.com/embed/track/"]];
    if (!embed) { completion(nil); return; }
    [[NSURLSession.sharedSession dataTaskWithURL:embed completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSString *html = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
        NSRange start = html ? [html rangeOfString:@"<script id=\"__NEXT_DATA__\" type=\"application/json\">"] : NSMakeRange(NSNotFound, 0);
        NSRange end = start.location == NSNotFound ? NSMakeRange(NSNotFound, 0) : [html rangeOfString:@"</script>" options:0 range:NSMakeRange(NSMaxRange(start), html.length - NSMaxRange(start))];
        NSDictionary *root = nil;
        if (start.location != NSNotFound && end.location != NSNotFound) {
            NSString *json = [html substringWithRange:NSMakeRange(NSMaxRange(start), end.location - NSMaxRange(start))];
            id parsed = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
            root = [parsed isKindOfClass:NSDictionary.class] ? parsed : nil;
        }
        id entity = dictValue(dictValue(dictValue(dictValue(dictValue(root, @"props"), @"pageProps"), @"state"), @"data"), @"entity");
        NSArray *artists = dictValue(entity, @"artists");
        NSString *match = nil, *fallback = nil;
        for (id item in [artists isKindOfClass:NSArray.class] ? artists : @[]) {
            NSString *name = dictValue(item, @"name"), *uri = dictValue(item, @"uri");
            if (![uri isKindOfClass:NSString.class]) continue;
            if (!fallback) fallback = uri;
            if ([name isKindOfClass:NSString.class] && [name caseInsensitiveCompare:artistName] == NSOrderedSame) { match = uri; break; }
        }
        NSString *resolved = match ?: fallback;
        if (resolved) persistSet(kArtistURIs, artistName.lowercaseString, resolved);
        dispatch_async(dispatch_get_main_queue(), ^{ completion(resolved); });
    }] resume];
}

+ (void)fill:(UIImageView *)view entry:(SGStatsEntry *)entry kind:(SGStatsEntity)kind {
    NSString *token = entry.uri.length ? entry.uri : entry.name;
    view.accessibilityIdentifier = token ?: @"";
    view.image = [self tileFor:entry.name];
    if (entry.artwork.length) { [self load:entry.artwork into:view token:token]; return; }

    if (kind == SGStatsEntityTrack) {
        [self thumbForURI:entry.uri completion:^(NSString *thumb) {
            if (thumb.length) [self load:thumb into:view token:token];
        }];
        return;
    }

    NSString *key = entry.name.lowercaseString;
    if (kind == SGStatsEntityAlbum) {
        NSString *cached = persistGet(kAlbumThumbs, key);
        if (cached.length) { [self load:cached into:view token:token]; return; }
        NSString *source = entry.uri.length ? entry.uri : [SGStatsStore.shared anyTrackURIForAlbum:entry.name artist:entry.subtitle];
        [self thumbForURI:source completion:^(NSString *thumb) {
            if (!thumb.length) return;
            persistSet(kAlbumThumbs, key, thumb);
            [self load:thumb into:view token:token];
        }];
        return;
    }

    NSString *cached = persistGet(kArtistThumbs, key);
    if (cached.length) { [self load:cached into:view token:token]; return; }
    if (entry.uri.length) {
        [self thumbForURI:entry.uri completion:^(NSString *thumb) {
            if (!thumb.length) return;
            persistSet(kArtistThumbs, key, thumb);
            [self load:thumb into:view token:token];
        }];
        return;
    }
    NSString *track = [SGStatsStore.shared anyTrackURIForArtist:entry.name];
    if (!track.length) return;
    [self artistURIForTrack:track name:entry.name completion:^(NSString *artistURI) {
        if (!artistURI.length) return;
        [self thumbForURI:artistURI completion:^(NSString *thumb) {
            if (!thumb.length) return;
            persistSet(kArtistThumbs, key, thumb);
            [self load:thumb into:view token:token];
        }];
    }];
}

@end

#pragma mark - page

@interface SGStatsPageController : SGPage
@end

@implementation SGStatsPageController {
    UISegmentedControl *_rangeControl, *_entityControl;
    UILabel *_summary;
    SGStatsChartView *_chart;
    NSArray<SGStatsEntry *> *_entries;
    SGStatsRange _range;
    SGStatsEntity _entity;
    NSInteger _generation;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Stats";
    _range = SGStatsRangeLifetime;
    _entity = SGStatsEntityTrack;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] style:UIBarButtonItemStylePlain target:self action:@selector(openSettings)];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload) name:SGStatsChangedNotification object:nil];
    [self buildHeader];
    [self reload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (void)openSettings {
    SGShowPage(self, SGStatsSettingsPage());
}

- (void)buildHeader {
    UIView *header = [UIView new];

    NSArray<NSString *> *ranges = @[@"24h", @"Week", @"4W", @"6M", @"Year", @"All"];
    _rangeControl = [[UISegmentedControl alloc] initWithItems:ranges];
    _rangeControl.selectedSegmentIndex = _range;
    [_rangeControl addTarget:self action:@selector(changed) forControlEvents:UIControlEventValueChanged];
    [_rangeControl.heightAnchor constraintEqualToConstant:32].active = YES;

    _entityControl = [[UISegmentedControl alloc] initWithItems:@[@"Tracks", @"Albums", @"Artists"]];
    _entityControl.selectedSegmentIndex = _entity;
    [_entityControl addTarget:self action:@selector(changed) forControlEvents:UIControlEventValueChanged];
    [_entityControl.heightAnchor constraintEqualToConstant:32].active = YES;

    _summary = [UILabel new];
    _summary.numberOfLines = 3;
    _summary.font = [UIFont systemFontOfSize:15];
    _summary.textColor = [UIColor colorWithWhite:1 alpha:0.7];

    _chart = [SGStatsChartView new];
    _chart.backgroundColor = UIColor.clearColor;
    [_chart.heightAnchor constraintEqualToConstant:100].active = YES;

    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    for (UIView *view in @[_rangeControl, _entityControl, _summary, _chart]) [stack addArrangedSubview:view];
    [header addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:header.topAnchor constant:8],
        [stack.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],
        [stack.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-12],
    ]];

    self.tableView.tableHeaderView = header;
}

// The header is a table header view, so its frame has to be given the table's width before it can
// size itself; without it the stack lays out against a zero width and sits off screen.
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIView *header = self.tableView.tableHeaderView;
    if (!header) return;
    CGFloat width = self.tableView.bounds.size.width;
    CGSize size = [header systemLayoutSizeFittingSize:CGSizeMake(width, 0)
                     withHorizontalFittingPriority:UILayoutPriorityRequired
                           verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    if (fabs(header.frame.size.width - width) > 0.5 || fabs(header.frame.size.height - size.height) > 0.5) {
        header.frame = CGRectMake(0, 0, width, size.height);
        self.tableView.tableHeaderView = header;
    }
}

- (void)changed {
    _range = (SGStatsRange)_rangeControl.selectedSegmentIndex;
    _entity = (SGStatsEntity)_entityControl.selectedSegmentIndex;
    [self reload];
}

- (void)reload {
    int64_t since = SGStatsRangeSince(_range);
    _entries = [SGStatsStore.shared top:_entity order:SGStatsOrderPlays since:since limit:100];
    SGStatsSummary *summary = [SGStatsStore.shared summarySince:since];
    _summary.text = [NSString stringWithFormat:@"%@ · %@ plays\n%@ tracks · %@ albums · %@ artists\n%@",
                     durationText(summary.ms), countText(summary.plays),
                     countText(summary.tracks), countText(summary.albums), countText(summary.artists),
                     dateSpan(since)];
    _chart.days = [SGStatsStore.shared dailySince:since];
    [self.tableView reloadData];
}

#pragma mark - table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _entries.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (!_entries.count) return nil;
    return [NSString stringWithFormat:@"Top %@", SGStatsEntityName(_entity).lowercaseString];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"entry"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"entry"];
    SGStatsEntry *entry = _entries[indexPath.row];
    cell.textLabel.text = [NSString stringWithFormat:@"%ld. %@", (long)(indexPath.row + 1), entry.name];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@%@ plays · %@", entry.subtitle.length ? [entry.subtitle stringByAppendingString:@" · "] : @"", countText(entry.plays), durationText(entry.ms)];
    cell.imageView.contentMode = UIViewContentModeScaleAspectFill;
    cell.imageView.clipsToBounds = YES;
    cell.imageView.layer.cornerRadius = 6;
    [SGStatsArtwork fill:cell.imageView entry:entry kind:_entity];
    return cell;
}

@end

UIViewController *SGStatsPage(void) {
    return [SGStatsPageController new];
}
