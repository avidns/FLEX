//
//  FLEXShortcutsSection.m
//  FLEX
//
//  Created by Tanner Bennett on 8/29/19.
//  Copyright © 2020 FLEX Team. All rights reserved.
//

#import "Classes/Headers/FLEXShortcutsSection.h"
#import "Classes/Headers/FLEXTableView.h"
#import "Classes/Headers/FLEXTableViewCell.h"
#import "Classes/Utility/FLEXUtility.h"
#import "Classes/Headers/FLEXShortcut.h"
#import "Classes/Utility/Runtime/Objc/Reflection/FLEXProperty.h"
#import "Classes/Utility/Runtime/Objc/Reflection/FLEXPropertyAttributes.h"
#import "Classes/Utility/Runtime/Objc/Reflection/FLEXIvar.h"
#import "Classes/Utility/Runtime/Objc/Reflection/FLEXMethod.h"
#import "Classes/Utility/Categories/FLEXRuntime+UIKitHelpers.h"
#import "Classes/Headers/FLEXObjectExplorer.h"

#pragma mark Private

@interface FLEXShortcutsSection ()
@property (nonatomic, copy) NSArray<NSString *> *titles;
@property (nonatomic, copy) NSArray<NSString *> *subtitles;

@property (nonatomic, copy) NSArray<NSString *> *allTitles;
@property (nonatomic, copy) NSArray<NSString *> *allSubtitles;

// Shortcuts are not used if initialized with static titles and subtitles
@property (nonatomic, copy) NSArray<id<FLEXShortcut>> *shortcuts;
@property (nonatomic, readonly) NSArray<id<FLEXShortcut>> *allShortcuts;
@end

@implementation FLEXShortcutsSection
@synthesize isNewSection = _isNewSection;

#pragma mark Initialization

+ (instancetype)forObject:(id)objectOrClass rowTitles:(NSArray<NSString *> *)titles {
    return [self forObject:objectOrClass rowTitles:titles rowSubtitles:nil];
}

+ (instancetype)forObject:(id)objectOrClass
                rowTitles:(NSArray<NSString *> *)titles
             rowSubtitles:(NSArray<NSString *> *)subtitles {
    return [[self alloc] initWithObject:objectOrClass titles:titles subtitles:subtitles];
}

+ (instancetype)forObject:(id)objectOrClass rows:(NSArray *)rows {
    return [[self alloc] initWithObject:objectOrClass rows:rows isNewSection:YES];
}

+ (instancetype)forObject:(id)objectOrClass additionalRows:(NSArray *)toPrepend {
    NSArray *rows = [FLEXShortcutsFactory shortcutsForObjectOrClass:objectOrClass];
    NSArray *allRows = [toPrepend arrayByAddingObjectsFromArray:rows] ?: rows;
    return [[self alloc] initWithObject:objectOrClass rows:allRows isNewSection:NO];
}

+ (instancetype)forObject:(id)objectOrClass {
    return [self forObject:objectOrClass additionalRows:nil];
}

- (id)initWithObject:(id)object
              titles:(NSArray<NSString *> *)titles
           subtitles:(NSArray<NSString *> *)subtitles {

    NSParameterAssert(titles.count == subtitles.count || !subtitles);
    NSParameterAssert(titles.count);

    self = [super init];
    if (self) {
        _object = object;
        _allTitles = titles.copy;
        _allSubtitles = subtitles.copy;
        _isNewSection = YES;
        _numberOfLines = 1;
    }

    return self;
}

- (id)initWithObject:object rows:(NSArray *)rows isNewSection:(BOOL)newSection {
    self = [super init];
    if (self) {
        _object = object;
        _isNewSection = newSection;
        
        _allShortcuts = [rows flex_mapped:^id(id obj, NSUInteger idx) {
            return [FLEXShortcut shortcutFor:obj];
        }];
        _numberOfLines = 1;
        
        // Populate titles and subtitles
        [self reloadData];
    }

    return self;
}


#pragma mark - Public

- (void)setCacheSubtitles:(BOOL)cacheSubtitles {
    if (_cacheSubtitles == cacheSubtitles) return;

    // cacheSubtitles only applies if we have shortcut objects
    if (self.allShortcuts) {
        _cacheSubtitles = cacheSubtitles;
        [self reloadData];
    } else {
        NSLog(@"Warning: setting 'cacheSubtitles' on a shortcut section with static subtitles");
    }
}


