//
//  TBSiteDocument.m
//  Tribo
//
//  Created by Carter Allen on 10/3/11.
//  Copyright (c) 2011 Opt-6 Products, LLC. All rights reserved.
//

#import "TBSiteDocument.h"
#import "TBAddPostSheetController.h"
#import "TBSite.h"
#import "TBPost.h"
#import "HTTPServer.h"
#import "Safari.h"
#import "UKFSEventsWatcher.h"
#import <Quartz/Quartz.h>

@interface TBSiteDocument () <NSTableViewDelegate>
@property (nonatomic, strong) UKFSEventsWatcher *sourceWatcher;
@property (nonatomic, strong) UKFSEventsWatcher *postsWatcher;
@property (nonatomic, strong) HTTPServer *server;
@property (nonatomic, strong) NSPopover *currentPopover;
@property (nonatomic, strong) NSViewController *previewController;
- (void)refreshLocalhostPages;
@end

@implementation TBSiteDocument
@synthesize site=_site;
@synthesize postTableView=_postTableView;
@synthesize progressIndicator=_progressIndicator;
@synthesize previewButton=_previewButton;
@synthesize postCountLabel=_postCountLabel;
@synthesize addPostSheetController=_addPostSheetController;
@synthesize sourceWatcher=_sourceWatcher;
@synthesize postsWatcher=_postsWatcher;
@synthesize server=_server;
@synthesize currentPopover=_currentPopover;
@synthesize previewController=_previewController;

- (NSString *)windowNibName { return @"TBSiteDocument"; }

