#import "Stats.h"
#import "SGStatsStore.h"
#import "SGStatsImport.h"
#import "SGStatsLog.h"
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <UserNotifications/UserNotifications.h>

static NSString *historyRange(void);

static NSString *countText(NSInteger count) {
    static NSNumberFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ formatter = [NSNumberFormatter new]; formatter.numberStyle = NSNumberFormatterDecimalStyle; });
    return [formatter stringFromNumber:@(count)];
}

static NSString *durationText(int64_t ms) {
    int64_t minutes = llround((double)ms / 60000.0);
    if (minutes < 60) return [NSString stringWithFormat:@"%lld min", minutes];
    return [NSString stringWithFormat:@"%lldh %lldm", minutes / 60, minutes % 60];
}

#pragma mark - import

// The document picker's delegate is held weakly, so one of these stays alive across the import.
@interface SGStatsImportUI : NSObject <UIDocumentPickerDelegate>
+ (instancetype)shared;
- (void)present;
@end

@implementation SGStatsImportUI

+ (instancetype)shared {
    static SGStatsImportUI *ui;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ ui = [SGStatsImportUI new]; });
    return ui;
}

- (void)present {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeZIP, UTTypeJSON] asCopy:NO];
    picker.allowsMultipleSelection = YES;
    picker.delegate = self;
    [SGTopController() presentViewController:picker animated:YES completion:nil];
}

// A multi-year export is tens of thousands of rows across a ZIP; unpacking and inserting it on the
// main thread is a hang the watchdog kills, so it runs on a utility queue and only the answer comes
// back. The picker's security scope is opened on the main thread and held for that queue.
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    for (NSURL *url in urls) [url startAccessingSecurityScopedResource];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSInteger added = 0;
        NSError *error = nil;
        for (NSURL *url in urls) added += [SGStatsImporter importFileAtURL:url error:&error];
        for (NSURL *url in urls) [url stopAccessingSecurityScopedResource];
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter postNotificationName:SGStatsChangedNotification object:nil];
            NSString *message = added ? [NSString stringWithFormat:@"Added %ld plays.\nTotal %ld, history %@.",
                                                                (long)added, (long)SGStatsStore.shared.playCount, historyRange()]
                                      : (error.localizedDescription ?: @"No plays found in that file.");
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Import finished" message:message preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [SGTopController() presentViewController:alert animated:YES completion:nil];
        });
    });
}

@end

#pragma mark - restore

@interface SGStatsRestoreUI : NSObject <UIDocumentPickerDelegate>
+ (instancetype)shared;
- (void)present;
@end

@implementation SGStatsRestoreUI

+ (instancetype)shared {
    static SGStatsRestoreUI *ui;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ ui = [SGStatsRestoreUI new]; });
    return ui;
}

- (void)present {
    UTType *sqlite = [UTType typeWithFilenameExtension:@"sqlite"] ?: UTTypeDatabase;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[sqlite] asCopy:YES];
    picker.delegate = self;
    [SGTopController() presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSString *path = urls.firstObject.path;
    if (!path.length) return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSInteger added = [SGStatsStore restoreFromFileAtPath:path];
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter postNotificationName:SGStatsChangedNotification object:nil];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Restore finished"
                message:[NSString stringWithFormat:@"Added %ld plays. Total %ld.", (long)added, (long)SGStatsStore.shared.playCount]
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [SGTopController() presentViewController:alert animated:YES completion:nil];
        });
    });
}

@end

#pragma mark - actions

static void eraseStats(void) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Erase all stats?"
        message:@"Every recorded and imported play is deleted. This cannot be undone."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Erase" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [SGStatsStore.shared eraseAll];
        [NSNotificationCenter.defaultCenter postNotificationName:SGStatsChangedNotification object:nil];
    }]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

static void backupStats(void) {
    [SGStatsStore.shared checkpoint];
    NSString *destination = [NSTemporaryDirectory() stringByAppendingPathComponent:@"spoti.pw-stats.sqlite"];
    NSError *error = nil;
    [NSFileManager.defaultManager removeItemAtPath:destination error:NULL];
    if (![NSFileManager.defaultManager copyItemAtPath:SGStatsStore.shared.filePath toPath:destination error:&error]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Backup failed" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [SGTopController() presentViewController:alert animated:YES completion:nil];
        return;
    }
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:destination]] applicationActivities:nil];
    share.popoverPresentationController.sourceView = SGTopController().view;
    [SGTopController() presentViewController:share animated:YES completion:nil];
}

