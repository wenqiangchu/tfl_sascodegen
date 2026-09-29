param([string]$SasExecutable = 'sas.exe')
$ErrorActionPreference = 'Stop'
$fixtureDirectory = $PSScriptRoot
New-Item -ItemType Directory -Force (Join-Path $fixtureDirectory 'logs') | Out-Null
$samples = @()
foreach ($recordCount in @(10000, 30000)) {
    foreach ($blockCount in @(2, 4)) {
        foreach ($repeat in 1..3) {
            $modes = if ($repeat % 2) { @('shared', 'independent') } else { @('independent', 'shared') }
            foreach ($mode in $modes) {
                $caseName = "${recordCount}_${blockCount}_${mode}"
                $logName = "logs/bench_${caseName}_${repeat}.log"
                $arguments = "-sysin run_benchmark.sas -sysparm $caseName -log $logName -print logs/bench_${caseName}_${repeat}.lst -nosplash -noterminal"
                $sasProcess = Start-Process -FilePath $SasExecutable -ArgumentList $arguments -WorkingDirectory $fixtureDirectory -WindowStyle Hidden -PassThru
                $sasProcess.WaitForExit()
                $logText = Get-Content -Raw -LiteralPath (Join-Path $fixtureDirectory $logName)
                if ($sasProcess.ExitCode -ne 0 -or $logText -match '(?m)^ERROR' -or $logText -notmatch "NOTE: \[BENCH\] completed $caseName\s") {
                    throw "Benchmark failed: $caseName; inspect $logName"
                }
                $elapsed = [regex]::Match($logText, 'NOTE: \[BENCH\]\s+elapsed_seconds=\s*([\d.]+)')
                $bytes = [regex]::Match($logText, 'NOTE: \[BENCH\]\s+final_intermediate_bytes=\s*(\d+)\s*(?:\r?\n|$)')
                if (-not $elapsed.Success -or -not $bytes.Success -or [long]$bytes.Groups[1].Value -le 0) {
                    throw "Missing benchmark measurement: $caseName"
                }
                $sample = [pscustomobject]@{
                    records = $recordCount; blocks = $blockCount; mode = $mode; repetition = $repeat
                    seconds = [double]::Parse($elapsed.Groups[1].Value, [cultureinfo]::InvariantCulture)
                    final_intermediate_bytes = [long]$bytes.Groups[1].Value
                }
                $samples += $sample
                Write-Output "$caseName repeat=$repeat seconds=$($sample.seconds) bytes=$($sample.final_intermediate_bytes)"
            }
        }
    }
}
$samples | ConvertTo-Json | Set-Content -Encoding utf8 -LiteralPath (Join-Path $fixtureDirectory 'generated/benchmark-results.json')
$comparison = Start-Process -FilePath $SasExecutable -ArgumentList '-sysin compare_benchmark.sas -log logs/benchmark_compare.log -print logs/benchmark_compare.lst -nosplash -noterminal' -WorkingDirectory $fixtureDirectory -WindowStyle Hidden -PassThru
$comparison.WaitForExit()
$comparisonLog = Get-Content -Raw -LiteralPath (Join-Path $fixtureDirectory 'logs/benchmark_compare.log')
if ($comparison.ExitCode -ne 0 -or $comparisonLog -match '(?m)^ERROR' -or $comparisonLog -notmatch 'NOTE: \[BENCH\] all shared and independent results match\.') {
    throw 'Benchmark output comparison failed; inspect logs/benchmark_compare.log'
}
Write-Output 'All benchmark output comparisons passed.'
