//
//  NFMemoryCache.m
//  NFMemoryCache
//
//  Created by fulang on 2018/3/6.
//  Copyright © 2018年 fulang. All rights reserved.
//

#import "NFMemoryCache.h"
#import <UIKit/UIKit.h>

#define defaultCountLimit   50
#define defaultPoisonRatio  0.3

@interface _LinkedNode : NSObject {
    @package
    NSString *_key;
    id _object;
    __weak _LinkedNode *_prev;
    __weak _LinkedNode *_next;
}
- (instancetype)initWithKey:(NSString *)key object:(id)object;
+ (_LinkedNode *)nodeWithKey:(NSString *)key object:(id)object;
@end

@implementation _LinkedNode
- (instancetype)initWithKey:(NSString *)key object:(id)object {
    self = [super init];
    _key = key;
    _object = object;
    return self;
}
+ (_LinkedNode *)nodeWithKey:(NSString *)key object:(id)object {
    return [[_LinkedNode alloc] initWithKey:key object:object];
}

@end

@interface _LinkedMap : NSObject {
    @package
    NSMutableDictionary *_nodeMap;
    __weak _LinkedNode *_head;
    __weak _LinkedNode *_tail;
}

- (NSUInteger)totalCount;

- (BOOL)containsNodeForKey:(NSString *)key;
- (_LinkedNode *)nodeForKey:(NSString *)key;
- (void)insertNodeAtHead:(_LinkedNode *)node;
- (void)bringNodeToHead:(_LinkedNode *)node;
- (void)removeNode:(_LinkedNode *)node;
- (_LinkedNode *)removeLastNode;
- (void)removeAllNode;

@end

@implementation _LinkedMap

- (instancetype)init {
    self = [super init];
    _nodeMap = @[].mutableCopy;
    return self;
}

- (NSUInteger)totalCount {
    return _nodeMap.count;
}

- (BOOL)containsNodeForKey:(NSString *)key {
    return _nodeMap[key] != nil;
}

- (_LinkedNode *)nodeForKey:(NSString *)key {
    return _nodeMap[key];
}

- (void)appendNodeToTail:(_LinkedNode *)node {
    if (node == nil) { return; }
    _nodeMap[node->_key] = node;
    if (_head == nil) {
        _head = _tail = node;
        return;
    }
    _tail->_next    = node;
    node->_prev     = _tail;
    _tail           = node;
}

- (void)insertNodeAtHead:(_LinkedNode *)node {
    if (node == nil) { return; }
    _nodeMap[node->_key] = node;
    if (_head == nil) {
        _head = _tail = node;
        return;
    }
    _head->_prev = node;
    node->_next = _head;
    _head = node;
}

- (void)bringNodeToHead:(_LinkedNode *)node {
    if (node == _head) { return; }
    if (node == _tail) {
        _tail = node->_prev;
        _tail->_next = nil;
    }else {
        node->_prev->_next = node->_next;
        node->_next->_prev = node->_prev;
    }
    node->_next = _head;
    node->_prev = nil;
    _head->_prev = node;
    _head = node;
}

- (void)removeNode:(_LinkedNode *)node {
    if (node == nil) { return; }
    if (node == _head) { _head = node->_next; }
    if (node == _tail) { _tail = node->_prev; }
    if (node->_next != nil) {
        node->_next->_prev = node->_prev;
    }
    if (node->_prev != nil) {
        node->_prev->_next = node->_next;
    }
    _nodeMap[node->_key] = nil;
}

- (_LinkedNode *)removeLastNode {
    if (_tail == nil) { return nil; }
    _LinkedNode *tailNode = _tail;
    _nodeMap[_tail->_key] = nil;
    if (_head == _tail) {
        _head = _tail = nil;
    }else {
        _tail->_prev->_next = nil;
        _tail->_prev = nil;
    }
    return tailNode;
}

- (void)removeAllNode {
    _head = nil;
    _tail = nil;
    if (_nodeMap.count > 0) {
        NSDictionary *holder = _nodeMap;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            [holder count];
        });
        _nodeMap = @[].mutableCopy;
    }
}

@end

@implementation NFMemoryCache {
    _LinkedMap *_cacheMap;
    _LinkedMap *_poisonMap;
    NSLock *_lock;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (instancetype)init {
    self = [super init];
    _cacheMap       = [_LinkedMap new];
    _poisonMap      = [_LinkedMap new];
    _lock           = [[NSLock alloc] init];
    _countLimit     = defaultCountLimit;
    _poisonLimit    = defaultCountLimit * defaultPoisonRatio;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_didReceiveMemoryWarning) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_didEnterBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
    return self;
}
#pragma mark - Public

