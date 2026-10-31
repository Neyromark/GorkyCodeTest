$ErrorActionPreference = "Stop"

$Submodules = @("Backend", "Database", "Notifications", "VK-Bot")

Write-Host "Checking out update-modules branch..."

$branchExists = git branch --list update-modules
if ($branchExists) {
    git checkout update-modules
} else {
    git checkout -b update-modules
}

Write-Host "Starting submodules update..."

foreach ($submodule in $Submodules) {
    Write-Host "Updating submodule: $submodule..."

    $ErrorActionPreference = "Continue"
    # Обновляем подмодули локально без открытия редактора Vim
    git -c core.editor=true submodule update --init --remote --merge $submodule 2>&1
    $ErrorActionPreference = "Stop"
}

Write-Host "Staging changes in main repository..."
foreach ($submodule in $Submodules) {
    if (Test-Path $submodule) {
        git add $submodule
    }
}

git diff --cached --quiet
if ($LASTEXITCODE -eq 0) {
    Write-Host "All submodules are already up to date. No commit needed."
} else {
    Write-Host "Creating commit..."
    git commit -m "chore: update submodules Backend, Database, Notifications, VK-Bot"

    Write-Host "Pushing changes strictly to update-modules branch..."
    $ErrorActionPreference = "Continue"
    # Отправляем ветку в origin
    git push -u origin update-modules 2>&1
    $ErrorActionPreference = "Stop"
    Write-Host "Successfully updated and pushed to update-modules!"
}
