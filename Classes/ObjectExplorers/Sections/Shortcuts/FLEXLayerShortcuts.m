//
//  FLEXLayerShortcuts.m
//  FLEX
//
//  Created by Tanner Bennett on 12/12/19.
//  Copyright © 2020 FLEX Team. All rights reserved.
//

#import "Classes/ObjectExplorers/Sections/Shortcuts/FLEXLayerShortcuts.h"
#import "Classes/Headers/FLEXShortcut.h"
#import "Classes/ViewHierarchy/FLEXImagePreviewViewController.h"

@implementation FLEXLayerShortcuts

+ (instancetype)forObject:(CALayer *)layer {
    return [self forObject:layer additionalRows:@[
        [FLEXActionShortcut title:@"Preview Image" subtitle:nil
            viewer:^UIViewController *(CALayer *layer) {
                return [FLEXImagePreviewViewController previewForLayer:layer];
            }
            accessoryType:^UITableViewCellAccessoryType(CALayer *layer) {
                return CGRectIsEmpty(layer.bounds) ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDisclosureIndicator;
            }
        ]
    ]];
}

@end
