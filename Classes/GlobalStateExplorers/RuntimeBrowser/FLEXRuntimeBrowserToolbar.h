//
//  FLEXRuntimeBrowserToolbar.h
//  FLEX
//
//  Created by Tanner on 6/11/17.
//  Copyright © 2017 Tanner Bennett. All rights reserved.
//

#import "Classes/GlobalStateExplorers/RuntimeBrowser/FLEXKeyboardToolbar.h"
#import "Classes/GlobalStateExplorers/RuntimeBrowser/FLEXRuntimeKeyPath.h"

@interface FLEXRuntimeBrowserToolbar : FLEXKeyboardToolbar

+ (instancetype)toolbarWithHandler:(FLEXKBToolbarAction)tapHandler suggestions:(NSArray<NSString *> *)suggestions;

- (void)setKeyPath:(FLEXRuntimeKeyPath *)keyPath suggestions:(NSArray<NSString *> *)suggestions;

@end
