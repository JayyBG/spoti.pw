#import "Stats.h"
#import "SGStatsStore.h"
#import "SGStatsImport.h"
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

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

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSInteger added = 0;
    NSError *error = nil;
    for (NSURL *url in urls) added += [SGStatsImporter importFileAtURL:url error:&error];
    [NSNotificationCenter.defaultCenter postNotificationName:SGStatsChangedNotification object:nil];
    NSString *message = added ? [NSString stringWithFormat:@"Added %ld plays.", (long)added]
                              : (error.localizedDescription ?: @"No plays found in that file.");
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Import finished" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

@end

NSString *SGStatsRowValue(void) {
    if (!SGFlag(SGKeyStats, NO)) return @"Off";
    return @(SGStatsStore.shared.playCount).stringValue;
}

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

UIViewController *SGStatsSettingsPage(void) {
    SGModRow *enable = SGOptionRow(@"Listening stats", @"Keeps a local history of what you play", SGKeyStats);
    SGModRow *import = SGActionRow(@"Import streaming history", @"Spotify → Account → Privacy → Download your data (the .zip)", ^{
        [SGStatsImportUI.shared present];
    });
    SGModRow *plays = SGStatRow(@"Plays recorded", ^NSString *{ return @(SGStatsStore.shared.playCount).stringValue; });
    SGModRow *erase = SGActionRow(@"Erase all stats", nil, ^{ eraseStats(); });
    erase.color = UIColor.systemRedColor;

    return [[SGModPage alloc] initWithTitle:@"Stats" intro:SGRestartNote sections:@[
        SGSection(@"Listening stats", @[
            SGWithSymbol(enable, @"chart.bar"),
            SGWithSymbol(import, @"square.and.arrow.down"),
        ]),
        SGSection(@"Manage", @[
            SGWithSymbol(plays, @"number"),
            SGWithSymbol(erase, @"trash"),
        ]),
    ] footer:nil];
}
