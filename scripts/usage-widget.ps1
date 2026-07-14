param([int]$RefreshSeconds = 60)
Add-Type -AssemblyName PresentationFramework
$serverPath = Join-Path $PSScriptRoot "server.mjs"
$settingsDir = Join-Path $env:LOCALAPPDATA "CodexUsageWidget"
$settingsPath = Join-Path $settingsDir "settings.json"
$settings = [pscustomobject]@{ Width = 330; RefreshSeconds = $RefreshSeconds; Opacity = 0.95 }
if (Test-Path $settingsPath) {
 try {
  $saved = Get-Content -Raw $settingsPath | ConvertFrom-Json
  if ([int]$saved.Width -ge 260 -and [int]$saved.Width -le 480) { $settings.Width = [int]$saved.Width }
  if ([int]$saved.RefreshSeconds -ge 10 -and [int]$saved.RefreshSeconds -le 600) { $settings.RefreshSeconds = [int]$saved.RefreshSeconds }
  if ([double]$saved.Opacity -ge 0.35 -and [double]$saved.Opacity -le 1) { $settings.Opacity = [double]$saved.Opacity }
 } catch {}
}
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="Codex Usage" Width="330" Height="190" WindowStyle="None" AllowsTransparency="True" Background="Transparent" Topmost="True" ResizeMode="NoResize">
<Border CornerRadius="16" Background="#1D2026" BorderBrush="#3B414C" BorderThickness="1" Padding="18">
<Grid>
<Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
<Grid Grid.Row="0">
<TextBlock Text="CODEX USAGE" Foreground="#AAB2C0" FontSize="12" FontWeight="SemiBold"/>
<StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
<Button Name="SettingsButton" Content="&#x2699;" ToolTip="设置" Width="28" Height="24" Foreground="#AAB2C0" Background="Transparent" BorderThickness="0" FontSize="15"/>
<Button Name="RefreshButton" Content="&#x21BB;" ToolTip="立即刷新" Width="28" Height="24" Foreground="#AAB2C0" Background="Transparent" BorderThickness="0" FontSize="16"/>
<Button Name="CloseButton" Content="&#x00D7;" ToolTip="关闭" Width="28" Height="24" Foreground="#AAB2C0" Background="Transparent" BorderThickness="0" FontSize="18"/>
</StackPanel>
</Grid>
<Grid Grid.Row="1" Margin="0,13,0,10">
<Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
<StackPanel>
<TextBlock Name="RemainingText" Text="--%" Foreground="#F4F7FB" FontSize="38" FontWeight="Bold"/>
<TextBlock Name="StatusText" Text="正在读取本地额度..." Foreground="#8F98A8" FontSize="12"/>
</StackPanel>
<StackPanel Grid.Column="1" VerticalAlignment="Center">
<TextBlock Text="重置时间" Foreground="#727C8C" FontSize="11" HorizontalAlignment="Right"/>
<TextBlock Name="ResetText" Text="--" Foreground="#CDD3DC" FontSize="13" Margin="0,4,0,0"/>
</StackPanel>
</Grid>
<Grid Grid.Row="2">
<ProgressBar Name="QuotaBar" Height="7" Minimum="0" Maximum="100" Foreground="#36D399" Background="#343A45" BorderThickness="0"/>
<TextBlock Name="UpdatedText" Foreground="#697383" FontSize="10" HorizontalAlignment="Right" Margin="0,13,0,-15"/>
</Grid>
</Grid>
</Border>
</Window>
"@
$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)
$remainingText = $window.FindName("RemainingText")
$statusText = $window.FindName("StatusText")
$resetText = $window.FindName("ResetText")
$updatedText = $window.FindName("UpdatedText")
$quotaBar = $window.FindName("QuotaBar")
$settingsButton = $window.FindName("SettingsButton")
$refreshButton = $window.FindName("RefreshButton")
$closeButton = $window.FindName("CloseButton")
$timer = New-Object System.Windows.Threading.DispatcherTimer