- (BOOL)containsObjectForKey:(NSString *)key {
    return ([_cacheMap containsNodeForKey:key] || [_poisonMap containsNodeForKey:key]);
}

- (id)cachedObjectForKey:(NSString *)key {
    if (key.length == 0) {
        return nil;
    }
    [_lock lock];
    _LinkedNode *target = [_poisonMap nodeForKey:key];
    if (target != nil) {
        [_poisonMap removeNode:target];
        [_cacheMap insertNodeAtHead:target];
        [self _trimMap:_cacheMap toCount:_countLimit - _poisonLimit];
    }else if ([_cacheMap containsNodeForKey:key]) {
        target = [_cacheMap nodeForKey:key];
        [_cacheMap bringNodeToHead:target];
    }
    [_lock unlock];
    if (target) {
        return target->_object;
    }
    return nil;
}

- (void)setCacheObject:(id)object forKey:(NSString *)key {
    if (key.length == 0) { return; }
    [_lock lock];
    if (object == nil) {
        [self removeObjectForKey:key];
    }else {
        _LinkedNode *target = [self _nodeForKey:key];
        if (target == nil) {
            target = [_LinkedNode nodeWithKey:key object:object];
            [_poisonMap insertNodeAtHead:target];
        }else {
            target->_object = object;
        }
    }
    [_lock unlock];
    [self _trimMap:_poisonMap toCount:_poisonLimit];
}

- (id)removeObjectForKey:(NSString *)key {
    if (key.length == 0) { return nil; }
    [_lock lock];
    _LinkedNode *target = [_poisonMap nodeForKey:key];
    if (target != nil) {
        [_poisonMap removeNode:target];
    }else if ([_cacheMap containsNodeForKey:key]){
        target = [_cacheMap nodeForKey:key];
        [_cacheMap removeNode:target];
    }
    [_lock unlock];
    if (target != nil) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            [target description];
        });
        return target->_object;
    }
    return nil;
}

- (void)removeAllObjects {
    [self _trimToCount:0];
}

- (void)removePoisonObjects {
    [self _trimMap:_poisonMap toCount:0];
}

#pragma mark - Notification Responder
- (void)_didReceiveMemoryWarning {
    if (self.didReceiveMemoryWarningBlock) {
        self.didReceiveMemoryWarningBlock(self);
    }
    if (self.shouldRemoveAllObjectsOnMemoryWarning) {
        [self removeAllObjects];
    }
}

- (void)_didEnterBackground {
    if (self.didEnterBackgroundBlock) {
        self.didEnterBackgroundBlock(self);
    }
    if (self.shouldRemoveAllObjectsWhenEnterBackground) {
        [self removeAllObjects];
    }
}

#pragma mark - private

- (_LinkedNode *)_nodeForKey:(NSString *)key {
    _LinkedNode *target = [_poisonMap nodeForKey:key];
    if (target == nil) {
        target = [_cacheMap nodeForKey:key];
    }
    return target;
}

#pragma mark - private (trim)
- (void)_trimToCount:(NSUInteger)count {
    if (count > _cacheMap.totalCount + _poisonMap.totalCount) {
        return;
    }
    [self _trimMap:_cacheMap toCount:_countLimit - _poisonLimit];
    [self _trimMap:_poisonMap toCount:_poisonLimit];
}

- (void)_trimMap:(_LinkedMap *)map toCount:(NSUInteger)count {
    BOOL isFinished = NO;
    [_lock lock];
    if (count >= map.totalCount) {
        isFinished = YES;
    }else if (count == 0) {
        [map removeAllNode];
        isFinished = YES;
    }
    [_lock unlock];
    if (isFinished) return;
    NSMutableArray *tempHolder = [NSMutableArray array];
    while (!isFinished) {
        [_lock lock];
        _LinkedNode *tail = [_cacheMap removeLastNode];
        if (tail != nil) {
            [tempHolder addObject:tail];
        }
        isFinished = (count >= map.totalCount);
        [_lock unlock];
    }
    if (tempHolder.count > 0) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            [tempHolder count];
        });
    }
}

#pragma mark - Accessor
- (NSUInteger)totalCount {
    return _cacheMap.totalCount + _poisonMap.totalCount;
}

- (void)setCountLimit:(NSUInteger)countLimit {
    _countLimit     = countLimit;
    _poisonLimit    = countLimit * defaultPoisonRatio;
    [self _trimToCount:_countLimit];
}

- (void)setPoisonLimit:(NSUInteger)poisonLimit {
    _poisonLimit = poisonLimit;
    [self _trimMap:_poisonMap toCount:_poisonLimit];
}

@end
