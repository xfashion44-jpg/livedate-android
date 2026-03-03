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
$null = gh auth status 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "gh 인증이 필요합니다. 먼저 'gh auth login' 실행하세요."
}

Write-Host "[5/6] 최신 Actions run 조회(databaseId 단일 추출)..."
$runId = gh run list `
    --repo $Repo `
    --workflow $Workflow `
    --limit 1 `
    --json databaseId `
    --jq '.[0].databaseId'

if (-not $runId) {
    throw "최신 run id를 찾지 못했습니다: $Workflow"
}

$runId = $runId.Trim()
Write-Host "  Run ID: $runId"

# 다운로드 폴더는 매번 깨끗하게 초기화(덮어쓰기/잔재 방지)
if (Test-Path $ArtifactsDir) {
    Remove-Item $ArtifactsDir -Recurse -Force
}
New-Item -ItemType Directory -Path $ArtifactsDir | Out-Null

Write-Host "[6/6] 아티팩트 다운로드..."
# 이름 필터 제거: 해당 run의 아티팩트를 전부 다운로드 (이름 변경/숫자 suffix 대응)
gh run download $runId --repo $Repo --dir $ArtifactsDir

if ($LASTEXITCODE -ne 0) {
    throw "아티팩트 다운로드 실패(run id=$runId)"
}

Write-Host ""
Write-Host "완료:"
Write-Host "  RepoRoot    : $resolvedRepoRoot"
Write-Host "  Run ID      : $runId"
Write-Host "  Artifact    : (all)"
Write-Host "  Output Dir  : $ArtifactsDir"
