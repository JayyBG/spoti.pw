// Listening stats: every play this install hears and everything imported from Spotify's Extended
// streaming history, held in one SQLite file and shown on a Stats page in Mod Settings. Shared, so
// both looks get it.
#import <UIKit/UIKit.h>
#import "SGStatsModel.h"

@class SGStatsEntry;

#define SGKeyStats @"spotifyglass.stats"
#define SGKeyStatsRecap @"spotifyglass.stats.recap"
// Posted when the store gains plays from an import or loses them to an erase, so an open Stats page
// reads again.
#define SGStatsChangedNotification @"spotifyglass.stats.changed"

// The Stats screen and the page its import, erase and export live on.
UIViewController *SGStatsPage(void);
UIViewController *SGStatsSettingsPage(void);

// The Mod Settings row's value: "Off" while the switch is off, else how many plays are stored.
NSString *SGStatsRowValue(void);

// The pages the Stats screen reaches: the recent plays, the listening clock, the discoveries, one
// entity in full, and the shareable Wrapped card.
UIViewController *SGStatsHistoryPage(void);
UIViewController *SGStatsClockPage(void);
UIViewController *SGStatsDiscoverPage(SGStatsDiscover kind, SGStatsEntity entity, SGStatsRange range);
UIViewController *SGStatsDetailPage(SGStatsEntry *entry, SGStatsEntity entity);
UIViewController *SGStatsCalendarPage(void);
UIViewController *SGStatsYearsPage(void);
UIViewController *SGStatsBreakdownPage(SGStatsBreakdown kind, SGStatsRange range);
void SGStatsShareWrapped(UIViewController *owner, SGStatsEntity entity);

// Starts the player observer that records plays. Called once from the tweak's %ctor; a no-op while
// the switch is off.
void SGStatsStart(void);

// Schedules the weekly recap notification with the last seven days' numbers, if its switch is on.
void SGStatsScheduleRecap(void);

// Writes the home screen widget's summary into the App Group and reloads its timelines.
void SGStatsWriteWidgetSummary(void);
