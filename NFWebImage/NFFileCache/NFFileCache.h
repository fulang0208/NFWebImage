//
//  NFFileCache.h
//  NFMemoryCache
//
//  Created by fulang on 2018/3/8.
//  Copyright © 2018年 fulang. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NFFileCache : NSObject

@property (nonatomic,copy) NSString *name;

@property (nonatomic,readonly) NSString *directoryPath;

@property (nonatomic,assign,readonly) int64_t totalSize;

@property (nonatomic,copy) NSData *(^customArchiveBlock)(id object);
@property (nonatomic,copy) id(^customUnArchiveBlock)(NSData *data);
@property (nonatomic,copy) NSString *(^customFileNameBlock)(NSString *key);

- (BOOL)containsObjectForKey:(NSString *)key;
- (id)objectForKey:(NSString *)key;
- (void)objectForKey:(NSString *)key withBlock:(void(^)(NSString *key, id object))block;
- (void)setObject:(id)object forKey:(NSString *)key;
- (void)setObject:(id)object forKey:(NSString *)key withBlock:(void(^)(void))block;
- (void)removeObjectForKey:(NSString *)key;
- (void)removeAllObject;

@end
