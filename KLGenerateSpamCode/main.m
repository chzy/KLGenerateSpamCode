//
//  main.m
//  generateSpamCode
//
//  Created by 柯磊 on 2017/7/5.
//  Copyright © 2017年 GAEA. All rights reserved.
//

#import <Foundation/Foundation.h>
#include <stdlib.h>

typedef NS_ENUM(NSInteger, GSCSourceType) {
    GSCSourceTypeClass,
    GSCSourceTypeCategory,
};

void recursiveDirectory(NSString *directory, void(^handleFile)(NSString *mFilePath));
void generateSpamCodeFile(NSString *outDirectory, NSString *mFilePath, GSCSourceType type);
NSString *randomString(NSInteger length);
void handleXcassetsFiles(NSString *directory);
void deleteComments(NSString *directory);

// 命令行修改工程目录下所有 png 资源 hash 值
// 使用 ImageMagick 进行图片压缩，所以需要安装 ImageMagick，安装方法 brew install imagemagick
// find . -iname "*.png" -exec echo {} \; -exec convert {} {} \;
// or
// find . -iname "*.png" -exec echo {} \; -exec convert {} -quality 95 {} \;

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSArray<NSString *> *arguments = [[NSProcessInfo processInfo] arguments];
        if (!arguments || arguments.count <= 1) {
            printf("缺少工程目录参数\n");
            return 1;
        }
        if (arguments.count <= 2) {
            printf("缺少任务参数 -spamCodeOut or -handleXcassets or -deleteComments\n");
            return 1;
        }
        
        BOOL isDirectory = NO;
        NSString *projectDirString = nil;
        NSString *outDirString = nil;
        BOOL needHandleXcassets = NO;
        BOOL needDeleteComments = NO;
        
        NSFileManager *fm = [NSFileManager defaultManager];
        for (NSInteger i = 1; i < arguments.count; i++) {
            NSString *argument = arguments[i];
            if (i == 1) {
                projectDirString = argument;
                if (![fm fileExistsAtPath:projectDirString isDirectory:&isDirectory]) {
                    printf("%s不存在\n", [projectDirString UTF8String]);
                    return 1;
                }
                if (!isDirectory) {
                    printf("%s不是目录\n", [projectDirString UTF8String]);
                    return 1;
                }
                continue;
            }
            if ([argument isEqualToString:@"-spamCodeOut"]) {
                outDirString = arguments[++i];
                if ([fm fileExistsAtPath:outDirString isDirectory:&isDirectory]) {
                    if (!isDirectory) {
                        printf("%s 已存在但不是文件夹，需要传入一个输出文件夹目录\n", [outDirString UTF8String]);
                        return 1;
                    }
                } else {
                    NSError *error = nil;
                    if (![fm createDirectoryAtPath:outDirString withIntermediateDirectories:YES attributes:nil error:&error]) {
                        printf("创建输出目录失败，请确认 -spamCodeOut 之后接的是一个“输出文件夹目录”参数，错误信息如下：\n传入的输出文件夹目录：%s\n%s", [outDirString UTF8String], [error.localizedDescription UTF8String]);
                        return 1;
                    }
                }
                continue;
            }
            if ([argument isEqualToString:@"-handleXcassets"]) {
                needHandleXcassets = YES;
                continue;
            }
            if ([argument isEqualToString:@"-deleteComments"]) {
                needDeleteComments = YES;
                continue;
            }
        }
        
        if (outDirString) {
            @autoreleasepool {
                recursiveDirectory(projectDirString, ^(NSString *mFilePath){
                    generateSpamCodeFile(outDirString, mFilePath, GSCSourceTypeClass);
                    generateSpamCodeFile(outDirString, mFilePath, GSCSourceTypeCategory);
                });
            }
        }
        if (needHandleXcassets) {
            @autoreleasepool {
                handleXcassetsFiles(projectDirString);
            }
        }
        if (needDeleteComments) {
            @autoreleasepool {
                deleteComments(projectDirString);
            }
        }
    }
    return 0;
}

