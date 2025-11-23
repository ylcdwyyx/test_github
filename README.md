## 项目说明

这是一个用于快速创建 GitHub 仓库并推送当前项目的示例仓库。

### 文件列表
- README.md：项目说明与使用方法。
- push_to_github.py：使用 PAT 创建 GitHub 仓库、设置远程并推送的脚本。
- .venv/：uv 创建的本地虚拟环境（可根据需要重建）。

### 环境准备
1. 创建虚拟环境：`uv venv`
2. 安装依赖：`uv pip install requests`
3. 配置 PAT：`setx GITHUB_TOKEN <your_pat>`（重新打开终端后生效）。

### 脚本用法
- 创建并推送（公开仓库）：
  ```pwsh
  .\.venv\Scripts\python.exe push_to_github.py test_github
  ```
- 创建私有仓库：`--private`
- 仓库已存在时仅推送：`--skip-create --owner <你的 GitHub 用户名>`
- 仅查看计划而不推送：`--dry-run`

> 推送前需保证工作区干净（无未提交改动），否则脚本会直接报错终止。
