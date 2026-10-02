function ConvertTo-NSPQuotedArgument {
    # Quotes one command-line argument for Start-Process -ArgumentList (Windows CRT rules): wraps in
    # double quotes when it contains whitespace or a quote, doubling backslashes that precede a quote.
    # Arguments that need no quoting (e.g. '-ShimPath') pass through unchanged.
    param([AllowEmptyString()][string]$Value)

    if ($Value -eq '') { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }

    $escaped = [regex]::Replace($Value, '(\\*)"', { param($m) ($m.Groups[1].Value * 2) + '\"' })
    $escaped = [regex]::Replace($escaped, '(\\+)$', { param($m) $m.Groups[1].Value * 2 })
    return '"' + $escaped + '"'
}
