#!/bin/bash

# 版本检测和更新脚本
# 功能：
# 1. 从Apple网页获取最新客户端版本
# 2. 从API获取最新资源版本
# 3. 检测版本更新并更新相关文件

set -e

# 配置
endpoint="https://api.link-like-lovelive.app/v1/user/login"
apple_url="https://apps.apple.com/jp/app/link-like-%E3%83%A9%E3%83%96%E3%83%A9%E3%82%A4%E3%83%96-%E8%93%AE%E3%83%8E%E7%A9%BA%E3%82%B9%E3%82%AF%E3%83%BC%E3%83%AB%E3%82%A2%E3%82%A4%E3%83%89%E3%83%AB%E3%82%AF%E3%83%A9%E3%83%96/id1665027261"
web_ua="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"

# 文件路径
res_version_file="../data/res_version.txt"
csv_file="../others/linkura-googleplay-apk.csv"
client_res_file="../data/client-res.json"

# 创建data目录（如果不存在）
mkdir -p "../data"

# 标记变更
has_new_res_version=false
has_new_client_version=false

# 函数定义
update_csv_file() {
    # 获取当前日期和星期几
    current_date=$(date '+%Y-%m-%d')
    day_of_week=$(date '+%a')
    case $day_of_week in
        Mon) jp_day="(月)" ;;
        Tue) jp_day="(火)" ;;
        Wed) jp_day="(水)" ;;
        Thu) jp_day="(木)" ;;
        Fri) jp_day="(金)" ;;
        Sat) jp_day="(土)" ;;
        Sun) jp_day="(日)" ;;
        *) jp_day="(x)" ;;
    esac
    
    # 创建新行内容
    new_line="${current_date} ${jp_day},${web_client_version},"
    echo "在CSV文件第二行插入新版本记录: $new_line"
    
    # 创建临时文件
    temp_file=$(mktemp)
    
    # 读取CSV文件的第一行（标题）
    head -1 "$csv_file" > "$temp_file"
    
    # 添加新版本行
    echo "$new_line" >> "$temp_file"
    
    # 添加其余行（跳过标题行）
    tail -n +2 "$csv_file" >> "$temp_file"
    
    # 替换原文件
    mv "$temp_file" "$csv_file"
    echo "CSV文件已更新"
}

