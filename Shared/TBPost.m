//
//  TBPost.m
//  Tribo
//
//  Created by Carter Allen on 9/25/11.
//  Copyright (c) 2012 The Tribo Authors.
//  See the included License.md file.
//

#import "TBSite.h"
#import "TBPost.h"
#import "TBError.h"
#import "markdown.h"
#import "html.h"
#import "NSDateFormatter+TBAdditions.h"

@implementation TBPost

+ (instancetype)postWithURL:(NSURL *)URL inSite:(TBSite *)site error:(NSError **)error {
	return (TBPost *)[super pageWithURL:URL inSite:site error:error];
}

- (BOOL)parse:(NSError **)error {
	
	[self loadMarkdownContent];
	
	if (![self parseDateAndSlug:error])
		return NO;
	
	[self parseTitle];
	
    return YES;
	
}

- (void)loadMarkdownContent; {
	NSString *markdownContent = [NSString stringWithContentsOfURL:self.URL encoding:NSUTF8StringEncoding error:nil];
	self.markdownContent = markdownContent;
}

- (void)parseTitle {
	// Titles are optional. A single # header on the first line of the document is regarded as the title.
	if (!self.markdownContent || ![self.markdownContent length]) return;
	NSMutableString *markdownContent = [self.markdownContent mutableCopy];
	static NSRegularExpression *headerRegex;
	if (headerRegex == nil)
		headerRegex = [NSRegularExpression regularExpressionWithPattern:@"#[ \\t](.*)[ \\t]#" options:0 error:nil];
	NSRange firstLineRange = NSMakeRange(0, [markdownContent rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]].location);
	if (firstLineRange.length == NSNotFound) return;
	NSString *firstLine = [markdownContent substringWithRange:firstLineRange];
	NSTextCheckingResult *titleResult = [headerRegex firstMatchInString:firstLine options:0 range:NSMakeRange(0, firstLine.length)];
	if (titleResult) {
		self.title = [firstLine substringWithRange:[titleResult rangeAtIndex:1]];
		[markdownContent deleteCharactersInRange:NSMakeRange(firstLineRange.location, firstLineRange.length + 1)];
	}
	[markdownContent deleteCharactersInRange:[markdownContent rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]]];
	self.markdownContent = markdownContent;
}

- (BOOL)parseDateAndSlug:(NSError **)error {
	// Dates and slugs are parsed from a pattern in the post file name.
	static NSRegularExpression *fileNameRegex;
	if (fileNameRegex == nil)
		fileNameRegex = [NSRegularExpression regularExpressionWithPattern:@"^(\\d+-\\d+-\\d+)-(.*)" options:0 error:nil];
	NSString *fileName = [self.URL.lastPathComponent stringByDeletingPathExtension];
	NSTextCheckingResult *fileNameResult = [fileNameRegex firstMatchInString:fileName options:0 range:NSMakeRange(0, fileName.length)];
	if (fileNameResult) {
		NSDateFormatter *fileNameDateFormatter = [NSDateFormatter tb_cachedDateFormatterFromString:@"yyyy-MM-dd"];
		self.date = [fileNameDateFormatter dateFromString:[fileName substringWithRange:[fileNameResult rangeAtIndex:1]]];
		self.slug = [fileName substringWithRange:[fileNameResult rangeAtIndex:2]];
	}
	else {
		if (error) *error = TBError.badPostFileName(self.URL);
		return NO;
	}
	return YES;
}

- (void)parseMarkdownContent {
	if (!self.markdownContent || ![self.markdownContent length]) return;
	// Create and fill a buffer for with the raw markdown data.
	if ([self.markdownContent length] == 0) return;
	struct sd_callbacks callbacks;
	struct html_renderopt options;
	const char *rawMarkdown = [self.markdownContent cStringUsingEncoding:NSUTF8StringEncoding];
	struct buf *smartyPantsOutputBuffer = bufnew(1);
	sdhtml_smartypants(smartyPantsOutputBuffer, (const unsigned char *)rawMarkdown, strlen(rawMarkdown));
	
	// Parse the markdown into a new buffer using Sundown.
	struct buf *outputBuffer = bufnew(64);
	sdhtml_renderer(&callbacks, &options, 0);
	struct sd_markdown *markdown = sd_markdown_new(0, 16, &callbacks, &options);
	sd_markdown_render(outputBuffer, smartyPantsOutputBuffer->data, smartyPantsOutputBuffer->size, markdown);
	sd_markdown_free(markdown);
	
	self.content = @(bufcstr(outputBuffer));
	
	bufrelease(smartyPantsOutputBuffer);
	bufrelease(outputBuffer);
}

@end
