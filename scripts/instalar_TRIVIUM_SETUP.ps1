<#
  instalar_TRIVIUM_SETUP.ps1  -  TRIVIUM369
  ------------------------------------------------------------------
  Baixa o indicador TRIVIUM_SETUP.mq5 direto do GitHub e instala em
  TODOS os terminais MetaTrader 5 encontrados no computador (incluindo
  a Admirals), compilando em seguida.

  COMO RODAR:
    1. Abra o PowerShell
    2. (se reclamar de permissao) rode antes:
         Set-ExecutionPolicy -Scope Process Bypass -Force
    3. Rode este script:
         .\instalar_TRIVIUM_SETUP.ps1

  Depois, no MetaTrader: Navegador -> Indicadores -> botao direito ->
  Atualizar -> arraste TRIVIUM_SETUP para o grafico.
#>

# ====================== CONFIG (ajuste se precisar) ======================
$Branch     = "claude/eurusd-t-script-setup-fuaqkc"
$RawUrl     = "https://raw.githubusercontent.com/roneirosar25-creator/Pedrinho/$Branch/indicators/TRIVIUM_SETUP.mq5"
$NomeArq    = "TRIVIUM_SETUP.mq5"
$MetaEditor = "C:\Program Files\MetaTrader 5\metaeditor64.exe"   # caminho do MetaEditor
# =========================================================================

$ErrorActionPreference = "Stop"
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

Write-Host ""
Write-Host "=== Instalador TRIVIUM_SETUP (TRIVIUM369) ===" -ForegroundColor Cyan
Write-Host ""

# 1) Baixa o arquivo do GitHub para a pasta temporaria
$tmp = Join-Path $env:TEMP $NomeArq
Write-Host "[1] Baixando do GitHub..." -ForegroundColor Cyan
try {
    Invoke-WebRequest -Uri $RawUrl -OutFile $tmp -UseBasicParsing
}
catch {
    Write-Host "[ERRO] Falha ao baixar o arquivo:" -ForegroundColor Red
    Write-Host "       $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "       Confira a internet e se a branch '$Branch' ainda existe." -ForegroundColor Yellow
    exit 1
}

$tam = (Get-Item $tmp).Length
if ($tam -lt 1000) {
    Write-Host "[ERRO] Arquivo baixado parece invalido ($tam bytes)." -ForegroundColor Red
    Write-Host "       Talvez a URL/branch tenha mudado." -ForegroundColor Yellow
    exit 1
}
Write-Host "[OK]  Baixado ($([Math]::Round($tam/1KB,1)) KB)" -ForegroundColor Green
Write-Host ""

# 2) Descobre os terminais MT5 instalados (sob %APPDATA%\MetaQuotes\Terminal)
$raizTerm = Join-Path $env:APPDATA "MetaQuotes\Terminal"
if (-not (Test-Path $raizTerm)) {
    Write-Host "[ERRO] Nao encontrei a pasta de terminais MT5:" -ForegroundColor Red
    Write-Host "       $raizTerm" -ForegroundColor Red
    exit 1
}

$terminais = @(Get-ChildItem $raizTerm -Directory -ErrorAction SilentlyContinue | Where-Object {
    Test-Path (Join-Path $_.FullName "MQL5\Indicators")
})

if ($terminais.Count -eq 0) {
    Write-Host "[ERRO] Nenhum terminal com pasta MQL5\Indicators foi encontrado." -ForegroundColor Red
    Write-Host "       Abra o MetaTrader pelo menos uma vez e tente de novo." -ForegroundColor Yellow
    exit 1
}

Write-Host "[2] Terminais MT5 encontrados: $($terminais.Count)" -ForegroundColor Cyan
Write-Host ""

# 3) Copia para cada terminal e compila
$temMeta = Test-Path $MetaEditor
$instalados = 0
$compilados = 0

foreach ($t in $terminais) {
    $destPasta = Join-Path $t.FullName "MQL5\Indicators"
    $dest      = Join-Path $destPasta $NomeArq
    Copy-Item $tmp $dest -Force
    $instalados++
    Write-Host "    -> $dest" -ForegroundColor Gray

    if ($temMeta) {
        Start-Process -FilePath $MetaEditor -ArgumentList "/compile:`"$dest`"","/log" -Wait
        Start-Sleep -Milliseconds 500
        $ex5 = [System.IO.Path]::ChangeExtension($dest, ".ex5")
        if (Test-Path $ex5) {
            Write-Host "       [OK] Compilado" -ForegroundColor Green
            $compilados++
        }
        else {
            Write-Host "       [AVISO] Nao gerou .ex5 -> abra no MetaEditor e tecle F7" -ForegroundColor Yellow
        }
    }
}

Write-Host ""
if (-not $temMeta) {
    Write-Host "[AVISO] MetaEditor nao encontrado em:" -ForegroundColor Yellow
    Write-Host "        $MetaEditor" -ForegroundColor Yellow
    Write-Host "        O .mq5 foi copiado. Abra-o no MetaEditor e tecle F7 para compilar." -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "=== PRONTO! Instalado em $instalados terminal(is), compilado em $compilados. ===" -ForegroundColor Green
Write-Host ""
Write-Host "No MetaTrader:" -ForegroundColor Yellow
Write-Host "  Navegador -> Indicadores -> (botao direito) Atualizar" -ForegroundColor Yellow
Write-Host "  Arraste 'TRIVIUM_SETUP' para o grafico." -ForegroundColor Yellow
