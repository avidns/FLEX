//
//  FLEXObjectExplorerViewController.m
//  Flipboard
//
//  Created by Ryan Olson on 2014-05-03.
//  Copyright (c) 2020 FLEX Team. All rights reserved.
//

#import "Classes/Headers/FLEXObjectExplorerViewController.h"
#import "Classes/Utility/FLEXUtility.h"
#import "Classes/Utility/Runtime/FLEXRuntimeUtility.h"
#import "Classes/Utility/Categories/UIBarButtonItem+FLEX.h"
#import "Classes/Headers/FLEXMultilineTableViewCell.h"
#import "Classes/Headers/FLEXObjectExplorerFactory.h"
#import "Classes/Editing/FLEXFieldEditorViewController.h"
#import "Classes/Editing/FLEXMethodCallingViewController.h"
#import "Classes/GlobalStateExplorers/FLEXObjectListViewController.h"
#import "Classes/ExplorerInterface/Tabs/FLEXTabsViewController.h"
#import "Classes/ExplorerInterface/Bookmarks/FLEXBookmarkManager.h"
#import "Classes/Headers/FLEXTableView.h"
#import "Classes/Utility/FLEXResources.h"
#import "Classes/Headers/FLEXTableViewCell.h"
#import "Classes/Core/Views/Carousel/FLEXScopeCarousel.h"
#import "Classes/Headers/FLEXMetadataSection.h"
#import "Classes/Headers/FLEXSingleRowSection.h"
#import "Classes/Headers/FLEXShortcutsSection.h"
#import "Classes/Utility/Categories/NSUserDefaults+FLEX.h"
#import <objc/runtime.h>

#pragma mark - Private properties
@interface FLEXObjectExplorerViewController () <UIGestureRecognizerDelegate>
@property (nonatomic, readonly) FLEXSingleRowSection *descriptionSection;
@property (nonatomic, readonly) NSArray<FLEXTableViewSection *> *customSections;
@property (nonatomic) NSIndexSet *customSectionVisibleIndexes;

@property (nonatomic, readonly) NSArray<NSString *> *observedNotifications;

@end

@implementation FLEXObjectExplorerViewController

#pragma mark - Initialization

+ (instancetype)exploringObject:(id)target {
    return [self exploringObject:target customSection:[FLEXShortcutsSection forObject:target]];
}

+ (instancetype)exploringObject:(id)target customSection:(FLEXTableViewSection *)section {
    return [self exploringObject:target customSections:@[section]];
}

+ (instancetype)exploringObject:(id)target customSections:(NSArray *)customSections {
    return [[self alloc]
        initWithObject:target
        explorer:[FLEXObjectExplorer forObject:target]
        customSections:customSections
    ];
}

- (id)initWithObject:(id)target
            explorer:(__kindof FLEXObjectExplorer *)explorer
       customSections:(NSArray<FLEXTableViewSection *> *)customSections {
    NSParameterAssert(target);
    
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        _object = target;
        _explorer = explorer;
        _customSections = customSections;
    }

    return self;
}

- (NSArray<NSString *> *)observedNotifications {
    return @[
        kFLEXDefaultsHidePropertyIvarsKey,
        kFLEXDefaultsHidePropertyMethodsKey,
        kFLEXDefaultsHidePrivateMethodsKey,
        kFLEXDefaultsShowMethodOverridesKey,
        kFLEXDefaultsHideVariablePreviewsKey,
    ];
}

#pragma mark - View controller lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.showsShareToolbarItem = YES;
    self.wantsSectionIndexTitles = YES;

    // Use [object class] here rather than object_getClass
    // to avoid the KVO prefix for observed objects
    self.title = [FLEXRuntimeUtility safeClassNameForObject:self.object];

    // Search
    self.showsSearchBar = YES;
    self.searchBarDebounceInterval = kFLEXDebounceInstant;
    self.showsCarousel = YES;

    // Carousel scope bar
    [self.explorer reloadClassHierarchy];
    self.carousel.items = [self.explorer.classHierarchyClasses flex_mapped:^id(Class cls, NSUInteger idx) {
        return NSStringFromClass(cls);
    }];
    
    // ... button for extra options
    [self addToolbarItems:@[[UIBarButtonItem
        flex_itemWithImage:FLEXResources.moreIcon target:self action:@selector(moreButtonPressed:)
    ]]];

    // Swipe gestures to swipe between classes in the hierarchy
    UISwipeGestureRecognizer *leftSwipe = [[UISwipeGestureRecognizer alloc]
        initWithTarget:self action:@selector(handleSwipeGesture:)
    ];
    UISwipeGestureRecognizer *rightSwipe = [[UISwipeGestureRecognizer alloc]
        initWithTarget:self action:@selector(handleSwipeGesture:)
    ];
    leftSwipe.direction = UISwipeGestureRecognizerDirectionLeft;
    rightSwipe.direction = UISwipeGestureRecognizerDirectionRight;
    leftSwipe.delegate = self;
    rightSwipe.delegate = self;
    [self.tableView addGestureRecognizer:leftSwipe];
    [self.tableView addGestureRecognizer:rightSwipe];
    
    // Observe preferences which may change on other screens
    //
    // "If your app targets iOS 9.0 and later or macOS 10.11 and later,
    // you don't need to unregister an observer in its dealloc method."
    for (NSString *pref in self.observedNotifications) {
        [NSNotificationCenter.defaultCenter
            addObserver:self
            selector:@selector(fullyReloadData)
            name:pref
            object:nil
        ];
    }
}