#pragma mark - Overrides

- (UITableViewCellAccessoryType)accessoryTypeForRow:(NSInteger)row {
    if (_allShortcuts) {
        return [self.shortcuts[row] accessoryTypeWith:self.object];
    }
    
    return UITableViewCellAccessoryNone;
}

- (void)setFilterText:(NSString *)filterText {
    super.filterText = filterText;

    NSAssert(
        self.allTitles.count == self.allSubtitles.count,
        @"Each title needs a (possibly empty) subtitle"
    );

    if (filterText.length) {
        // Tally up indexes of titles and subtitles matching the filter
        NSMutableIndexSet *filterMatches = [NSMutableIndexSet new];
        id filterBlock = ^BOOL(NSString *obj, NSUInteger idx) {
            if ([obj localizedCaseInsensitiveContainsString:filterText]) {
                [filterMatches addIndex:idx];
                return YES;
            }

            return NO;
        };

        // Get all matching indexes, including subtitles
        [self.allTitles flex_forEach:filterBlock];
        [self.allSubtitles flex_forEach:filterBlock];
        // Filter to matching indexes only
        self.titles    = [self.allTitles objectsAtIndexes:filterMatches];
        self.subtitles = [self.allSubtitles objectsAtIndexes:filterMatches];
        self.shortcuts = [self.allShortcuts objectsAtIndexes:filterMatches];
    } else {
        self.shortcuts = self.allShortcuts;
        self.titles    = self.allTitles;
        self.subtitles = [self.allSubtitles flex_filtered:^BOOL(NSString *sub, NSUInteger idx) {
            return sub.length > 0;
        }];
    }
}

- (void)reloadData {
    [FLEXObjectExplorer configureDefaultsForItems:self.allShortcuts];
    
    // Generate all (sub)titles from shortcuts
    if (self.allShortcuts) {
        self.allTitles = [self.allShortcuts flex_mapped:^id(id<FLEXShortcut> s, NSUInteger idx) {
            return [s titleWith:self.object];
        }];
        self.allSubtitles = [self.allShortcuts flex_mapped:^id(id<FLEXShortcut> s, NSUInteger idx) {
            return [s subtitleWith:self.object] ?: @"";
        }];
    }

    // Re-generate filtered (sub)titles and shortcuts
    self.filterText = self.filterText;
}

- (NSString *)title {
    return @"Shortcuts";
}

- (NSInteger)numberOfRows {
    return self.titles.count;
}

- (BOOL)canSelectRow:(NSInteger)row {
    UITableViewCellAccessoryType type = [self.shortcuts[row] accessoryTypeWith:self.object];
    BOOL hasDisclosure = NO;
    hasDisclosure |= type == UITableViewCellAccessoryDisclosureIndicator;
    hasDisclosure |= type == UITableViewCellAccessoryDetailDisclosureButton;
    return hasDisclosure;
}

- (void (^)(__kindof UIViewController *))didSelectRowAction:(NSInteger)row {
    return [self.shortcuts[row] didSelectActionWith:self.object];
}

- (UIViewController *)viewControllerToPushForRow:(NSInteger)row {
    /// Nil if shortcuts is nil, i.e. if initialized with forObject:rowTitles:rowSubtitles:
    return [self.shortcuts[row] viewerWith:self.object];
}

- (void (^)(__kindof UIViewController *))didPressInfoButtonAction:(NSInteger)row {
    id<FLEXShortcut> shortcut = self.shortcuts[row];
    if ([shortcut respondsToSelector:@selector(editorWith:forSection:)]) {
        id object = self.object;
        return ^(UIViewController *host) {
            UIViewController *editor = [shortcut editorWith:object forSection:self];
            [host.navigationController pushViewController:editor animated:YES];
        };
    }

    return nil;
}

- (NSString *)reuseIdentifierForRow:(NSInteger)row {
    FLEXTableViewCellReuseIdentifier defaultReuse = kFLEXDetailCell;
    if (@available(iOS 11, *)) {
        defaultReuse = kFLEXMultilineDetailCell;
    }
    
    return [self.shortcuts[row] customReuseIdentifierWith:self.object] ?: defaultReuse;
}