- (IBAction)preview:(id)sender {
	
	if (!self.server.isRunning) {
		
		self.previewButton.hidden = YES;
		self.progressIndicator.hidden = NO;
		[self.progressIndicator startAnimation:self];
		[self.site process];
		
		if (!self.sourceWatcher) {
			self.sourceWatcher = [UKFSEventsWatcher new];
			self.sourceWatcher.delegate = self;
		}
		[self.sourceWatcher addPath:self.site.sourceDirectory.path];
		[self.sourceWatcher addPath:self.site.templatesDirectory.path];
		
		// Start up the HTTP server so that the site can be previewed.
		if (!self.server) {
			self.server = [HTTPServer new];
			self.server.documentRoot = self.site.destination.path;
		}
		[self.server start:nil];
		[self refreshLocalhostPages];
		
		[self.progressIndicator stopAnimation:self];
		self.progressIndicator.hidden = YES;
		self.previewButton.title = @"Stop Server";
		[self.previewButton sizeToFit];
		self.previewButton.hidden = NO;
		[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://localhost:%d", self.server.listeningPort]]];
		
	}
	else {
		[self.sourceWatcher removeAllPaths];
		[self.server stop];
		self.previewButton.title = @"Preview";
	}
}

- (IBAction)showAddPostSheet:(id)sender {
	[self.addPostSheetController runModalForWindow:self.windowForSheet completionBlock:^(NSString *title, NSString *slug) {
		NSDate *currentDate = [NSDate date];
		NSDateFormatter *dateFormatter = [NSDateFormatter new];
		dateFormatter.dateFormat = @"yyyy-MM-dd";
		NSString *dateString = [dateFormatter stringFromDate:currentDate];
		NSString *filename = [NSString stringWithFormat:@"%@-%@", dateString, slug];
		NSURL *destination = [[self.site.postsDirectory URLByAppendingPathComponent:filename] URLByAppendingPathExtension:@"md"];
		NSString *contents = [NSString stringWithFormat:@"# %@ #\n\n", title];
		[contents writeToURL:destination atomically:YES encoding:NSUTF8StringEncoding error:nil];
		[self.site parsePosts];
		[[NSWorkspace sharedWorkspace] openURL:destination];
	}];
}

- (IBAction)editPost:(id)sender {
	TBPost *clickedPost = [self.site.posts objectAtIndex:[self.postTableView clickedRow]];
	[[NSWorkspace sharedWorkspace] openURL:clickedPost.URL];
}

- (IBAction)previewPost:(id)sender {
	if (!self.server.isRunning) [self preview:sender];
	TBPost *clickedPost = [self.site.posts objectAtIndex:[self.postTableView clickedRow]];
	NSDateFormatter *formatter = [NSDateFormatter new];
	formatter.dateFormat = @"yyyy/MM/dd";
	NSString *postURLPrefix = [[formatter stringFromDate:clickedPost.date] stringByAppendingPathComponent:clickedPost.slug];
	NSURL *postPreviewURL = [NSURL URLWithString:postURLPrefix relativeToURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://localhost:%d", self.server.listeningPort]]];
	[[NSWorkspace sharedWorkspace] openURL:postPreviewURL];
	
}

- (IBAction)revealPost:(id)sender {
	TBPost *clickedPost = [self.site.posts objectAtIndex:[self.postTableView clickedRow]];
	[[NSWorkspace sharedWorkspace] selectFile:clickedPost.URL.path inFileViewerRootedAtPath:nil];
}

- (void)refreshLocalhostPages {
	// Refresh any Safari tabs open to http://localhost:port/**.
	SafariApplication *safari = (SafariApplication *)[[SBApplication alloc] initWithBundleIdentifier:@"com.apple.Safari"];
	for (SafariWindow *window in safari.windows) {
		for (SafariTab *tab in window.tabs) {
			if ([tab.URL hasPrefix:[NSString stringWithFormat:@"http://localhost:%d", self.server.listeningPort]]) {
				tab.URL = tab.URL;
			}
		}
	}
}

- (void)watcher:(id<UKFileWatcher>)watcher receivedNotification:(NSString *)notification forPath:(NSString *)path {
	if (watcher == self.sourceWatcher || self.server.isRunning) {
		[self.site process];
		[self refreshLocalhostPages];
	}
	else if (watcher == self.postsWatcher) {
		[self.site parsePosts];
	}
}

- (void)windowControllerDidLoadNib:(NSWindowController *)controller {
    [super windowControllerDidLoadNib:controller];
	self.postTableView.target = self;
	self.postTableView.doubleAction = @selector(editPost:);
	((NSCell *)self.postCountLabel.cell).backgroundStyle = NSBackgroundStyleRaised;
	self.addPostSheetController = [TBAddPostSheetController new];
	self.postsWatcher = [UKFSEventsWatcher new];
	self.postsWatcher.delegate = self;
	[self.postsWatcher addPath:self.site.postsDirectory.path];
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
	self.postCountLabel.textColor = [NSColor controlTextColor];
}

- (void)windowDidResignKey:(NSNotification *)notification {
	self.postCountLabel.textColor = [NSColor disabledControlTextColor];
}

- (void)toggleQuickLookPopover {
	if (!self.currentPopover) {
		TBPost *selectedPost = [self.site.posts objectAtIndex:self.postTableView.selectedRow];
		if (!self.previewController) {
			self.previewController = [[NSViewController alloc] initWithNibName:@"TBQLPreviewView" bundle:[NSBundle bundleForClass:[self class]]];
			((QLPreviewView *)self.previewController.view).shouldCloseWithWindow = NO;
		}
		((QLPreviewView *)self.previewController.view).previewItem = selectedPost.URL;
		self.currentPopover = [NSPopover new];
		self.currentPopover.animates = YES;
		self.currentPopover.contentViewController = self.previewController;
		[self.currentPopover showRelativeToRect:[self.postTableView rectOfRow:self.postTableView.selectedRow] ofView:self.postTableView preferredEdge:0];
		[self.postTableView.superview becomeFirstResponder];
	}
	else {
		[self.currentPopover close];
		self.currentPopover = nil;
	}
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
	if (self.currentPopover.isShown) {
		TBPost *selectedPost = [self.site.posts objectAtIndex:self.postTableView.selectedRow];
		((QLPreviewView *)self.previewController.view).previewItem = selectedPost.URL;
		self.currentPopover.positioningRect = [self.postTableView rectOfRow:self.postTableView.selectedRow];
	}
}

- (BOOL)readFromURL:(NSURL *)URL ofType:(NSString *)typeName error:(NSError *__autoreleasing *)outError {
	self.site = [TBSite siteWithRoot:URL];
	[self.site parsePosts];
	return YES;
}

- (void)dealloc {
	if (self.previewController)
		[(QLPreviewView *)self.previewController.view close];
}

@end