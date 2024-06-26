#include "Tweak.h"

@interface UITraitCollection ()
+(id)currentTraitCollection;
@end

BOOL isTweakEnabled, is3DMenu;
static void loadPrefs() { 
	NSMutableDictionary* mainPreferenceDict = [[NSMutableDictionary alloc] initWithContentsOfFile:SPOOF_VER_PLIST];
	isTweakEnabled = [mainPreferenceDict objectForKey:@"isTweakEnabled"] ? [[mainPreferenceDict objectForKey:@"isTweakEnabled"] boolValue] : YES;
	is3DMenu = [mainPreferenceDict objectForKey:@"is3DMenu"] ? [[mainPreferenceDict objectForKey:@"is3DMenu"] boolValue] : YES;
}

%hook SBIconView
- (void)setApplicationShortcutItems:(NSArray *)shortcutItems {
	#define TDAVS_ASSET_DARK jbroot(@"/Library/Application Support/3DAppVersionSpoofer.bundle/fakeverblack@2x.png")
	#define TDAVS_ASSET_WHITE jbroot(@"/Library/Application Support/3DAppVersionSpoofer.bundle/fakeverwhite@2x.png")
	if (!is3DMenu) {
		return %orig;
	}

	NSMutableArray *editedItems = [NSMutableArray arrayWithArray:shortcutItems ? : @[]];
	if (![self.icon isKindOfClass:%c(SBFolderIcon)] && ![self.icon isKindOfClass:%c(SBWidgetIcon)]) { 
		SBSApplicationShortcutItem *shortcutItems = [[%c(SBSApplicationShortcutItem) alloc] init];
		shortcutItems.localizedTitle = @"Spoof App Version";
		shortcutItems.type = SPOOF_VER_TWEAK_BUNDLE;
		NSData *imgData = UIImagePNGRepresentation([UIImage imageNamed:TDAVS_ASSET_DARK]);
		//dark mode check
		NSOperatingSystemVersion version = [[NSProcessInfo processInfo] operatingSystemVersion];
		if (version.majorVersion >= 13 && version.majorVersion >= 5) {
			if ([[UITraitCollection currentTraitCollection] userInterfaceStyle] == UIUserInterfaceStyleDark) {
				imgData = UIImagePNGRepresentation([UIImage imageNamed:TDAVS_ASSET_WHITE]);
			}
		}
		if (imgData) {
			SBSApplicationShortcutCustomImageIcon *iconImage = [[%c(SBSApplicationShortcutCustomImageIcon) alloc] initWithImagePNGData:imgData];
			shortcutItems.icon = iconImage;
		}
		if (shortcutItems) {
			[editedItems addObject:shortcutItems];
		}
	}
 	%orig(editedItems);
}

+ (void)activateShortcut:(SBSApplicationShortcutItem *)item withBundleIdentifier:(NSString *)bundleID forIconView:(SBIconView *)iconView {
    if ([item.type isEqualToString:SPOOF_VER_TWEAK_BUNDLE]) {
		//i have no idea why sometimes the apdefaultversion is null, the bundle is correct and works the same as in settings..
		NSString *appDefaultVersion = [NSBundle bundleWithIdentifier:bundleID].infoDictionary[@"CFBundleShortVersionString"];
		NSMutableDictionary *prefPlist = [NSMutableDictionary dictionary];
		[prefPlist addEntriesFromDictionary:[NSDictionary dictionaryWithContentsOfFile:SPOOF_VER_PLIST]];
		NSString *currentVer = prefPlist[bundleID];
		if (currentVer == nil || [currentVer isEqualToString:@"0"]) {
			currentVer = @"Default";
		}
	    UIAlertController* alertController = [UIAlertController alertControllerWithTitle:@"3DAppVersionSpoofer"
																	message:[NSString stringWithFormat:@"WARNING: This can cause unexpected behavior in your app.\nBundle ID: %@\nCurrent Spoofed Version: %@\nDefault App Version: %@\n\nWhat is the version number you want to spoof?",bundleID,currentVer,appDefaultVersion]
																	preferredStyle:UIAlertControllerStyleAlert];

		[alertController addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {textField.placeholder = @"Enter Version Number"; textField.keyboardType = UIKeyboardTypeDecimalPad;}];
		UIAlertAction *setNewValue = [UIAlertAction actionWithTitle:@"Set Spoofed Version" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
			NSString *answerFromTextField = ([[alertController textFields][0] text].length > 0) ? [[alertController textFields][0] text] : @"0";
			//support regions that have comma instead of dot 0-0
			[prefPlist setObject:[answerFromTextField stringByReplacingOccurrencesOfString:@"," withString:@"."] forKey:bundleID];
			[prefPlist writeToFile:SPOOF_VER_PLIST atomically:YES]; 
		}];

		[alertController addAction:setNewValue];

		UIAlertAction *setDefaultValue = [UIAlertAction actionWithTitle:@"Reset to Default Version" style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
			//0 means use original version!
			CGFloat defaultValue = 0.0f;
			NSNumber *numberFromFloat = [NSNumber numberWithFloat:defaultValue];
			[prefPlist setObject:[numberFromFloat stringValue] forKey:bundleID];
			[prefPlist writeToFile:SPOOF_VER_PLIST atomically:YES];
		}];
		[alertController addAction:setDefaultValue];

		UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style: UIAlertActionStyleCancel handler:^(UIAlertAction * action) {}];

		[alertController addAction:cancelAction];

		//seriously shit hacks
		UIWindow *originalKeyWindow = [[UIApplication sharedApplication] keyWindow];
		UIResponder *responder = originalKeyWindow.rootViewController.view;
		while ([responder isKindOfClass:[UIView class]]) responder = [responder nextResponder];
		[(UIViewController *)responder presentViewController:alertController animated:YES completion:^{}];
	} else {
		%orig;
	}

}
%end

%hook NSBundle
NSString *versionToSpoof = nil;
-(NSDictionary *)infoDictionary {
	NSDictionary *dictionary = %orig;
	NSMutableDictionary *moddedDictionary = [NSMutableDictionary dictionaryWithDictionary:dictionary];
	NSDictionary* modifiedBundlesDict = [[NSDictionary alloc] initWithContentsOfFile:SPOOF_VER_PLIST];
	if (!self || ![self isLoaded] || ![[self bundleURL].absoluteString containsString:@"Application"] || !isTweakEnabled || (!modifiedBundlesDict[moddedDictionary[@"CFBundleIdentifier"]] || [modifiedBundlesDict[moddedDictionary[@"CFBundleIdentifier"]] isEqualToString:@"0"])) {
		return %orig;
	} else {	
		NSString *appBundleID = moddedDictionary[@"CFBundleIdentifier"];
		if ((appBundleID) && ([modifiedBundlesDict objectForKey:appBundleID]) && ([[modifiedBundlesDict objectForKey:appBundleID] length] > 0) && (![modifiedBundlesDict[appBundleID] isEqualToString:@"0"])) {
			versionToSpoof = [[NSString alloc] init];
			versionToSpoof = modifiedBundlesDict[appBundleID];
			[moddedDictionary setValue:versionToSpoof forKey:@"CFBundleShortVersionString"];
		}
		return moddedDictionary;
	}
}
%end

%ctor{
	loadPrefs();
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)loadPrefs, CFSTR("com.0xkuj.3dappversionspoofer.settingschanged"), NULL, CFNotificationSuspensionBehaviorCoalesce);
}