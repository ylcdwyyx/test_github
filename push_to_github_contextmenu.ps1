param(
    [Parameter(Mandatory = $true)]
    [string]$TargetPath,
    [switch]$NoPause
)

$ErrorActionPreference = "Stop"

try {
    $projectPath = (Resolve-Path -LiteralPath $TargetPath).Path
    Set-Location -LiteralPath $projectPath

    $pythonExe = "D:\py\github\.venv\Scripts\python.exe"
    $scriptPath = "D:\py\github\push_to_github.py"

    if (-not (Test-Path -LiteralPath $pythonExe)) {
        throw "未找到 Python 虚拟环境解释器：$pythonExe"
    }
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw "未找到推送脚本：$scriptPath"
    }

    $tempLogPath = Join-Path $env:TEMP ("push_to_github_" + (Split-Path -Leaf $projectPath) + ".log")
    $logPath = $tempLogPath
    "开始推送：$projectPath" | Set-Content -Path $logPath -Encoding UTF8

    function Write-Log([string]$Message) {
        Add-Content -Path $logPath -Encoding UTF8 -Value $Message
        Write-Host $Message
    }

    function Run-Logged([string[]]$Cmd) {
        Write-Log ("执行命令：" + ($Cmd -join " "))
        $output = & $Cmd[0] $Cmd[1..($Cmd.Length - 1)] 2>&1
        $exitCode = $LASTEXITCODE
        if ($output) {
            $output | ForEach-Object { Write-Log $_ }
        }
        return $exitCode
    }

    function Pause-IfNeeded([string]$Prompt) {
        if ($NoPause) { return }
        try { Read-Host $Prompt | Out-Null } catch { }
    }

    # 1) 确保当前目录是 Git 仓库（不是则初始化）
    $code = Run-Logged @("git", "--version")
    if ($code -ne 0) { throw "未检测到 git，请先安装 Git for Windows，并确保 git 在 PATH 中。" }

    $inside = ""
    try {
        $inside = (git rev-parse --is-inside-work-tree 2>$null).Trim()
    } catch { }

    if ($inside -ne "true") {
        Write-Log "当前目录不是 Git 仓库，开始初始化 git..."
        $code = Run-Logged @("git", "init")
        if ($code -ne 0) { throw "git init 失败（退出码 $code）" }
        try { git symbolic-ref HEAD refs/heads/main | Out-Null } catch { }
    }

    # 切换到项目内日志（放在 .git 内，避免污染工作区）
    try {
        $projectLogPath = Join-Path (Join-Path $projectPath ".git") "push_to_github.log"
        if ($logPath -ne $projectLogPath) {
            if (Test-Path -LiteralPath $logPath) {
                Get-Content -LiteralPath $logPath | Set-Content -LiteralPath $projectLogPath -Encoding UTF8
                Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
            }
            $logPath = $projectLogPath
            Write-Log "日志已切换到：$logPath"
        }
    } catch { }

    # 2) 如有未提交/未跟踪文件，提示确认并自动提交
    $status = (git status --porcelain)
    if ($status) {
        Write-Log "检测到未提交改动（包含未跟踪文件）："
        $status | ForEach-Object { Write-Log $_ }

        $answer = Read-Host "是否自动提交以上改动后再推送？输入 Y 确认，其它任意键取消"
        if ((-not $answer) -or ($answer.ToUpperInvariant() -ne "Y")) {
            Write-Log "用户已取消。"
            Start-Process $logPath
            Pause-IfNeeded "按回车关闭窗口"
            exit 2
        }

        $hasHead = $true
        try { git rev-parse --verify HEAD 1>$null 2>$null } catch { $hasHead = $false }
        $defaultMsg = if ($hasHead) { "auto commit" } else { "init commit" }
        $msg = Read-Host "请输入提交信息（直接回车使用默认：$defaultMsg）"
        if (-not $msg) { $msg = $defaultMsg }

        $code = Run-Logged @("git", "add", "-A")
        if ($code -ne 0) { throw "git add 失败（退出码 $code）" }

        $code = Run-Logged @("git", "commit", "-m", $msg)
        if ($code -ne 0) { throw "git commit 失败（退出码 $code），请检查是否有权限/是否配置了 user.name 与 user.email" }
    } else {
        Write-Log "工作区干净，无需提交。"
    }

    # 3) 统一分支名为 main（避免默认 master 导致推送分支不一致）
    try {
        $code = Run-Logged @("git", "branch", "-M", "main")
        if ($code -ne 0) { Write-Log "警告：git branch -M main 失败（退出码 $code），继续尝试推送。" }
    } catch { }

    # 4) 创建 GitHub 私有仓库并推送（仓库名=目录名）
    if (-not $env:GITHUB_TOKEN) {
        Write-Log "未检测到环境变量 GITHUB_TOKEN（PAT）。"
        Write-Log "请先执行：setx GITHUB_TOKEN <你的PAT>，然后重启资源管理器（或注销重登）后再右键推送。"
        Start-Process $logPath
        Pause-IfNeeded "按回车关闭窗口"
        exit 3
    }

    $output = & $pythonExe $scriptPath --private --path $projectPath --no-prompt-token 2>&1
    $exitCode = $LASTEXITCODE
    if ($output) { $output | ForEach-Object { Write-Log $_ } }
    

    if ($exitCode -ne 0) {
        Add-Content -Path $logPath -Encoding UTF8 -Value "执行失败，退出码：$exitCode"
        Write-Host "推送失败，已写入日志：$logPath"
        Start-Process $logPath
        Pause-IfNeeded "按回车关闭窗口"
        exit $exitCode
    }

    Add-Content -Path $logPath -Encoding UTF8 -Value "执行成功"
    Write-Host "推送成功。日志：$logPath"
    exit 0
}
catch {
    try {
        if ($logPath) {
            $_ | Out-String | Add-Content -Path $logPath -Encoding UTF8
            Write-Host "发生异常，已写入日志：$logPath"
            Start-Process $logPath
        } else {
            $fallbackLog = Join-Path $env:TEMP "push_to_github_error.log"
            $_ | Out-String | Set-Content -Path $fallbackLog -Encoding UTF8
            Write-Host "发生异常，已写入日志：$fallbackLog"
            Start-Process $fallbackLog
        }
    } catch { }
    Pause-IfNeeded "按回车关闭窗口"
    exit 1
}
