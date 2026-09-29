// Feeds the home screen widget: the tweak cannot share its SQLite with the extension, so it writes a
// small JSON into the App Group both sides are put on (extension/AppGroups) and asks WidgetKit to
// reload. Called after an import or an erase and whenever the app goes to the background.
#import "Stats.h"
#import "SGStatsStore.h"

// WidgetKit's WidgetCenter through the runtime: the header's ObjC surface has moved between SDKs.
static void reloadWidgets(void) {
    Class centerClass = NSClassFromString(@"WidgetCenter");
    if (!centerClass) return;
    id center = [centerClass performSelector:@selector(sharedCenter)];
    if ([center respondsToSelector:@selector(reloadAllTimelines)]) [center performSelector:@selector(reloadAllTimelines)];
}

void SGStatsWriteWidgetSummary(void) {
    NSURL *container = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:@"group.com.spotify.client.widget"];
    if (!container) return;

    int64_t now = (int64_t)NSDate.date.timeIntervalSince1970;
    SGStatsSummary *all = [SGStatsStore.shared summarySince:0];
    SGStatsSummary *week = [SGStatsStore.shared summarySince:now - 7 * 86400];
    SGStatsSummary *today = [SGStatsStore.shared summarySince:now - 86400];
    NSArray<SGStatsEntry *> *artists = [SGStatsStore.shared top:SGStatsEntityArtist order:SGStatsOrderMinutes since:0 until:0 limit:1];
    NSArray<SGStatsEntry *> *tracks = [SGStatsStore.shared top:SGStatsEntityTrack order:SGStatsOrderMinutes since:0 until:0 limit:1];

    NSDictionary *summary = @{
        @"allMs": @(all.ms),
        @"weekMs": @(week.ms),
        @"todayMs": @(today.ms),
        @"plays": @(all.plays),
        @"topArtist": artists.firstObject.name ?: @"",
        @"topTrack": tracks.firstObject.name ?: @"",
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:summary options:0 error:NULL];
    [data writeToURL:[container URLByAppendingPathComponent:@"spoti.pw-stats.json"] atomically:YES];

    reloadWidgets();
}
