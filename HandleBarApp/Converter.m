//
//  Converter.m
//  HandleBarApp
//
//  Created by Johan Kuijt on 11-03-13.
//  Copyright (c) 2013 Mustacherious. All rights reserved.
//

#import "Converter.h"
#import "Util.h"

#import "NSOperationQueue+CWSharedQueue.h"
#import "NSFileManager+Directories.h"

@interface Converter()

@end

@implementation Converter

- (id) initWithPaths:(NSArray *)paths {
    
    self = [super init];
	if (self)
	{
		VDKQueue *vdk = [[VDKQueue alloc] init];
                
        for(NSDictionary *path in paths) {
            [vdk addPath:[path objectForKey:@"path"] notifyingAbout:VDKQueueNotifyAboutWrite];
        }
        
        vdk.delegate = self;
	}
	return self;
}

-(void) VDKQueue:(VDKQueue *)queue receivedNotification:(NSString*)noteName forPath:(NSString*)fpath {
    
    NSFileManager *fileManager = [[NSFileManager alloc] init];
    NSURL *directoryURL = [NSURL URLWithString:fpath];
    NSArray *keys = [NSArray arrayWithObject:NSURLIsDirectoryKey];
    NSMutableArray *videoFiles = [NSMutableArray new];
    
    NSDirectoryEnumerator *enumerator = [fileManager enumeratorAtURL:directoryURL includingPropertiesForKeys:keys options:0 errorHandler:^(NSURL *url, NSError *error) { return YES; }];

    for (NSURL *url in enumerator) {
     
        NSError *error;
        NSNumber *isDirectory = nil;
        NSNumber *isHidden = nil;
             
        [url getResourceValue:&isHidden forKey:NSURLIsHiddenKey error:&error];

        if (![url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:&error]) {
             NSLog(@"error while scanning dir");
        }
         
        if ([isDirectory boolValue]) {

            videoFiles = [self findVideoFiles:[NSString stringWithFormat:@"%@/",[url path]] array:videoFiles];
        }
    }
    
    if([videoFiles count] == 0)
        videoFiles = [self findVideoFiles:fpath array:videoFiles];
    
    videoFiles = [NSMutableArray arrayWithArray:[videoFiles valueForKeyPath:@"@distinctUnionOfObjects.self"]];
    
    [self performSelectorInBackgroundQueue:@selector(convert:) withObject:videoFiles];
}

- (void) convert:(NSArray *) videos {
    
    NSString *currentPath = [[NSBundle mainBundle] bundlePath];
    NSString *cmd = [currentPath stringByAppendingPathComponent:@"Contents/Resources/HandBrakeCLI"];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *appSupportPath = [fm applicationSupportFolder];
    NSString *failedPath = [appSupportPath stringByAppendingPathComponent:@"/media/failed"];
    NSString *debugRemovePath = [appSupportPath stringByAppendingPathComponent:@"/media/done"];
    
    NSString *videoPath = [videos objectAtIndex:0];
    NSString *convertPath = [NSString stringWithFormat:@"%@.m4v", [videoPath stringByDeletingPathExtension]];
    
    NSString *audioTracks = [self getAudioTracks:videoPath];
    NSString *preset = [[NSUserDefaults standardUserDefaults] objectForKey:@"HandBrakePreset"];
    NSString *language = [[NSUserDefaults standardUserDefaults] objectForKey:@"HandBrakeLanguage"];
        
    NSArray *args = [NSArray arrayWithObjects:@"-i", videoPath, @"-o", convertPath, @"--audio", audioTracks, @"--preset", preset, @"--native-language", language, @"--native-dub", @"1>", @"/tmp/handleBarEncode.status", nil];
    
    [Util executeCommand:cmd args:args];
    
    if([fm fileExistsAtPath:convertPath]) {
        
        if([Util inDebugMode]) {
            
            NSString *newPath = [debugRemovePath stringByAppendingPathComponent:[videoPath lastPathComponent]];
            [fm moveItemAtPath:videoPath toPath:newPath error:nil];
            
        } else {
            
            // Move orignal file to the trash bin
            [Util trashWithPath:videoPath];
        }
        
    } else {
        
        // Move original to failed dir if m4v isn't found
        NSString *newPath = [failedPath stringByAppendingPathComponent:[videoPath lastPathComponent]];
        [fm moveItemAtPath:videoPath toPath:newPath error:nil];
    }
}

- (NSString *)getAudioTracks:(NSString *)sourcePath {
    
    //Downloads/ffmpeg -i Downloads/tv/Californication.S06E03.mov 2>&1 >/dev/null | grep -c "Audio"
    
    NSString *currentPath = [[NSBundle mainBundle] bundlePath];
    NSString *cmd = [currentPath stringByAppendingPathComponent:@"Contents/Resources/ffmpeg"];
    
    NSDictionary *response = [Util executeBashCommand:[NSString stringWithFormat:@"%@ -i %@ 2>&1 >/dev/null | grep -c 'Audio'", cmd, sourcePath]];

    int trackCount = (int) [[response objectForKey:@"response"] integerValue];

    NSMutableArray *tracks = [NSMutableArray new];
    
    for(int i = 1; i <= trackCount; i++) {
        [tracks addObject:[NSNumber numberWithInt:i]];
    }
    
    return [tracks componentsJoinedByString:@","];
}

- (NSMutableArray *) findVideoFiles:(NSString *)path array:(NSMutableArray *)videosFiles {
    
    NSArray *dirFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:nil];
    NSArray *files = [dirFiles filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:[self fileTypePredicateString]]];
    
    for(NSString *file in files) {
        
        NSString *f = [NSString stringWithFormat:@"%@%@",path, file];
        [videosFiles addObject:f];
    }
    
    return videosFiles;
}

- (NSString *)fileTypePredicateString {
    
    NSArray *fileTypesConfig = [[NSUserDefaults standardUserDefaults] objectForKey:@"FileTypes"];
    NSMutableArray *fileTypes = [[NSMutableArray alloc] init];
    
    for(NSDictionary *fileType in fileTypesConfig) {
        
        NSString *predicate = [NSString stringWithFormat:@"(self ENDSWITH '%@')", [[fileType objectForKey:@"file"] stringByReplacingOccurrencesOfString:@"*" withString:@""]];
        [fileTypes addObject:predicate];
    }
    
    return [fileTypes componentsJoinedByString:@" OR "];       
}

@end
