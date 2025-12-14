param(
    [Parameter(Mandatory = $true)]
    [string]$TargetPath
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

    $logPath = Join-Path $projectPath ".push_to_github.log"
    "开始推送：$projectPath" | Out-File -FilePath $logPath -Encoding UTF8

    & $pythonExe $scriptPath --private --path $projectPath 2>&1 | Tee-Object -FilePath $logPath -Append
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        "执行失败，退出码：$exitCode" | Out-File -FilePath $logPath -Encoding UTF8 -Append
        Write-Host "推送失败，已写入日志：$logPath"
        Start-Process $logPath
        Read-Host "按回车关闭窗口"
        exit $exitCode
    }

    "执行成功" | Out-File -FilePath $logPath -Encoding UTF8 -Append
    exit 0
}
catch {
    try {
        $fallbackLog = Join-Path $env:TEMP "push_to_github_error.log"
        $_ | Out-String | Out-File -FilePath $fallbackLog -Encoding UTF8
        Write-Host "发生异常，已写入日志：$fallbackLog"
        Start-Process $fallbackLog
    } catch { }
    Read-Host "按回车关闭窗口"
    exit 1
}