function Save-Settings {
 New-Item -ItemType Directory -Force $settingsDir | Out-Null
 $settings | ConvertTo-Json | Set-Content -Encoding UTF8 $settingsPath
}
function Apply-Settings {
 $window.Width = $settings.Width
 $window.Height = [Math]::Round($settings.Width * 0.575)
 $window.Opacity = $settings.Opacity
 $timer.Interval = [TimeSpan]::FromSeconds($settings.RefreshSeconds)
}
function Get-QuotaSnapshot {
 $info = New-Object System.Diagnostics.ProcessStartInfo
 $info.FileName = "node"
 $info.Arguments = '"' + $serverPath + '" --json'
 $info.UseShellExecute = $false
 $info.CreateNoWindow = $true
 $info.RedirectStandardOutput = $true
 $info.RedirectStandardError = $true
 $process = [System.Diagnostics.Process]::Start($info)
 $stdout = $process.StandardOutput.ReadToEnd()
 $stderr = $process.StandardError.ReadToEnd()
 $process.WaitForExit()
 if ($process.ExitCode -ne 0) { throw $(if ($stderr) { $stderr.Trim() } else { "额度读取失败" }) }
 $stdout | ConvertFrom-Json
}
function Update-Quota {
 try {
  $quota = Get-QuotaSnapshot
  if ($null -eq $quota.primary) { throw "当前快照没有主额度窗口" }
  $primary = $quota.primary
  $remaining = [double]$primary.remaining_percent
  $remainingText.Text = "{0:g}%" -f $remaining
  $quotaBar.Value = $remaining
  $statusText.Text = "剩余 / 已使用 {0:g}% / {1:g} 天周期" -f $primary.used_percent, ($primary.window_minutes / 1440)
  if ($primary.resets_at) { $resetText.Text = ([DateTimeOffset]::Parse($primary.resets_at).ToLocalTime()).ToString("MM-dd  HH:mm") } else { $resetText.Text = "未知" }
  $updatedText.Text = "更新于 " + (Get-Date).ToString("HH:mm:ss")
  if ($remaining -le 10) { $quotaBar.Foreground = "#F87171" } elseif ($remaining -le 30) { $quotaBar.Foreground = "#FBBF24" } else { $quotaBar.Foreground = "#36D399" }
 } catch {
  $remainingText.Text = "--%"
  $statusText.Text = $_.Exception.Message
  $resetText.Text = "读取失败"
  $updatedText.Text = "点击刷新按钮重试"
  $quotaBar.Value = 0
 }
}
function Show-Settings {
 [xml]$settingsXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="悬浮窗设置" Width="360" Height="330" WindowStartupLocation="CenterOwner" ResizeMode="NoResize" Background="#1D2026" Foreground="#E7EBF1">
<Grid Margin="22">
<Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="72"/><RowDefinition Height="72"/><RowDefinition Height="72"/><RowDefinition Height="*"/></Grid.RowDefinitions>
<TextBlock Text="悬浮窗设置" FontSize="18" FontWeight="Bold"/>
<Grid Grid.Row="1"><TextBlock Text="窗口大小" VerticalAlignment="Top" Margin="0,10,0,0"/><TextBlock Name="SizeText" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,10,0,0"/><Slider Name="SizeSlider" Minimum="260" Maximum="480" TickFrequency="10" IsSnapToTickEnabled="True" VerticalAlignment="Bottom" Margin="0,0,0,8"/></Grid>
<Grid Grid.Row="2"><TextBlock Text="自动刷新间隔" VerticalAlignment="Top" Margin="0,10,0,0"/><TextBlock Name="RefreshText" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,10,0,0"/><Slider Name="RefreshSlider" Minimum="10" Maximum="600" TickFrequency="10" IsSnapToTickEnabled="True" VerticalAlignment="Bottom" Margin="0,0,0,8"/></Grid>
<Grid Grid.Row="3"><TextBlock Text="透明度" VerticalAlignment="Top" Margin="0,10,0,0"/><TextBlock Name="OpacityText" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,10,0,0"/><Slider Name="OpacitySlider" Minimum="35" Maximum="100" TickFrequency="5" IsSnapToTickEnabled="True" VerticalAlignment="Bottom" Margin="0,0,0,8"/></Grid>
<StackPanel Grid.Row="4" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Bottom"><Button Name="CancelButton" Content="取消" Width="76" Height="30" Margin="0,0,10,0"/><Button Name="SaveButton" Content="保存" Width="76" Height="30" Background="#36D399" BorderThickness="0"/></StackPanel>
</Grid>
</Window>
"@
 $sr = New-Object System.Xml.XmlNodeReader $settingsXaml
 $dialog = [Windows.Markup.XamlReader]::Load($sr)
 $dialog.Owner = $window
 $sizeSlider = $dialog.FindName("SizeSlider")
 $refreshSlider = $dialog.FindName("RefreshSlider")
 $opacitySlider = $dialog.FindName("OpacitySlider")
 $sizeText = $dialog.FindName("SizeText")
 $refreshText = $dialog.FindName("RefreshText")
 $opacityText = $dialog.FindName("OpacityText")
 $sizeSlider.Value = $settings.Width
 $refreshSlider.Value = $settings.RefreshSeconds
 $opacitySlider.Value = [Math]::Round($settings.Opacity * 100)
 $sizeText.Text = "$([int]$sizeSlider.Value) px"
 $refreshText.Text = "$([int]$refreshSlider.Value) 秒"
 $opacityText.Text = "$([int]$opacitySlider.Value)%"
 $sizeSlider.Add_ValueChanged({ $sizeText.Text = "$([int]$sizeSlider.Value) px" })
 $refreshSlider.Add_ValueChanged({ $refreshText.Text = "$([int]$refreshSlider.Value) 秒" })
 $opacitySlider.Add_ValueChanged({ $opacityText.Text = "$([int]$opacitySlider.Value)%" })
 $dialog.FindName("CancelButton").Add_Click({ $dialog.Close() })
 $dialog.FindName("SaveButton").Add_Click({
  $settings.Width = [int]$sizeSlider.Value
  $settings.RefreshSeconds = [int]$refreshSlider.Value
  $settings.Opacity = [double]$opacitySlider.Value / 100
  Apply-Settings
  Save-Settings
  $dialog.Close()
 })
 [void]$dialog.ShowDialog()
}$window.Add_MouseLeftButtonDown({ if ($_.ButtonState -eq "Pressed") { $window.DragMove() } })
$closeButton.Add_Click({ $window.Close() })
$refreshButton.Add_Click({ Update-Quota })
$settingsButton.Add_Click({ Show-Settings })
$timer.Add_Tick({ Update-Quota })
Apply-Settings
$timer.Start()
$window.Add_ContentRendered({ Update-Quota })
$window.Add_Closed({ $timer.Stop() })
[void]$window.ShowDialog()


