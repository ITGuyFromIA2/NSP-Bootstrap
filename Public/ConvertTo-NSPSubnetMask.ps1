function ConvertTo-NSPSubnetMask {
    <#
    .SYNOPSIS
        CIDR prefix length (0-32) -> dotted-decimal subnet mask, e.g. 24 -> "255.255.255.0".

    .DESCRIPTION
        Adopted verbatim (behaviour-preserving) from the NSP-FGTIPSecTools CLI Builder, where it
        exists because FortiGate's "config firewall address" (type ipmask) wants
        "set subnet <ip> <netmask>" in dotted-decimal form, not slash notation.

        Built byte-by-byte from the bit count rather than a single 32-bit shift - avoids the signed/
        unsigned bit-shift overflow pitfalls a naive `[uint32]::MaxValue -shl (32-$CIDR)` approach can
        hit in PowerShell (hex literals/shifts on Int32 sign-extend in surprising ways).

    .PARAMETER CIDR
        Prefix length, 0-32.

    .EXAMPLE
        ConvertTo-NSPSubnetMask -CIDR 24

    .EXAMPLE
        ConvertTo-NSPSubnetMask 8
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory, Position = 0)][ValidateRange(0, 32)][int]$CIDR)

    $bytes = @(0, 0, 0, 0)
    for ($i = 0; $i -lt 4; $i++) {
        $bitsForThisByte = [Math]::Min(8, [Math]::Max(0, $CIDR - ($i * 8)))
        $bytes[$i] = [byte](256 - [Math]::Pow(2, 8 - $bitsForThisByte))
        if ($bitsForThisByte -eq 0) { $bytes[$i] = 0 }
        if ($bitsForThisByte -eq 8) { $bytes[$i] = 255 }
    }
    return ($bytes -join '.')
}
