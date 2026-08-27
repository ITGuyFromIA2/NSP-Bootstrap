function ConvertFrom-NSPSecureString {
    <#
    .SYNOPSIS
        Returns the plaintext of a SecureString. Works on Windows PowerShell 5.1 AND PowerShell 7+.

    .DESCRIPTION
        PowerShell 7 has `ConvertFrom-SecureString -AsPlainText`, but 5.1 does not, and 5.1 is the
        NSP toolkit floor. The BSTR marshal below is the portable way that behaves identically on
        both. The unmanaged buffer is always zeroed and freed in the finally block.

        Internal helper - not exported.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][System.Security.SecureString]$SecureString
    )

    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}
