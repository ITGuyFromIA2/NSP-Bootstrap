function New-NSPRandomPassword {
    <#
    .SYNOPSIS
        Cryptographically-random password generator that works on Windows PowerShell 5.1 AND
        PowerShell 7+.

    .DESCRIPTION
        Adopted verbatim (behaviour-preserving) from the NSP-FGTIPSecTools CLI Builder / IPSec
        Master Orchestrator, where it replaced [System.Web.Security.Membership]::GeneratePassword -
        that type lives only in 5.1's System.Web.dll and throws "Unable to find type" under 7+.
        System.Security.Cryptography.RandomNumberGenerator exists on both.

        Character set excludes quotes, backtick, and space so the output is safe to drop into
        FortiGate CLI arguments, PowerShell string literals, and generated scripts. Look-alike
        characters (0/O, 1/l/I) are also excluded.

    .PARAMETER Length
        Total length. Default 16.

    .PARAMETER MinSpecial
        Minimum count of special characters (!@#$%^&*-_=+), placed then shuffled. Default 4.

    .EXAMPLE
        New-NSPRandomPassword

    .EXAMPLE
        New-NSPRandomPassword -Length 24 -MinSpecial 6
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [ValidateRange(4, 256)][int]$Length = 16,
        [ValidateRange(0, 64)][int]$MinSpecial = 4
    )

    if ($MinSpecial -gt $Length) {
        throw "New-NSPRandomPassword: -MinSpecial ($MinSpecial) cannot exceed -Length ($Length)."
    }

    $alphanumeric = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
    $special      = '!@#$%^&*-_=+'   # excludes quotes/backtick/space - those break downstream CLI args

    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $bytes = [byte[]]::new(4)
        $chars = [System.Collections.Generic.List[char]]::new()
        for ($i = 0; $i -lt $MinSpecial; $i++) {
            $rng.GetBytes($bytes)
            $chars.Add($special[[BitConverter]::ToUInt32($bytes, 0) % $special.Length])
        }
        for ($i = $MinSpecial; $i -lt $Length; $i++) {
            $rng.GetBytes($bytes)
            $chars.Add($alphanumeric[[BitConverter]::ToUInt32($bytes, 0) % $alphanumeric.Length])
        }
        # Fisher-Yates shuffle so the special chars aren't always clustered at the front
        for ($i = $chars.Count - 1; $i -gt 0; $i--) {
            $rng.GetBytes($bytes)
            $j = [BitConverter]::ToUInt32($bytes, 0) % ($i + 1)
            $tmp = $chars[$i]; $chars[$i] = $chars[$j]; $chars[$j] = $tmp
        }
        -join $chars
    } finally {
        $rng.Dispose()
    }
}