- (void)configureCell:(__kindof FLEXTableViewCell *)cell forRow:(NSInteger)row {
    cell.titleLabel.text = [self titleForRow:row];
    cell.titleLabel.numberOfLines = self.numberOfLines;
    cell.subtitleLabel.text = [self subtitleForRow:row];
    cell.subtitleLabel.numberOfLines = self.numberOfLines;
    cell.accessoryType = [self accessoryTypeForRow:row];
}

- (NSString *)titleForRow:(NSInteger)row {
    return self.titles[row];
}

- (NSString *)subtitleForRow:(NSInteger)row {
    // Case: dynamic, uncached subtitles
    if (!self.cacheSubtitles) {
        NSString *subtitle = [self.shortcuts[row] subtitleWith:self.object];
        return subtitle.length ? subtitle : nil;
    }

    // Case: static subtitles, or cached subtitles
    return self.subtitles[row];
}

@end


#pragma mark - Global shortcut registration

@interface FLEXShortcutsFactory () {
    BOOL _append, _prepend, _replace, _notInstance;
    NSArray<NSString *> *_properties, *_ivars, *_methods;
}
@end

#define NewAndSet(ivar) ({ FLEXShortcutsFactory *r = [self sharedFactory]; r->ivar = YES; r; })
#define SetIvar(ivar) ({ self->ivar = YES; self; })
#define SetParamBlock(ivar) ^(NSArray *p) { self->ivar = p; return self; }

typedef NSMutableDictionary<Class, NSMutableArray<id<FLEXRuntimeMetadata>> *> RegistrationBuckets;

@implementation FLEXShortcutsFactory {
    // Class buckets
    RegistrationBuckets *cProperties;
    RegistrationBuckets *cIvars;
    RegistrationBuckets *cMethods;
    // Metaclass buckets
    RegistrationBuckets *mProperties;
    RegistrationBuckets *mMethods;
}

+ (instancetype)sharedFactory {
    static FLEXShortcutsFactory *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [self new];
    });
    
    return shared;
}

- (id)init {
    self = [super init];
    if (self) {
        cProperties = [NSMutableDictionary new];
        cIvars = [NSMutableDictionary new];
        cMethods = [NSMutableDictionary new];

        mProperties = [NSMutableDictionary new];
        mMethods = [NSMutableDictionary new];
    }
    
    return self;
}

+ (NSArray<id<FLEXRuntimeMetadata>> *)shortcutsForObjectOrClass:(id)objectOrClass {
    return [[self sharedFactory] shortcutsForObjectOrClass:objectOrClass];
}

- (NSArray<id<FLEXRuntimeMetadata>> *)shortcutsForObjectOrClass:(id)objectOrClass {
    NSParameterAssert(objectOrClass);

    NSMutableArray<id<FLEXRuntimeMetadata>> *shortcuts = [NSMutableArray new];
    BOOL isClass = object_isClass(objectOrClass);
    // The -class does not give you a metaclass, and we want a metaclass
    // if a class is passed in, or a class if an object is passed in
    Class classKey = object_getClass(objectOrClass);
    
    RegistrationBuckets *propertyBucket = isClass ? mProperties : cProperties;
    RegistrationBuckets *methodBucket = isClass ? mMethods : cMethods;
    RegistrationBuckets *ivarBucket = isClass ? nil : cIvars;

    BOOL stop = NO;
    while (!stop && classKey) {
        NSArray *properties = propertyBucket[classKey];
        NSArray *ivars = ivarBucket[classKey];
        NSArray *methods = methodBucket[classKey];

        // Stop if we found anything
        stop = properties || ivars || methods;
        if (stop) {
            // Add things we found to the list
            [shortcuts addObjectsFromArray:properties];
            [shortcuts addObjectsFromArray:ivars];
            [shortcuts addObjectsFromArray:methods];
        } else {
            classKey = class_getSuperclass(classKey);
        }
    }
    
    [FLEXObjectExplorer configureDefaultsForItems:shortcuts];
    return shortcuts;
}

+ (FLEXShortcutsFactory *)append {
    return NewAndSet(_append);
}

+ (FLEXShortcutsFactory *)prepend {
    return NewAndSet(_prepend);
}

+ (FLEXShortcutsFactory *)replace {
    return NewAndSet(_replace);
}

