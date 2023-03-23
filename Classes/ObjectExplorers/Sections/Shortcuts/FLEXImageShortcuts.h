//
//  FLEXImageShortcuts.h
//  FLEX
//
//  Created by Tanner Bennett on 8/29/19.
//  Copyright © 2020 FLEX Team. All rights reserved.
//

#import "Classes/Headers/FLEXShortcutsSection.h"

/// Provides "view image" and "save image" shortcuts for UIImage objects
@interface FLEXImageShortcuts : FLEXShortcutsSection

+ (instancetype)forObject:(UIImage *)image;

@end
