#!/usr/bin/env python
"""使用 PAT 一键创建 GitHub 仓库并推送当前项目。"""
import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

import requests


def run_cmd(cmd, cwd):
    """运行命令并在失败时抛出异常，便于脚本中统一处理。"""
    result = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"命令失败: {' '.join(cmd)}\nstdout: {result.stdout}\nstderr: {result.stderr}")
    return result.stdout.strip()


def ensure_git_repo(root):
    """确保存在 Git 仓库，没有则初始化。"""
    if not (root / ".git").exists():
        run_cmd(["git", "init"], root)


def ensure_clean_tree(root):
    """推送前必须保证工作区干净。"""
    status = run_cmd(["git", "status", "--porcelain"], root)
    if status:
        raise RuntimeError("工作区存在未提交改动，请先提交后再运行脚本。")


def create_repo(token, name, private, description):
    """调用 GitHub API 创建仓库，成功返回仓库信息，已存在时返回 None。"""
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
    }
    payload = {
        "name": name,
        "private": private,
        "description": description or "",
    }
    resp = requests.post("https://api.github.com/user/repos", headers=headers, json=payload, timeout=15)
    if resp.status_code == 201:
        return resp.json()
    if resp.status_code == 422:
        # 仓库已存在等情况，调用者可选择跳过创建
        sys.stderr.write(f"警告：仓库可能已存在，跳过创建。响应: {resp.text}\n")
        return None
    raise RuntimeError(f"创建仓库失败，状态码 {resp.status_code}: {resp.text}")


def set_remote(root, remote_name, remote_url):
    """设置或更新远程地址。"""
    remotes = run_cmd(["git", "remote"], root).splitlines()
    if remote_name in remotes:
        run_cmd(["git", "remote", "set-url", remote_name, remote_url], root)
    else:
        run_cmd(["git", "remote", "add", remote_name, remote_url], root)


def main():
    parser = argparse.ArgumentParser(description="创建 GitHub 仓库并推送当前项目")
    parser.add_argument("repo", help="目标仓库名")
    parser.add_argument("--owner", help="GitHub 用户名/组织名，若创建成功将自动从返回值读取")
    parser.add_argument("--branch", default="main", help="推送分支，默认 main")
    parser.add_argument("--remote-name", default="origin", help="远程名，默认 origin")
    parser.add_argument("--private", action="store_true", help="创建私有仓库")
    parser.add_argument("--description", help="仓库描述")
    parser.add_argument("--skip-create", action="store_true", help="跳过创建仓库，仅设置远程并推送")
    parser.add_argument("--dry-run", action="store_true", help="仅打印计划操作，不实际推送")
    args = parser.parse_args()

    root = Path(__file__).resolve().parent
    token = os.environ.get("GITHUB_TOKEN")
    if not token:
        raise RuntimeError("未检测到 GITHUB_TOKEN，请先导出 PAT：setx GITHUB_TOKEN <token>")

    ensure_git_repo(root)
    ensure_clean_tree(root)

    repo_info = None
    if not args.skip_create:
        repo_info = create_repo(token, args.repo, args.private, args.description)

    owner = args.owner
    if repo_info:
        owner = repo_info.get("owner", {}).get("login", owner)
        remote_url = repo_info.get("clone_url")
    else:
        if not owner:
            raise RuntimeError("未提供 owner 且未从创建结果中获取到 owner，无法拼接远程地址。")
        visibility_prefix = ""  # https 方式无需可见性前缀
        remote_url = f"https://github.com/{owner}/{args.repo}.git"

    set_remote(root, args.remote_name, remote_url)

    if args.dry_run:
        print(f"计划推送到 {remote_url} 分支 {args.branch}，远程名 {args.remote_name}，跳过实际推送")
        return

    run_cmd(["git", "push", "-u", args.remote_name, args.branch], root)
    print(f"推送完成：{remote_url} -> {args.branch}")


if __name__ == "__main__":
    main()
