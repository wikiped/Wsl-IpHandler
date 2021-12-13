if (-not ('System.Windows.Forms.NotifyIcon' -as [type])) {
    Add-Type -AssemblyName System.Windows.Forms
}

function Show-ToastMessage {
    <#
.SYNOPSIS
Shows Toast Message

.DESCRIPTION
Shows Toast Message with specified Title and Text for specified duration

.PARAMETER Title
Toast Message Title

.PARAMETER Text
Toast Message Text

.PARAMETER Type
Type of Toast - sets the icon shown in Toast Message. One of:
'None', 'Info', 'Warning', 'Error'. Defaults to 'None'.

.PARAMETER Seconds
Number of seconds to show the toast message. Defaults to 5.

.EXAMPLE
Show-ToastMessage 'Message Title' 'Test Message' 5

.NOTES
Uses Windows Forms
Source: https://stackoverflow.com/questions/61971517
#>    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [string]$Text,

        [Parameter()]
        [ValidateSet('None', 'Info', 'Warning', 'Error')]
        [System.Windows.Forms.ToolTipIcon]$Type = 'None',

        [Parameter()]
        [int]$Seconds = 5
    )
    $Milliseconds = $Seconds * 1000

    $balloon = New-Object System.Windows.Forms.NotifyIcon

    $path = (Get-Process -Id $pid).Path

    $balloon.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($path)

    $balloon.BalloonTipIcon = $Type
    $balloon.BalloonTipText = $Text
    $balloon.BalloonTipTitle = $Title

    $balloon.Visible = $true
    $balloon.ShowBalloonTip($Milliseconds)
}

Export-ModuleMember -Function Show-ToastMessage