- (void)_register:(NSArray<id<FLEXRuntimeMetadata>> *)items to:(RegistrationBuckets *)global class:(Class)key {
    @synchronized (self) {
        // Get (or initialize) the bucket for this class
        NSMutableArray *bucket = ({
            id bucket = global[key];
            if (!bucket) {
                bucket = [NSMutableArray new];
                global[(id)key] = bucket;
            }
            bucket;
        });

        if (self->_append)  { [bucket addObjectsFromArray:items]; }
        if (self->_replace) { [bucket setArray:items]; }
        if (self->_prepend) {
            if (bucket.count) {
                // Set new items as array, add old items behind them
                id copy = bucket.copy;
                [bucket setArray:items];
                [bucket addObjectsFromArray:copy];
            } else {
                [bucket addObjectsFromArray:items];
            }
        }
    }
}

- (void)reset {
    _append = NO;
    _prepend = NO;
    _replace = NO;
    _notInstance = NO;
    
    _properties = nil;
    _ivars = nil;
    _methods = nil;
}

- (FLEXShortcutsFactory *)class {
    return SetIvar(_notInstance);
}

- (FLEXShortcutsFactoryNames)properties {
    NSAssert(!_notInstance, @"Do not try to set properties+classProperties at the same time");
    return SetParamBlock(_properties);
}

- (FLEXShortcutsFactoryNames)classProperties {
    _notInstance = YES;
    return SetParamBlock(_properties);
}

- (FLEXShortcutsFactoryNames)ivars {
    return SetParamBlock(_ivars);
}

- (FLEXShortcutsFactoryNames)methods {
    NSAssert(!_notInstance, @"Do not try to set methods+classMethods at the same time");
    return SetParamBlock(_methods);
}

- (FLEXShortcutsFactoryNames)classMethods {
    _notInstance = YES;
    return SetParamBlock(_methods);
}

- (FLEXShortcutsFactoryTarget)forClass {
    return ^(Class cls) {
        NSAssert(
            ( self->_append && !self->_prepend && !self->_replace) ||
            (!self->_append &&  self->_prepend && !self->_replace) ||
            (!self->_append && !self->_prepend &&  self->_replace),
            @"You can only do one of [append, prepend, replace]"
        );

        
        /// Whether the metadata we're about to add is instance or
        /// class metadata, i.e. class properties vs instance properties
        BOOL instanceMetadata = !self->_notInstance;
        /// Whether the given class is a metaclass or not; we need to switch to
        /// the metaclass to add class metadata if we are given the normal class object
        BOOL isMeta = class_isMetaClass(cls);
        /// Whether the shortcuts we're about to add should appear for classes or instances
        BOOL instanceShortcut = !isMeta;
        
        if (instanceMetadata) {
            NSAssert(!isMeta,
                @"Instance metadata can only be added as an instance shortcut"
            );
        }
        
        Class metaclass = isMeta ? cls : object_getClass(cls);
        Class clsForMetadata = instanceMetadata ? cls : metaclass;
        
        // The factory is a singleton so we don't need to worry about "leaking" it
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wimplicit-retain-self"
        
        RegistrationBuckets *propertyBucket = instanceShortcut ? cProperties : mProperties;
        RegistrationBuckets *methodBucket = instanceShortcut ? cMethods : mMethods;
        RegistrationBuckets *ivarBucket = instanceShortcut ? cIvars : nil;
        
        #pragma clang diagnostic pop

        if (self->_properties) {
            NSArray *items = [self->_properties flex_mapped:^id(NSString *name, NSUInteger idx) {
                return [FLEXProperty named:name onClass:clsForMetadata];
            }];
            [self _register:items to:propertyBucket class:cls];
        }

        if (self->_methods) {
            NSArray *items = [self->_methods flex_mapped:^id(NSString *name, NSUInteger idx) {
                return [FLEXMethod selector:NSSelectorFromString(name) class:clsForMetadata];
            }];
            [self _register:items to:methodBucket class:cls];
        }

        if (self->_ivars) {
            NSAssert(instanceMetadata, @"Instance metadata can only be added as an instance shortcut (%@)", cls);
            NSArray *items = [self->_ivars flex_mapped:^id(NSString *name, NSUInteger idx) {
                return [FLEXIvar named:name onClass:clsForMetadata];
            }];
            [self _register:items to:ivarBucket class:cls];
        }
        
        [self reset];
    };
}

@end