NSString *SGStatsRowValue(void) {
    if (!SGFlag(SGKeyStats, NO)) return @"Off";
    return @(SGStatsStore.shared.playCount).stringValue;
}

static NSString *historyRange(void) {
    int64_t first = SGStatsStore.shared.earliestTs, last = SGStatsStore.shared.latestTs;
    if (!first) return @"None";
    static NSDateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ formatter = [NSDateFormatter new]; formatter.dateFormat = @"d MMM yyyy"; });
    NSString *from = [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:first]];
    NSString *to = [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:last]];
    return [NSString stringWithFormat:@"%@ – %@", from, to];
}

#pragma mark - recap

void SGStatsScheduleRecap(void) {
    UNUserNotificationCenter *center = UNUserNotificationCenter.currentNotificationCenter;
    NSString *identifier = @"spotifyglass.stats.recap";
    if (!SGFlag(SGKeyStatsRecap, NO)) {
        [center removePendingNotificationRequestsWithIdentifiers:@[identifier]];
        return;
    }
    [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound) completionHandler:^(BOOL granted, NSError *error) {
        if (!granted) return;
        int64_t weekAgo = (int64_t)NSDate.date.timeIntervalSince1970 - 7 * 86400;
        SGStatsSummary *summary = [SGStatsStore.shared summarySince:weekAgo];
        UNMutableNotificationContent *content = [UNMutableNotificationContent new];
        content.title = @"Your week in music";
        content.body = [NSString stringWithFormat:@"%@ plays · %@. Open spoti.pw → Stats.", countText(summary.plays), durationText(summary.ms)];
        NSDateComponents *components = [NSDateComponents new];
        components.weekday = 1;   // Sunday
        components.hour = 20;
        components.minute = 0;
        UNCalendarNotificationTrigger *trigger = [UNCalendarNotificationTrigger triggerWithDateMatchingComponents:components repeats:YES];
        [center removePendingNotificationRequestsWithIdentifiers:@[identifier]];
        [center addNotificationRequest:[UNNotificationRequest requestWithIdentifier:identifier content:content trigger:trigger] withCompletionHandler:nil];
    }];
}

#pragma mark - page

UIViewController *SGStatsSettingsPage(void) {
    SGModRow *enable = SGOptionRow(@"Listening stats", @"Keeps a local history of what you play", SGKeyStats);
    SGModRow *import = SGActionRow(@"Import streaming history", @"Use Spotify's Extended streaming history, not Account data", ^{
        [SGStatsImportUI.shared present];
    });
    SGModRow *plays = SGStatRow(@"Plays recorded", ^NSString *{ return @(SGStatsStore.shared.playCount).stringValue; });
    SGModRow *range = SGStatRow(@"History range", ^NSString *{ return historyRange(); });
    SGModRow *backup = SGActionRow(@"Back up stats", @"Saves the stats file to share or keep", ^{ backupStats(); });
    SGModRow *restore = SGActionRow(@"Restore stats", @"Reads a stats backup made by this app", ^{ [SGStatsRestoreUI.shared present]; });
    SGModRow *log = SGActionRow(@"Import log", @"What the last import did, kept across a crash", ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Import log" message:SGStatsLogTail(500) preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Copy" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            UIPasteboard.generalPasteboard.string = SGStatsLogTail(500);
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Clear" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { SGStatsLogClear(); }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [SGTopController() presentViewController:alert animated:YES completion:nil];
    });
    SGModRow *erase = SGActionRow(@"Erase all stats", nil, ^{ eraseStats(); });
    erase.color = UIColor.systemRedColor;
    SGModRow *recap = SGOptionRow(@"Weekly recap", @"A Sunday reminder with the week's listening", SGKeyStatsRecap);
    recap.changed = ^(BOOL on) { SGStatsScheduleRecap(); };

    return [[SGModPage alloc] initWithTitle:@"Stats" intro:SGRestartNote sections:@[
        SGSection(@"Listening stats", @[
            SGWithSymbol(enable, @"chart.bar"),
            SGWithSymbol(import, @"square.and.arrow.down"),
        ]),
        SGSection(@"Manage", @[
            SGWithSymbol(plays, @"number"),
            SGWithSymbol(range, @"calendar"),
            SGWithSymbol(backup, @"square.and.arrow.up"),
            SGWithSymbol(restore, @"square.and.arrow.down.on.square"),
            SGWithSymbol(log, @"doc.text"),
            SGWithSymbol(erase, @"trash"),
        ]),
        SGSection(@"Notifications", @[
            SGWithSymbol(recap, @"bell"),
        ]),
    ] footer:nil];
}
