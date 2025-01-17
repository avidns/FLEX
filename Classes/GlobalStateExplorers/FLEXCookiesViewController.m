//
//  FLEXCookiesViewController.m
//  FLEX
//
//  Created by Rich Robinson on 19/10/2015.
//  Copyright © 2020 FLEX Team. All rights reserved.
//

#import "Classes/GlobalStateExplorers/FLEXCookiesViewController.h"
#import "Classes/Headers/FLEXObjectExplorerFactory.h"
#import "Classes/Headers/FLEXMutableListSection.h"
#import "Classes/Utility/FLEXUtility.h"

@interface FLEXCookiesViewController ()
@property (nonatomic, readonly) FLEXMutableListSection<NSHTTPCookie *> *cookies;
@property (nonatomic) NSString *headerTitle;
@end

@implementation FLEXCookiesViewController

#pragma mark - Overrides

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Cookies";
}

- (NSString *)headerTitle {
    return self.cookies.title;
}

- (void)setHeaderTitle:(NSString *)headerTitle {
    self.cookies.customTitle = headerTitle;
}

- (NSArray<FLEXTableViewSection *> *)makeSections {
    NSSortDescriptor *nameSortDescriptor = [[NSSortDescriptor alloc]
        initWithKey:@"name" ascending:YES selector:@selector(caseInsensitiveCompare:)
    ];
    NSArray *cookies = [NSHTTPCookieStorage.sharedHTTPCookieStorage.cookies
       sortedArrayUsingDescriptors:@[nameSortDescriptor]
    ];
    
    _cookies = [FLEXMutableListSection list:cookies
        cellConfiguration:^(UITableViewCell *cell, NSHTTPCookie *cookie, NSInteger row) {
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.textLabel.text = [cookie.name stringByAppendingFormat:@" (%@)", cookie.value];
            cell.detailTextLabel.text = [cookie.domain stringByAppendingFormat:@" — %@", cookie.path];
        } filterMatcher:^BOOL(NSString *filterText, NSHTTPCookie *cookie) {
            return [cookie.name localizedCaseInsensitiveContainsString:filterText] ||
                [cookie.value localizedCaseInsensitiveContainsString:filterText] ||
                [cookie.domain localizedCaseInsensitiveContainsString:filterText] ||
                [cookie.path localizedCaseInsensitiveContainsString:filterText];
        }
    ];
    
    self.cookies.selectionHandler = ^(UIViewController *host, NSHTTPCookie *cookie) {
        [host.navigationController pushViewController:[
            FLEXObjectExplorerFactory explorerViewControllerForObject:cookie
        ] animated:YES];
    };
    
    return @[self.cookies];
}

- (void)reloadData {
    self.headerTitle = [NSString stringWithFormat:
        @"%@ cookies", @(self.cookies.filteredList.count)
    ];
    [super reloadData];
}

#pragma mark - FLEXGlobalsEntry

+ (NSString *)globalsEntryTitle:(FLEXGlobalsRow)row {
    return @"🍪  Cookies";
}

+ (UIViewController *)globalsEntryViewController:(FLEXGlobalsRow)row {
    return [self new];
}

@end
