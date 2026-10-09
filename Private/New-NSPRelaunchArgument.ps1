function New-NSPRelaunchArgument {
    # The powershell.exe / pwsh.exe argument list for relaunching a script (-ScriptPath, each
    # -ArgumentList element quoted) or a command (-Command, via -EncodedCommand so quotes, $ and
    # newlines survive). Shared by Invoke-NSPElevated and Invoke-NSPPwsh.
    param(
        [string]$ScriptPath,
        [string[]]$ArgumentList = @(),
        [string]$Command,
        [switch]$NoExit
    )

    $psArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass')
    if ($NoExit) { $psArgs += '-NoExit' }
    if ($ScriptPath) {
        $psArgs += @('-File', (ConvertTo-NSPQuotedArgument $ScriptPath))
        foreach ($a in $ArgumentList) { $psArgs += (ConvertTo-NSPQuotedArgument $a) }
    } else {
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Command))
        $psArgs += @('-EncodedCommand', $encoded)
    }
    , $psArgs
}
