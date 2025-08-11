#!/bin/bash

# CubeCleaner 构建脚本
# 使用方法: ./build.sh [clean|run|release]

set -e  # 遇到错误立即退出

PROJECT_NAME="CubeCleaner"
SCHEME_NAME="CubeCleaner"
WORKSPACE_DIR=$(pwd)
BUILD_DIR="build"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查 Xcode 是否安装
check_xcode() {
    if ! command -v xcodebuild &> /dev/null; then
        print_error "Xcode 命令行工具未安装"
        print_info "请运行: xcode-select --install"
        exit 1
    fi
    print_info "Xcode 版本: $(xcodebuild -version | head -1)"
}

# 清理构建缓存
clean_build() {
    print_info "清理构建缓存..."
    
    # 清理 Xcode 构建缓存
    if [ -d ~/Library/Developer/Xcode/DerivedData ]; then
        rm -rf ~/Library/Developer/Xcode/DerivedData/${PROJECT_NAME}-*
        print_success "已清理 DerivedData"
    fi
    
    # 清理本地构建目录
    if [ -d "$BUILD_DIR" ]; then
        rm -rf "$BUILD_DIR"
        print_success "已清理本地构建目录"
    fi
    
    mkdir -p "$BUILD_DIR"
}

# 构建项目
build_project() {
    local configuration=${1:-Debug}
    
    print_info "开始构建项目 ($configuration)..."
    
    xcodebuild \
        -project "${PROJECT_NAME}.xcodeproj" \
        -scheme "$SCHEME_NAME" \
        -configuration "$configuration" \
        -derivedDataPath "$BUILD_DIR/DerivedData" \
        build
    
    if [ $? -eq 0 ]; then
        print_success "构建成功！"
        
        # 找到构建的应用程序
        APP_PATH=$(find "$BUILD_DIR/DerivedData/Build/Products/$configuration" -name "*.app" -type d | head -1)
        if [ -n "$APP_PATH" ]; then
            print_info "应用程序位置: $APP_PATH"
            echo "$APP_PATH" > "$BUILD_DIR/app_path.txt"
        fi
    else
        print_error "构建失败！"
        exit 1
    fi
}

# 运行应用程序
run_app() {
    if [ -f "$BUILD_DIR/app_path.txt" ]; then
        APP_PATH=$(cat "$BUILD_DIR/app_path.txt")
        if [ -d "$APP_PATH" ]; then
            print_info "启动应用程序..."
            open "$APP_PATH"
            print_success "应用程序已启动"
        else
            print_error "应用程序不存在，请先构建项目"
            exit 1
        fi
    else
        print_error "未找到应用程序路径，请先构建项目"
        exit 1
    fi
}

# 显示使用帮助
show_help() {
    echo "CubeCleaner 构建脚本"
    echo ""
    echo "使用方法:"
    echo "  ./build.sh [选项]"
    echo ""
    echo "选项:"
    echo "  clean     清理构建缓存"
    echo "  build     构建项目 (Debug 模式)"
    echo "  release   构建项目 (Release 模式)"
    echo "  run       运行应用程序"
    echo "  help      显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  ./build.sh build"
    echo "  ./build.sh clean && ./build.sh build"
    echo "  ./build.sh release"
    echo "  ./build.sh run"
}

# 主函数
main() {
    local command=${1:-build}
    
    print_info "CubeCleaner 构建脚本启动"
    print_info "工作目录: $WORKSPACE_DIR"
    
    case $command in
        "clean")
            check_xcode
            clean_build
            ;;
        "build")
            check_xcode
            build_project "Debug"
            ;;
        "release")
            check_xcode
            clean_build
            build_project "Release"
            ;;
        "run")
            run_app
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            print_error "未知命令: $command"
            show_help
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"
