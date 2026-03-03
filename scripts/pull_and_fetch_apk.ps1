param(
    [string]$RepoRoot = ".",
    [string]$Repo = "xfashion44-jpg/livedate-android",
    [string]$Workflow = "Android Debug APK",
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

Write-Host "[5/6] 최근 run 목록 조회(databaseId)..."
$runIds = gh run list `
    --repo $Repo `
    --workflow $Workflow `
    --limit 20 `
    --json databaseId `
    --jq '.[].databaseId'

if (-not $runIds) {
    throw "run list 결과가 비어있습니다. workflow 이름을 확인하세요: $Workflow"
}

# 다운로드 폴더 초기화
if (Test-Path $ArtifactsDir) {
    Remove-Item $ArtifactsDir -Recurse -Force
}
New-Item -ItemType Directory -Path $ArtifactsDir | Out-Null

Write-Host "[6/6] 아티팩트 다운로드(artifact 있는 run 찾기)..."
$downloaded = $false
$usedRunId = ""

foreach ($ridRaw in $runIds) {
    $rid = $ridRaw.ToString().Trim()
    if ($rid -notmatch "^\d+$") { continue }

    Write-Host "  Try Run ID: $rid"
    $null = gh run download $rid --repo $Repo --dir $ArtifactsDir 2>$null
    if ($LASTEXITCODE -ne 0) { continue }

    if ($LASTEXITCODE -eq 0) {
        $downloaded = $true
        $usedRunId = $rid
        break
    }
}

if (-not $downloaded) {
    throw "최근 20개 run에서 아티팩트를 찾지 못했습니다. Actions에서 artifact 생성 여부를 확인하세요."
}

Write-Host ""
Write-Host "완료:"
Write-Host "  RepoRoot    : $resolvedRepoRoot"
Write-Host "  Run ID      : $usedRunId"
Write-Host "  Output Dir  : $ArtifactsDir"