void recursiveDirectory(NSString *directory, void(^handleFile)(NSString *mFilePath)) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *files = [fm contentsOfDirectoryAtPath:directory error:nil];
    BOOL isDirectory;
    for (NSString *filePath in files) {
        NSString *path = [directory stringByAppendingPathComponent:filePath];
        if ([fm fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory) {
            recursiveDirectory(path, handleFile);
            continue;
        }
        NSString *fileName = filePath.lastPathComponent;
        if (![fileName hasSuffix:@".h"]) continue;
        fileName = [fileName stringByDeletingPathExtension];
        
        NSString *mFileName = [fileName stringByAppendingPathExtension:@"m"];
        if ([files containsObject:mFileName]) {
            handleFile([directory stringByAppendingPathComponent:mFileName]);
        }
    }
}

static NSString *const kClassCategoryName = @"GSC_CLASS_CODE";
static NSString *const kCategoryCategoryName = @"GSC_CATEGORY_CODE";
static NSString *const kHSystemClassFileTemplate = @"\
#import <Foundation/Foundation.h>\n\
#import <UIKit/UIKit.h>\n\
@interface %@ (%@)\n\
%@\n\
@end\n";
static NSString *const kHCustomClassFileTemplate = @"\
#import \"%@.h\"\n\
@interface %@ (%@)\n\
%@\n\
@end\n";
static NSString *const kMClassFileTemplate = @"\
#import \"%@+%@.h\"\n\
@implementation %@ (%@)\n\
%@\n\
@end\n";
void generateSpamCodeFile(NSString *outDirectory, NSString *mFilePath, GSCSourceType type) {
    NSString *mFileContent = [NSString stringWithContentsOfFile:mFilePath encoding:NSUTF8StringEncoding error:nil];
    NSString *regexStr;
    switch (type) {
        case GSCSourceTypeClass:
            regexStr = @" *@implementation +(\\w+)[^(]*\\n(?:.|\\n)+?@end";
            break;
        case GSCSourceTypeCategory:
            regexStr = @" *@implementation *(\\w+) *\\((\\w+)\\)(?:.|\\n)+?@end";
            break;
    }
    
    NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:regexStr options:NSRegularExpressionUseUnicodeWordBoundaries error:nil];
    NSArray<NSTextCheckingResult *> *matches = [expression matchesInString:mFileContent options:0 range:NSMakeRange(0, mFileContent.length)];
    if (matches.count <= 0) return;
    
    [matches enumerateObjectsUsingBlock:^(NSTextCheckingResult * _Nonnull impResult, NSUInteger idx, BOOL * _Nonnull stop) {
        NSString *className = [mFileContent substringWithRange:[impResult rangeAtIndex:1]];
        NSString *categoryName = nil;
        if (impResult.numberOfRanges >= 3) {
            categoryName = [mFileContent substringWithRange:[impResult rangeAtIndex:2]];
        }
        
        if (type == GSCSourceTypeClass) {
            // 如果该类型没有公开，只在 .m 文件中使用，则不处理
            NSString *hFilePath = [mFilePath.stringByDeletingPathExtension stringByAppendingPathExtension:@"h"];
            NSString *hFileContent = [NSString stringWithContentsOfFile:hFilePath encoding:NSUTF8StringEncoding error:nil];
            
            NSString *regexStr = [NSString stringWithFormat:@"\\b%@\\b", className];
            NSRange range = [hFileContent rangeOfString:regexStr options:NSRegularExpressionSearch];
            if (range.location == NSNotFound) {
                return;
            }
        }
        
        NSString *implementation = [mFileContent substringWithRange:impResult.range];
        NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:@" *([-+]) *\\(" options:NSRegularExpressionUseUnicodeWordBoundaries error:nil];
        NSArray<NSTextCheckingResult *> *matches = [expression matchesInString:implementation options:0 range:NSMakeRange(0, implementation.length)];
        if (matches.count <= 0) return;
        
        NSMutableString *hFileMethodsString = [NSMutableString string];
        NSMutableString *mFileMethodsString = [NSMutableString string];
        [matches enumerateObjectsUsingBlock:^(NSTextCheckingResult * _Nonnull matche, NSUInteger idx, BOOL * _Nonnull stop) {
            NSString *symbol = [implementation substringWithRange:[matche rangeAtIndex:1]];
            NSString *methodName = [@"gsc" stringByAppendingString:randomString(arc4random_uniform(16) + 16)];
            [hFileMethodsString appendFormat:@"%@ (NSArray *)%@;\n", symbol, methodName];
            
            [mFileMethodsString appendFormat:@"%@ (NSArray *)%@ {\n", symbol, methodName];
            [mFileMethodsString appendString:@"    NSMutableArray *array = [NSMutableArray array];\n"];
            NSInteger numCount = arc4random_uniform(40) + 1;
            for (NSInteger j = 0; j < numCount; j++) {
                [mFileMethodsString appendFormat:@"    [array addObject:@(%ld)];\n", (long)arc4random_uniform(999)];
            }
            [mFileMethodsString appendString:@"    return array;\n"];
            [mFileMethodsString appendString:@"}\n"];
        }];
        
        NSString *newCategoryName;
        switch (type) {
            case GSCSourceTypeClass:
                newCategoryName = kClassCategoryName;
                break;
            case GSCSourceTypeCategory:
                newCategoryName = [NSString stringWithFormat:@"%@_%@", kCategoryCategoryName, categoryName];
                break;
        }
        
        NSString *fileName = [NSString stringWithFormat:@"%@+%@.h", className, newCategoryName];
        NSString *fileContent;
        if ([className hasPrefix:@"NS"] || [className hasPrefix:@"UI"]) {
            fileContent = [NSString stringWithFormat:kHSystemClassFileTemplate, className, newCategoryName, hFileMethodsString];
        } else {
            NSString *soureHFileName = mFilePath.lastPathComponent.stringByDeletingPathExtension;
            fileContent = [NSString stringWithFormat:kHCustomClassFileTemplate, soureHFileName, className, newCategoryName, hFileMethodsString];
        }
        [fileContent writeToFile:[outDirectory stringByAppendingPathComponent:fileName] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        
        fileName = [NSString stringWithFormat:@"%@+%@.m", className, newCategoryName];
        fileContent = [NSString stringWithFormat:kMClassFileTemplate, className, newCategoryName, className, newCategoryName, mFileMethodsString];
        [fileContent writeToFile:[outDirectory stringByAppendingPathComponent:fileName] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }];
    
    
}

