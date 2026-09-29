// Listening stats: every play this install hears and everything imported from Spotify's Extended
// streaming history, held in one SQLite file and shown on a Stats page in Mod Settings. Shared, so
// both looks get it.
#import <UIKit/UIKit.h>

#define SGKeyStats @"spotifyglass.stats"
// Posted when the store gains plays from an import or loses them to an erase, so an open Stats page
// reads again.
#define SGStatsChangedNotification @"spotifyglass.stats.changed"

// The Stats screen and the page its import, erase and export live on.
UIViewController *SGStatsPage(void);
UIViewController *SGStatsSettingsPage(void);

// The Mod Settings row's value: "Off" while the switch is off, else how many plays are stored.
NSString *SGStatsRowValue(void);

// Starts the player observer that records plays. Called once from the tweak's %ctor; a no-op while
// the switch is off.
void SGStatsStart(void);
