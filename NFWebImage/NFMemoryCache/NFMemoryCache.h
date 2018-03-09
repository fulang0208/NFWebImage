//
//  NFMemoryCache.h
//  NFMemoryCache
//
//  Created by fulang on 2018/3/6.
//  Copyright © 2018年 fulang. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NFMemoryCache : NSObject

@property (nonatomic,copy) NSString *name;
@property (nonatomic,assign,readonly) NSUInteger totalCount;

@property (nonatomic,assign) NSUInteger countLimit;
@property (nonatomic,assign) NSUInteger poisonLimit;

@property (nonatomic,assign) BOOL shouldRemoveAllObjectsOnMemoryWarning;
@property (nonatomic,assign) BOOL shouldRemoveAllObjectsWhenEnterBackground;

@property (nonatomic,copy) void(^didReceiveMemoryWarningBlock)(NFMemoryCache *cache);
@property (nonatomic,copy) void(^didEnterBackgroundBlock)(NFMemoryCache *cache);

- (BOOL)containsObjectForKey:(NSString *)key;
- (id)cachedObjectForKey:(NSString *)key;
- (void)setCacheObject:(id)object forKey:(NSString *)key;
- (id)removeObjectForKey:(NSString *)key;
- (void)removeAllObjects;
- (void)removePoisonObjects;

@end