static const NSString *kRandomAlphabet = @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
NSString *randomString(NSInteger length) {
    NSMutableString *ret = [NSMutableString stringWithCapacity:length];
    for (int i = 0; i < length; i++) {
        [ret appendFormat:@"%C", [kRandomAlphabet characterAtIndex:arc4random_uniform((uint32_t)[kRandomAlphabet length])]];
    }
    return ret;
}

void handleXcassetsFiles(NSString *directory) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *files = [fm contentsOfDirectoryAtPath:directory error:nil];
    BOOL isDirectory;
    for (NSString *fileName in files) {
        NSString *filePath = [directory stringByAppendingPathComponent:fileName];
        if ([fm fileExistsAtPath:filePath isDirectory:&isDirectory] && isDirectory) {
            handleXcassetsFiles(filePath);
            continue;
        }
        if (![fileName isEqualToString:@"Contents.json"]) continue;
        NSString *contentsDirectoryName = filePath.stringByDeletingLastPathComponent.lastPathComponent;
        if (![contentsDirectoryName hasSuffix:@".imageset"]) continue;
        
        NSString *fileContent = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:nil];
        if (!fileContent) continue;
        
        NSMutableArray<NSString *> *processedImageFileNameArray = @[].mutableCopy;
        static NSString * const regexStr = @"\"filename\" *: *\"(.*)?\"";
        NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:regexStr options:NSRegularExpressionUseUnicodeWordBoundaries error:nil];
        NSArray<NSTextCheckingResult *> *matches = [expression matchesInString:fileContent options:0 range:NSMakeRange(0, fileContent.length)];
        while (matches.count > 0) {
            NSInteger i = 0;
            NSString *imageFileName = nil;
            do {
                if (i >= matches.count) {
                    i = -1;
                    break;
                }
                imageFileName = [fileContent substringWithRange:[matches[i] rangeAtIndex:1]];
                i++;
            } while ([processedImageFileNameArray containsObject:imageFileName]);
            if (i < 0) break;
            
            NSString *imageFilePath = [filePath.stringByDeletingLastPathComponent stringByAppendingPathComponent:imageFileName];
            if ([fm fileExistsAtPath:imageFilePath]) {
                NSString *newImageFileName = [randomString(10) stringByAppendingPathExtension:imageFileName.pathExtension];
                NSString *newImageFilePath = [filePath.stringByDeletingLastPathComponent stringByAppendingPathComponent:newImageFileName];
                while ([fm fileExistsAtPath:newImageFileName]) {
                    newImageFileName = [randomString(10) stringByAppendingPathExtension:imageFileName.pathExtension];
                    newImageFilePath = [filePath.stringByDeletingLastPathComponent stringByAppendingPathComponent:newImageFileName];
                }
                
                NSError *error = nil;
                [fm moveItemAtPath:imageFilePath toPath:newImageFilePath error:&error];
                assert(!error);
                
                fileContent = [fileContent stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@"\"%@\"", imageFileName]
                                                                     withString:[NSString stringWithFormat:@"\"%@\"", newImageFileName]];
                [fileContent writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
                
                [processedImageFileNameArray addObject:newImageFileName];
            } else {
                [processedImageFileNameArray addObject:imageFileName];
            }
            
            matches = [expression matchesInString:fileContent options:0 range:NSMakeRange(0, fileContent.length)];
        }
    }
}

