#!/bin/bash

# CubeCleaner 项目进度更新脚本
# 用于自动更新项目统计和进度跟踪

PROJECT_ROOT="/Users/tangmaocheng/Codes/CubeCleaner"
PROGRESS_FILE="$PROJECT_ROOT/PROJECT_PROGRESS.md"

# 统计代码行数
count_lines_of_code() {
    find "$PROJECT_ROOT/CubeCleaner" -name "*.swift" -exec wc -l {} + | tail -1 | awk '{print $1}'
}

# 统计文件数量
count_swift_files() {
    find "$PROJECT_ROOT/CubeCleaner" -name "*.swift" | wc -l
}

# 更新进度文件中的统计信息
update_progress_stats() {
    local loc=$(count_lines_of_code)
    local file_count=$(count_swift_files)
    local current_date=$(date "+%Y年%m月%d日")
    
    echo "更新项目统计信息..."
    echo "- 代码行数: $loc"
    echo "- Swift 文件数: $file_count"
    echo "- 更新日期: $current_date"
}

# 检查文件夹结构是否创建完成
check_folder_structure() {
    local folders=(
        "CubeCleaner/Models"
        "CubeCleaner/Views" 
        "CubeCleaner/ViewModels"
        "CubeCleaner/Services"
        "CubeCleaner/Utils"
    )
    
    local created_count=0
    for folder in "${folders[@]}"; do
        if [ -d "$PROJECT_ROOT/$folder" ]; then
            ((created_count++))
        fi
    done
    
    echo "文件夹结构完成度: $created_count/${#folders[@]}"
}

# 主函数
main() {
    echo "=== CubeCleaner 项目进度检查 ==="
    echo "执行时间: $(date)"
    echo ""
    
    update_progress_stats
    echo ""
    check_folder_structure
    echo ""
    echo "=== 检查完成 ==="
}

# 执行主函数
main