update_client_res_json() {
    echo "增量更新client-res.json..."
    
    # 直接执行Python代码进行增量更新
    python -c "
import json
import os
from pathlib import Path

# 参数
client_version = '$web_client_version'
res_version = '$new_res_version'
client_updated = '$has_new_client_version' == 'true'
res_updated = '$has_new_res_version' == 'true'

print(f'更新参数: 客户端={client_version}({client_updated}), 资源={res_version}({res_updated})')

# 文件路径
client_res_file = Path('../data/client-res.json')

# 加载现有数据
if client_res_file.exists():
    try:
        with open(client_res_file, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except Exception as e:
        print(f'警告: 加载client-res.json失败: {e}')
        data = {}
else:
    data = {}

# 如果是新的客户端版本，创建新的映射条目
if client_updated:
    print(f'添加新客户端版本: {client_version}')
    # 将新版本添加到数据结构的开头（保持最新版本在前的顺序）
    new_data = {client_version: []}
    new_data.update(data)
    data = new_data

# 如果是新的资源版本，添加到对应的客户端版本
if res_updated and res_version:
    print(f'添加资源版本 {res_version} 到客户端版本 {client_version}')
    
    # 确保客户端版本存在
    if client_version not in data:
        data[client_version] = []
    
    # 检查资源版本是否已存在
    if res_version not in data[client_version]:
        # 将新的资源版本添加到列表末尾
        data[client_version].append(res_version)
        print(f'资源版本 {res_version} 已添加到 {client_version}')
    else:
        print(f'资源版本 {res_version} 已存在于 {client_version}')

# 保存更新后的数据
client_res_file.parent.mkdir(exist_ok=True)
with open(client_res_file, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)

print('client-res.json已更新')
"
    
    echo "client-res.json增量更新完成"
}

echo "=== 版本检测开始 ==="

# 1. 获取Apple网页上的客户端版本
echo "正在从Apple网页获取最新客户端版本..."
apple_html=$(curl -s -H "User-Agent: $web_ua" "$apple_url")
if [ $? -ne 0 ]; then
    echo "错误: 无法访问Apple网页"
    exit 1
fi

# 提取版本号
web_client_version=$(echo "$apple_html" | grep -o '\\"versionDisplay\\":\\"[0-9]\+\.[0-9]\+\.[0-9]\+\\"' | sed 's/.*\\"versionDisplay\\":\\"\([^\\]*\)\\".*/\1/' | head -1)

if [ -z "$web_client_version" ]; then
    echo "错误: 无法从Apple网页提取客户端版本"
    exit 1
else
    echo "从Apple网页获取到客户端版本: $web_client_version"
fi

# 2. 检查CSV文件中的最新版本
echo "检查CSV文件中的最新版本..."
if [ -f "$csv_file" ]; then
    csv_latest_version=$(head -2 "$csv_file" | tail -1 | cut -d',' -f2)
    echo "CSV文件中最新版本: $csv_latest_version"
    
    # 比较版本
    if [ "$web_client_version" != "$csv_latest_version" ]; then
        echo "检测到新的客户端版本: $web_client_version"
        has_new_client_version=true
        
        # 更新CSV文件
        echo "更新CSV文件..."
        update_csv_file
    else
        echo "客户端版本无变化: $web_client_version"
    fi
else
    echo "警告: CSV文件不存在: $csv_file"
    has_new_client_version=true
fi

# 3. 使用最新的客户端版本获取资源版本
echo "使用客户端版本 $web_client_version 获取资源版本..."
old_res_version="R2503000"  # 默认旧版本用于请求

# 执行curl请求并捕获响应头
response_headers=$(curl -s -D - "$endpoint" \
     -H "content-type: application/json" \
     -H "x-client-version: $web_client_version" \
     -H "user-agent: inspix-android/$web_client_version" \
     -H "x-res-version: $old_res_version" \
     -H "x-device-type: android" \
     -d '{"device_specific_id":"","player_id":"","version":1}')

if [ $? -ne 0 ]; then
    echo "错误: API请求失败"
    exit 1
fi

# 提取完整的资源版本（包括@后的部分）
new_res_version=$(echo "$response_headers" | grep -i "x-res-version:" | sed 's/.*x-res-version: *//i' | tr -d '\r\n')

if [ -n "$new_res_version" ]; then
    echo "获取到资源版本: $new_res_version"
    
    # 4. 检查资源版本是否需要更新
    if [ -f "$res_version_file" ]; then
        current_res_version=$(head -1 "$res_version_file")
        if [ "$new_res_version" != "$current_res_version" ]; then
            echo "检测到新的资源版本: $new_res_version"
            has_new_res_version=true
            
            # 更新资源版本文件
            echo "更新资源版本文件..."
            temp_file=$(mktemp)
            echo "$new_res_version" > "$temp_file"
            if [ -f "$res_version_file" ]; then
                cat "$res_version_file" >> "$temp_file"
            fi
            mv "$temp_file" "$res_version_file"
            echo "资源版本文件已更新"
        else
            echo "资源版本无变化: $new_res_version"
        fi
    else
        echo "创建新的资源版本文件..."
        echo "$new_res_version" > "$res_version_file"
        has_new_res_version=true
    fi
else
    echo "警告: 未能获取到资源版本"
fi

# 5. 更新client-res.json（如果有任何变化）
if [ "$has_new_client_version" = true ] || [ "$has_new_res_version" = true ]; then
    echo ""
    echo "更新client-res.json..."
    update_client_res_json
fi

# 6. 总结和设置退出码
echo ""
echo "=== 版本检测完成 ==="
echo "客户端版本: $web_client_version $([ "$has_new_client_version" = true ] && echo "(已更新)" || echo "(无变化)")"
if [ -n "$new_res_version" ]; then
    echo "资源版本: $new_res_version $([ "$has_new_res_version" = true ] && echo "(已更新)" || echo "(无变化)")"
fi

# 根据是否有更新设置退出码
if [ "$has_new_client_version" = true ] || [ "$has_new_res_version" = true ]; then
    echo "检测到更新，退出码: 0"
    exit 0
else
    echo "无更新，退出码: 1"
    exit 1
fi