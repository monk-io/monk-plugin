function Deploy-Vercel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Action = 'deploy',
        [Parameter()]
        [string]$Path = '.',
        [Parameter()]
        [switch]$Public,
        [Parameter()]
        [string]$Output = 'stdout'
    )
    process {
        $version = & vercel --version 2>&1
        if ($version -match '1\.[0-9]+\.[0-9]+') {
            $verclArgs = @()
            $verclArgs += $Action
            $verclArgs += "--path `"$Path`""
            if ($Public) {
                $verclArgs += "--public"
            }
            if ($Output -ne 'stdout') {
                $verclArgs += "--output `"$Output`""
            }
            & vercel --name $verclArgs
        } else {
            $verclArgs = @()
            $verclArgs += $Action
            $verclArgs += "--path `"$Path`""
            & vercel --name $verclArgs
        }
    }
}
Export-ModuleMember -Function Deploy-Vercel