void regularReplacement(NSMutableString *originalString, NSString *regularExpression, NSString *newString) {
    BOOL isGroupNo1 = [newString isEqualToString:@"\\1"];
    NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:regularExpression options:NSRegularExpressionAnchorsMatchLines|NSRegularExpressionUseUnixLineSeparators|NSRegularExpressionUseUnicodeWordBoundaries error:nil];
    NSArray<NSTextCheckingResult *> *matches = [expression matchesInString:originalString options:0 range:NSMakeRange(0, originalString.length)];
    [matches enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(NSTextCheckingResult * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (isGroupNo1) {
            NSString *withString = [originalString substringWithRange:[obj rangeAtIndex:1]];
            [originalString replaceCharactersInRange:obj.range withString:withString];
        } else {
            [originalString replaceCharactersInRange:obj.range withString:newString];
        }
    }];
}

void deleteComments(NSString *directory) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *files = [fm contentsOfDirectoryAtPath:directory error:nil];
    BOOL isDirectory;
    for (NSString *fileName in files) {
        NSString *filePath = [directory stringByAppendingPathComponent:fileName];
        if ([fm fileExistsAtPath:filePath isDirectory:&isDirectory] && isDirectory) {
            deleteComments(filePath);
            continue;
        }
        if (![fileName hasSuffix:@".h"] && ![fileName hasSuffix:@".m"] && ![fileName hasSuffix:@".swift"]) continue;
        NSMutableString *fileContent = [NSMutableString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:nil];
        regularReplacement(fileContent, @"([^:/])//.*",             @"\\1");
        regularReplacement(fileContent, @"^//.*",                   @"");
        regularReplacement(fileContent, @"/\\*{1,2}[\\s\\S]*?\\*/", @"");
        regularReplacement(fileContent, @"^\\s*\\n",                @"");
        [fileContent writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}
