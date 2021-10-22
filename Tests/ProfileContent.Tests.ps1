﻿BeforeAll {
    Import-Module WSL-IpHandler -Force
    Set-Variable OriginalProfileContent @('# First line comments', '# Second line comments')
    Set-Variable WslProfileContent (InModuleScope WSL-IpHandler { Get-ProfileContent })
}

Describe 'Given profile file' {
    BeforeEach {
        Set-Variable ProfileFilePath 'TestDrive:\test_profile.ps1'
    }
    AfterEach {
        Remove-Item $ProfileFilePath -ErrorAction SilentlyContinue
    }
    Context ' That does not exist' {
        It ' Set-ProfileContent should create profile file and add content' {
            Set-ProfileContent -ProfilePath $ProfileFilePath
            $ProfileFilePath |
                Should -FileContentMatchMultilineExactly ($WslProfileContent -join "`r`n")
        }
        It ' Remove-ProfileContent should silently ignore absent file and not create file' {
            Remove-ProfileContent -ProfilePath $ProfileFilePath
            $ProfileFilePath | Should -Not -Exist
        }
    }

    Context ' That is empty' {
        BeforeEach {
            Set-Content -Path $ProfileFilePath -Value @()
        }
        It ' Set-ProfileContent should add content' {
            Set-ProfileContent -ProfilePath $ProfileFilePath
            $ProfileFilePath |
                Should -FileContentMatchMultilineExactly ($WslProfileContent -join "`r`n")
        }
        It ' Remove-ProfileContent should leave file empty' {
            Remove-ProfileContent -ProfilePath $ProfileFilePath
            $ProfileFilePath | Should -Exist
            $actualProfileContent = Get-Content $ProfileFilePath
            $actualProfileContent | Should -BeNullOrEmpty
        }
    }

    Context ' That is non-empty' {
        BeforeEach {
            Set-Content -Path $ProfileFilePath -Value $OriginalProfileContent
        }
        It ' Set-ProfileContent should add content keeping the original content' {
            Set-ProfileContent -ProfilePath $ProfileFilePath
            $expected = ($OriginalProfileContent + $WslProfileContent) -join "`r`n"
            $ProfileFilePath | Should -FileContentMatchMultilineExactly $expected
        }
        It ' Remove-ProfileContent should not change file' {
            Remove-ProfileContent -ProfilePath $ProfileFilePath
            $ProfileFilePath | Should -Exist
            $ProfileFilePath |
                Should -FileContentMatchMultilineExactly ($OriginalProfileContent -join "`r`n")
        }
    }

    Context ' That has WSL-IpHandler Content' {
        BeforeEach {
            Set-Variable FullContent ($OriginalProfileContent + $WslProfileContent)
            Set-Content -Path $ProfileFilePath -Value $FullContent
        }
        It ' Set-ProfileContent should not add any content' {
            Set-ProfileContent -ProfilePath $ProfileFilePath
            $ProfileFilePath | Should -FileContentMatchMultilineExactly ($FullContent -join "`r`n")
        }
        It ' Remove-ProfileContent should remove WSL-IpHandler Content' {
            Remove-ProfileContent -ProfilePath $ProfileFilePath
            $ProfileFilePath |
                Should -FileContentMatchMultilineExactly ($OriginalProfileContent -join "`r`n")
        }
    }
}
