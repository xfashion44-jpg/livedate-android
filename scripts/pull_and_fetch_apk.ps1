param(
    [string]$RepoRoot = ".",
    [string]$Repo = "xfashion44-jpg/livedate-android",
    [string]$Workflow = "Android Debug APK",
    [string]$ArtifactName = "app-debug-apk",
    [string]$ArtifactsDir = ".\artifacts"
)

$ErrorActionPreference = "Stop"

function Require-Cmd([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "필수 명령어가 없습니다: $Name"
    }
}

Write-Host "[1/6] 환경 확인..."
Require-Cmd "git"
Require-Cmd "gh"

$resolvedRepoRoot = (Resolve-Path $RepoRoot).Path
Set-Location $resolvedRepoRoot

Write-Host "[2/6] Git 상태 확인..."
$status = git status --porcelain
if ($status) {
    Write-Host "로컬 변경사항이 있습니다. pull을 중단합니다."
    Write-Host "아래 변경사항을 먼저 커밋/스태시/정리하세요:"
    Write-Host $status
    exit 2
}

Write-Host "[3/6] Git pull..."
git pull

Write-Host "[4/6] GitHub 인증 확인..."
$authStatus = gh auth status 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "gh 인증이 필요합니다. 먼저 'gh auth login' 실행하세요."
}

Write-Host "[5/6] 최신 Actions run 조회(성공 run 우선)..."
$runId = gh run list `
    --repo $Repo `
    --workflow $Workflow `
    --limit 10 `
    --json databaseId,conclusion,status `
    --jq '.[] | select(.status=="completed" and .conclusion=="success") | .databaseId' | Select-Object -First 1

if (-not $runId) {
    throw "성공한 run id를 찾지 못했습니다. workflow 이름/최근 실행 상태를 확인하세요: $Workflow"
}

$runId = $runId.Trim()
Write-Host "  Run ID: $runId"
if (-not $runId) {
    throw "최신 run id를 찾지 못했습니다. workflow 이름을 확인하세요: $Workflow"
}

# 다운로드 폴더는 매번 깨끗하게 초기화(덮어쓰기/잔재 방지)
if (Test-Path $ArtifactsDir) {
    Remove-Item $ArtifactsDir -Recurse -Force
}
New-Item -ItemType Directory -Path $ArtifactsDir | Out-Null

Write-Host "[6/6] 아티팩트 다운로드..."
gh run download $runId `
    --repo $Repo `
    --name $ArtifactName `
    --dir $ArtifactsDir

if ($LASTEXITCODE -ne 0) {
    throw "아티팩트 다운로드 실패. artifact 이름을 확인하세요: $ArtifactName"
}

Write-Host ""
Write-Host "완료:"
Write-Host "  RepoRoot    : $resolvedRepoRoot"
Write-Host "  Run ID      : $runId"
Write-Host "  Artifact    : $ArtifactName"
Write-Host "  Output Dir  : $ArtifactsDir"

