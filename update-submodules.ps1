# Останавливать выполнение при критических ошибках
$ErrorActionPreference = "Stop"

# Список подмодулей для обновления (укажите точные пути, если они лежат в подпапках)
$Submodules = @("Backend", "Database", "Notifications", "VK-Bot")

Write-Host "🔄 Переключение на ветку update-modules..." -ForegroundColor Cyan

# Проверяем, существует ли ветка update-modules
$branchExists = git branch --list update-modules
if ($branchExists) {
    git checkout update-modules
} else {
    git checkout -b update-modules
}

Write-Host "🚀 Начинаем обновление подмодулей..." -ForegroundColor Cyan

# Обновляем каждый подмодуль до последней версии из его удаленной ветки
foreach ($submodule in $Submodules) {
    if (Test-Path $submodule) {
        Write-Host "🔹 Обновление подмодуля: $submodule..." -ForegroundColor Gray
        git submodule update --remote --merge $submodule
    } else {
        Write-Warning "Папка $submodule не найдена. Пропускаем."
    }
}

Write-Host "📝 Индексация изменений..." -ForegroundColor Cyan
foreach ($submodule in $Submodules) {
    if (Test-Path $submodule) {
        git add $submodule
    }
}

# Проверяем, есть ли измененные подмодули для коммита
git diff --cached --quiet
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Все подмодули уже в актуальном состоянии. Коммит не требуется." -ForegroundColor Green
} else {
    Write-Host "💾 Создание коммита..." -ForegroundColor Cyan
    git commit -m "chore: обновление подмодулей Backend, Database, Notifications, VK-Bot"

    Write-Host "📤 Отправка изменений в удаленный репозиторий..." -ForegroundColor Cyan
    git push -u origin update-modules
    Write-Host "🎉 Успешно обновлено и отправлено!" -ForegroundColor Green
}