- (BOOL)scrollViewShouldScrollToTop:(UIScrollView *)scrollView {
    [self.navigationController setToolbarHidden:NO animated:YES];
    return YES;
}


#pragma mark - Overrides

/// Override to hide the description section when searching
- (NSArray<FLEXTableViewSection *> *)nonemptySections {
    if (self.shouldShowDescription) {
        return super.nonemptySections;
    }
    
    return [super.nonemptySections flex_filtered:^BOOL(FLEXTableViewSection *section, NSUInteger idx) {
        return section != self.descriptionSection;
    }];
}

- (NSArray<FLEXTableViewSection *> *)makeSections {
    FLEXObjectExplorer *explorer = self.explorer;
    
    // Description section is only for instances
    if (self.explorer.objectIsInstance) {
        _descriptionSection = [FLEXSingleRowSection
            title:@"Description" reuse:kFLEXMultilineCell cell:^(FLEXTableViewCell *cell) {
                cell.titleLabel.font = UIFont.flex_defaultTableCellFont;
                cell.titleLabel.text = explorer.objectDescription;
            }
        ];
        self.descriptionSection.filterMatcher = ^BOOL(NSString *filterText) {
            return [explorer.objectDescription localizedCaseInsensitiveContainsString:filterText];
        };
    }

    // Object graph section
    FLEXSingleRowSection *referencesSection = [FLEXSingleRowSection
        title:@"Object Graph" reuse:kFLEXDefaultCell cell:^(FLEXTableViewCell *cell) {
            cell.titleLabel.text = @"See Objects with References to This Object";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    ];
    referencesSection.selectionAction = ^(UIViewController *host) {
        UIViewController *references = [FLEXObjectListViewController
            objectsWithReferencesToObject:explorer.object
            retained:NO
        ];
        [host.navigationController pushViewController:references animated:YES];
    };

    NSMutableArray *sections = [NSMutableArray arrayWithArray:@[
        [FLEXMetadataSection explorer:self.explorer kind:FLEXMetadataKindProperties],
        [FLEXMetadataSection explorer:self.explorer kind:FLEXMetadataKindClassProperties],
        [FLEXMetadataSection explorer:self.explorer kind:FLEXMetadataKindIvars],
        [FLEXMetadataSection explorer:self.explorer kind:FLEXMetadataKindMethods],
        [FLEXMetadataSection explorer:self.explorer kind:FLEXMetadataKindClassMethods],
        [FLEXMetadataSection explorer:self.explorer kind:FLEXMetadataKindClassHierarchy],
        [FLEXMetadataSection explorer:self.explorer kind:FLEXMetadataKindProtocols],
        [FLEXMetadataSection explorer:self.explorer kind:FLEXMetadataKindOther],
        referencesSection
    ]];

    if (self.customSections) {
        [sections insertObjects:self.customSections atIndexes:[NSIndexSet
            indexSetWithIndexesInRange:NSMakeRange(0, self.customSections.count)
        ]];
    }
    if (self.descriptionSection) {
        [sections insertObject:self.descriptionSection atIndex:0];
    }

    return sections.copy;
}

/// In our case, all this does is reload the table view,
/// or reload the sections' data if we changed places
/// in the class hierarchy. Doesn't refresh \c self.explorer
- (void)reloadData {
    // Check to see if class scope changed, update accordingly
    if (self.explorer.classScope != self.selectedScope) {
        self.explorer.classScope = self.selectedScope;
        [self reloadSections];
    }
    
    [super reloadData];
}

- (void)shareButtonPressed:(UIBarButtonItem *)sender {
    [FLEXAlert makeSheet:^(FLEXAlert *make) {
        make.button(@"Add to Bookmarks").handler(^(NSArray<NSString *> *strings) {
            [FLEXBookmarkManager.bookmarks addObject:self.object];
        });
        make.button(@"Copy Description").handler(^(NSArray<NSString *> *strings) {
            UIPasteboard.generalPasteboard.string = self.explorer.objectDescription;
        });
        make.button(@"Copy Address").handler(^(NSArray<NSString *> *strings) {
            UIPasteboard.generalPasteboard.string = [FLEXUtility addressOfObject:self.object];
        });
        make.button(@"Cancel").cancelStyle();
    } showFrom:self source:sender];
}


#pragma mark - Private

/// Unlike \c -reloadData, this refreshes everything, including the explorer.
- (void)fullyReloadData {
    [self.explorer reloadMetadata];
    [self reloadSections];
    [self reloadData];
}

- (void)handleSwipeGesture:(UISwipeGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateEnded) {
        switch (gesture.direction) {
            case UISwipeGestureRecognizerDirectionRight:
                if (self.selectedScope > 0) {
                    self.selectedScope -= 1;
                }
                break;
            case UISwipeGestureRecognizerDirectionLeft:
                if (self.selectedScope != self.explorer.classHierarchy.count - 1) {
                    self.selectedScope += 1;
                }
                break;

            default:
                break;
        }
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g1 shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)g2 {
    // Prioritize important pan gestures over our swipe gesture
    if ([g2 isKindOfClass:[UIPanGestureRecognizer class]]) {
        if (g2 == self.navigationController.interactivePopGestureRecognizer) {
            return NO;
        }
        
        if (g2 == self.tableView.panGestureRecognizer) {
            return NO;
        }
    }
    
    return YES;
}

- (BOOL)gestureRecognizerShouldBegin:(UISwipeGestureRecognizer *)gesture {
    // Don't allow swiping from the carousel
    CGPoint location = [gesture locationInView:self.tableView];
    if ([self.carousel hitTest:location withEvent:nil]) {
        return NO;
    }
    
    return YES;
}
    
- (void)moreButtonPressed:(UIBarButtonItem *)sender {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    // Maps preference keys to a description of what they affect
    NSDictionary<NSString *, NSString *> *explorerToggles = @{
        kFLEXDefaultsHidePropertyIvarsKey:    @"Property-Backing Ivars",
        kFLEXDefaultsHidePropertyMethodsKey:  @"Property-Backing Methods",
        kFLEXDefaultsHidePrivateMethodsKey:   @"Likely Private Methods",
        kFLEXDefaultsShowMethodOverridesKey:  @"Method Overrides",
        kFLEXDefaultsHideVariablePreviewsKey: @"Variable Previews"
    };
    
    // Maps the key of the action itself to a map of a description
    // of the action ("hide X") mapped to the current state.
    //
    // So keys that are hidden by default have NO mapped to "Show"
    NSDictionary<NSString *, NSDictionary *> *nextStateDescriptions = @{
        kFLEXDefaultsHidePropertyIvarsKey:    @{ @NO: @"Hide ", @YES: @"Show " },
        kFLEXDefaultsHidePropertyMethodsKey:  @{ @NO: @"Hide ", @YES: @"Show " },
        kFLEXDefaultsHidePrivateMethodsKey:   @{ @NO: @"Hide ", @YES: @"Show " },
        kFLEXDefaultsShowMethodOverridesKey:  @{ @NO: @"Show ", @YES: @"Hide " },
        kFLEXDefaultsHideVariablePreviewsKey: @{ @NO: @"Hide ", @YES: @"Show " },
    };
    
    [FLEXAlert makeSheet:^(FLEXAlert *make) {
        make.title(@"Options");
        
        for (NSString *option in explorerToggles.allKeys) {
            BOOL current = [defaults boolForKey:option];
            NSString *title = [nextStateDescriptions[option][@(current)]
                stringByAppendingString:explorerToggles[option]
            ];
            make.button(title).handler(^(NSArray<NSString *> *strings) {
                [NSUserDefaults.standardUserDefaults flex_toggleBoolForKey:option];
                [self fullyReloadData];
            });
        }
        
        make.button(@"Cancel").cancelStyle();
    } showFrom:self source:sender];
}

#pragma mark - Description

- (BOOL)shouldShowDescription {
    // Hide if we have filter text; it is rarely
    // useful to see the description when searching
    // since it's already at the top of the screen
    if (self.filterText.length) {
        return NO;
    }

    return YES;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    // For the description section, we want that nice slim/snug looking row.
    // Other rows use the automatic size.
    FLEXTableViewSection *section = self.filterDelegate.sections[indexPath.section];
    
    if (section == self.descriptionSection) {
        NSAttributedString *attributedText = [[NSAttributedString alloc]
            initWithString:self.explorer.objectDescription
            attributes:@{ NSFontAttributeName : UIFont.flex_defaultTableCellFont }
        ];
        
        return [FLEXMultilineTableViewCell
            preferredHeightWithAttributedText:attributedText
            maxWidth:tableView.frame.size.width - tableView.separatorInset.right
            style:tableView.style
            showsAccessory:NO
        ];
    }

    return UITableViewAutomaticDimension;
}

- (BOOL)tableView:(UITableView *)tableView shouldShowMenuForRowAtIndexPath:(NSIndexPath *)indexPath {
    return self.filterDelegate.sections[indexPath.section] == self.descriptionSection;
}

- (BOOL)tableView:(UITableView *)tableView canPerformAction:(SEL)action forRowAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender {
    // Only the description section has "actions"
    if (self.filterDelegate.sections[indexPath.section] == self.descriptionSection) {
        return action == @selector(copy:);
    }

    return NO;
}

- (void)tableView:(UITableView *)tableView performAction:(SEL)action forRowAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender {
    if (action == @selector(copy:)) {
        UIPasteboard.generalPasteboard.string = self.explorer.objectDescription;
    }
}

@end
