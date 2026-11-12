<#
  XP12 Forest Tweak  -  Windows window
  Version 1.6.0 (2026-11-12)   https://github.com/E11i0t09/xp12-forest-tweak

  The window for XP12_ForestTweak.ps1. All the work is done by the functions of XP12_ForestTweak.ps1
  (the same as in the console menu); this file only shows them in a window:
  - the tool runs in a second PowerShell runspace, so the window stays usable while it works
  - its text output goes to the log of the window, its progress to the progress bar, and its
    questions ([Y/n]) become dialogs
  - update check at start; "Update now" downloads the new version from GitHub, checks its SHA-256
    against the checksum GitHub publishes, and installs it (Setup: runs the new setup silently;
    ZIP without installation: replaces the own files, old ones are kept until it worked)

  Start: Start_ForestTweak.bat or the shortcut "Forest Tweak". Console menu: Start_ForestTweak_Console.bat
  The console window behind it is hidden once the window has started (it stays visible after a start error).
  (c) E11i0t09. Free community project, not for sale. License: CC BY-NC-SA 4.0 with additional permission (free use also for companies and flight schools), see the LICENSE file.
#>
param([string]$XPlane = '', [switch]$UninstallRestore)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
$Core = Join-Path $Here 'XP12_ForestTweak.ps1'
$GuiVersion = '1.6.0'
$Repo = 'E11i0t09/xp12-forest-tweak'
$Dot = [string][char]0xB7; $Bul = [string][char]0x2022      # middle dot and bullet (the file stays plain ASCII)
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

function Show-Fatal([string]$msg) { [void][System.Windows.MessageBox]::Show($msg, 'XP12 Forest Tweak', 'OK', 'Error') }
if (-not (Test-Path -LiteralPath $Core)) { Show-Fatal 'XP12_ForestTweak.ps1 was not found next to this file. Please unzip or install the tool again.'; exit 1 }

# ---------------------------------------------------------------- shared state window <-> worker
$sync = [hashtable]::Synchronized(@{
    Log = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
    Ask = $null; Answer = $null; Prog = $null; Mute = $false; AutoYes = $false
    Part = ''; Capture = $null; CapPart = ''
})

# runs in the worker before the tool is loaded: Write-Host / Read-Host / Write-Progress of the tool go to the window
$WorkerBoot = @'
function global:Write-Host {
    param([Parameter(Position = 0, ValueFromRemainingArguments = $true)][object[]]$Object, [object]$ForegroundColor,
          [object]$BackgroundColor, [switch]$NoNewline, [object]$Separator = ' ')
    $t = (@($Object) | ForEach-Object { "$_" }) -join $Separator
    if ($null -ne $sync.Capture) {
        $t = $sync.CapPart + $t
        if ($NoNewline) { $sync.CapPart = $t } else { $sync.CapPart = ''; [void]$sync.Capture.Add($t) }
        return
    }
    if ($sync.Mute) { return }
    $t = $sync.Part + $t
    if ($NoNewline) { $sync.Part = $t } else { $sync.Part = ''; $sync.Log.Enqueue($t) }
}
function global:Read-Host {
    param([Parameter(Position = 0)][object]$Prompt)
    if ($sync.AutoYes) { return 'y' }
    $sync.Answer = $null; $sync.Ask = [string]$Prompt
    while ($null -eq $sync.Answer) { Start-Sleep -Milliseconds 100 }
    $a = [string]$sync.Answer; $sync.Answer = $null; $sync.Ask = $null
    return $a
}
function global:Write-Progress {
    param([Parameter(Position = 0)][string]$Activity, [Parameter(Position = 1)][string]$Status, [int]$PercentComplete = -1,
          [int]$SecondsRemaining = -1, [switch]$Completed, [int]$Id = 0, [string]$CurrentOperation)
    if ($sync.Mute) { return }
    if ($Completed) { $sync.Prog = $null } else { $sync.Prog = @{ A = $Activity; S = $Status; P = $PercentComplete; R = $SecondsRemaining } }
}
function global:Get-GuiState {
    $off = Test-SwitchedOff $xp
    $st = $script:StCache
    if (-not $st) { $st = Get-ForestState $xp $targets; $script:StCache = $st }
    $ho = Get-HedgeOverview $xp
    $ki = Get-KnickInfo $xp
    $det = Get-HmDetect $xp
    $hasSh = [bool]($ho.Files.Count -or $det.Pro.Count -or $det.Free.Count)
    $hchoice = if ($hasSh) { Get-HedgeChoice $xp $ho.Overall } else { 'default' }
    $info = Get-HmInfo $xp
    $curC = @(); if ($info) { $curC = @($info.Countries) }
    $pc = @(); $proAll = 0
    if ($det.Pro.Count) {
        $opts = Get-ProCountries $xp      # returns its list as one object (,$opts): take it apart here
        $pc = @(foreach ($o in $opts) { [pscustomobject]@{ Key = $o[0]; Name = $o[1]; Tiles = $o[2] } })
        $proAll = (Get-HmProTiles $xp).Count
    }
    $ver = Get-XPVersion $xp
    $old = $ki.On -and (($info -and $info.Version -ne $Version) -or (Get-KnickLibVersion $xp) -ne $Version)
    $sync.Capture = New-Object System.Collections.ArrayList; $sync.CapPart = ''
    try { Show-Status $xp $targets } finally { $lines = @($sync.Capture); $sync.Capture = $null }
    [pscustomobject]@{
        Version = $Version; XP = $xp; XPVer = $ver[1]; TestedXP = $TestedXP; Off = $off; TweakDir = (Get-TweakDir $xp)
        X = $st.X; H = $st.H; N = $st.N; NOrig = $st.NOrig; NReset = $st.NReset; NOld = $st.NOld; Files = $st.Files
        HasSh = $hasSh; Hedges = $hchoice; HedgeFiles = $ho.Files.Count; Countries = $curC; KnicksOn = $ki.On; OverlayOld = [bool]$old
        Pro = @($det.Pro); Free = @($det.Free); Both = @($det.Both); ProCountries = $pc; ProAll = $proAll
        GF = @($gf | ForEach-Object { Split-Path -Leaf $_ }); UseGF = $global:useGf
        Hint = $(if ($off) { '' } else { Get-HedgeHint $xp }); Veg = (Get-VegSlider $xp); Status = $lines
        MinFac = $MinFac; MinHeight = $MinHeight
    }
}
function global:Set-GuiTargets([bool]$use) {
    if ($use -ne $global:useGf) { $global:useGf = $use; $global:targets = @(Get-Targets $xp $gf $use); $script:StCache = $null }
}
'@

$iss = [initialsessionstate]::CreateDefault()
try { $iss.ExecutionPolicy = 'Bypass' } catch { }
$rs = [runspacefactory]::CreateRunspace($iss)
$rs.ThreadOptions = 'ReuseThread'
$rs.Open()
$rs.SessionStateProxy.SetVariable('sync', $sync)
$rs.SessionStateProxy.SetVariable('FdtLib', $true)
$rs.SessionStateProxy.SetVariable('CorePath', $Core)
$rs.SessionStateProxy.SetVariable('XPArg', $XPlane)

# ---------------------------------------------------------------- window layout
$Xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="XP12 Forest Tweak" Width="900" Height="580" ResizeMode="CanMinimize" WindowStartupLocation="CenterScreen"
        FontFamily="Segoe UI" FontSize="13.5" Background="{DynamicResource Panel}" Foreground="{DynamicResource Txt}" UseLayoutRounding="True">
  <Window.Resources>
    <SolidColorBrush x:Key="Panel" Color="#FFFFFF"/><SolidColorBrush x:Key="Nav" Color="#FAFAFA"/><SolidColorBrush x:Key="Line" Color="#D6D6D6"/>
    <SolidColorBrush x:Key="Txt" Color="#1B1B1B"/><SolidColorBrush x:Key="Mut" Color="#5D5D5D"/><SolidColorBrush x:Key="Acc" Color="#2F7D32"/>
    <SolidColorBrush x:Key="Acc2" Color="#E8F3E8"/><SolidColorBrush x:Key="Blue" Color="#0067C0"/><SolidColorBrush x:Key="Bd" Color="#9A9A9A"/>
    <SolidColorBrush x:Key="Btn" Color="#FDFDFD"/><SolidColorBrush x:Key="WarnBg" Color="#FFF3E0"/><SolidColorBrush x:Key="WarnBd" Color="#F0C58A"/>
    <SolidColorBrush x:Key="InfoBg" Color="#E8F1FB"/><SolidColorBrush x:Key="InfoBd" Color="#9CC3EA"/><SolidColorBrush x:Key="WarnTxt" Color="#B26A00"/>
    <SolidColorBrush x:Key="LogBg" Color="#1E1E1E"/><SolidColorBrush x:Key="LogTxt" Color="#D0D0D0"/><SolidColorBrush x:Key="BoxBg" Color="#FFFFFF"/>

    <Style TargetType="TextBlock"><Setter Property="TextWrapping" Value="Wrap"/></Style>
    <Style x:Key="H2" TargetType="TextBlock"><Setter Property="FontSize" Value="17"/><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Margin" Value="0,0,0,8"/></Style>
    <Style x:Key="H3" TargetType="TextBlock"><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Margin" Value="0,0,0,6"/></Style>
    <Style x:Key="Small" TargetType="TextBlock"><Setter Property="FontSize" Value="12"/><Setter Property="Foreground" Value="{DynamicResource Mut}"/><Setter Property="TextWrapping" Value="Wrap"/></Style>
    <Style x:Key="Group" TargetType="Border"><Setter Property="BorderBrush" Value="{DynamicResource Line}"/><Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="6"/><Setter Property="Padding" Value="12,9"/><Setter Property="Margin" Value="0,0,0,9"/></Style>
    <Style x:Key="Banner" TargetType="Border"><Setter Property="Background" Value="{DynamicResource WarnBg}"/><Setter Property="BorderBrush" Value="{DynamicResource WarnBd}"/>
      <Setter Property="BorderThickness" Value="1"/><Setter Property="CornerRadius" Value="6"/><Setter Property="Padding" Value="12,8"/><Setter Property="Margin" Value="0,0,0,10"/></Style>
    <Style x:Key="Info" TargetType="Border" BasedOn="{StaticResource Banner}"><Setter Property="Background" Value="{DynamicResource InfoBg}"/><Setter Property="BorderBrush" Value="{DynamicResource InfoBd}"/></Style>

    <Style TargetType="Button">
      <Setter Property="Foreground" Value="{DynamicResource Txt}"/><Setter Property="Background" Value="{DynamicResource Btn}"/><Setter Property="BorderBrush" Value="{DynamicResource Bd}"/>
      <Setter Property="Padding" Value="16,5"/><Setter Property="Margin" Value="8,0,0,0"/><Setter Property="MinWidth" Value="90"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
        <Border x:Name="b" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="4" Padding="{TemplateBinding Padding}">
          <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
        <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="{DynamicResource Acc}"/></Trigger>
          <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.45"/></Trigger></ControlTemplate.Triggers>
      </ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key="Pri" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Background" Value="{DynamicResource Blue}"/><Setter Property="BorderBrush" Value="{DynamicResource Blue}"/><Setter Property="Foreground" Value="White"/>
    </Style>

    <Style x:Key="Opt" TargetType="RadioButton">
      <Setter Property="Foreground" Value="{DynamicResource Txt}"/><Setter Property="Margin" Value="0,0,5,0"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="RadioButton">
        <Border x:Name="b" Background="{DynamicResource Panel}" BorderBrush="{DynamicResource Line}" BorderThickness="1" CornerRadius="6" Padding="7,5">
          <DockPanel LastChildFill="True">
            <Grid DockPanel.Dock="Left" Width="13" Height="13" Margin="0,2,6,0" VerticalAlignment="Top">
              <Ellipse x:Name="o" Stroke="{DynamicResource Mut}" StrokeThickness="1.4"/>
              <Ellipse x:Name="i" Width="7" Height="7" Fill="{DynamicResource Acc}" Visibility="Collapsed"/></Grid>
            <ContentPresenter/></DockPanel></Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsChecked" Value="True"><Setter TargetName="b" Property="Background" Value="{DynamicResource Acc2}"/>
            <Setter TargetName="b" Property="BorderBrush" Value="{DynamicResource Acc}"/><Setter TargetName="i" Property="Visibility" Value="Visible"/>
            <Setter TargetName="o" Property="Stroke" Value="{DynamicResource Acc}"/></Trigger>
          <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="o" Property="Stroke" Value="{DynamicResource Acc}"/></Trigger>
          <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.45"/></Trigger>
        </ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="{DynamicResource Txt}"/><Setter Property="Margin" Value="0,0,14,0"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="CheckBox">
        <StackPanel Orientation="Horizontal" Background="Transparent">
          <Border x:Name="b" Width="14" Height="14" CornerRadius="3" BorderThickness="1.4" BorderBrush="{DynamicResource Mut}" Background="{DynamicResource Panel}" Margin="0,0,6,0" VerticalAlignment="Center">
            <Path x:Name="p" Data="M2.5,7 L5.5,10 L11,3.5" Stroke="White" StrokeThickness="1.8" Visibility="Collapsed"/></Border>
          <ContentPresenter VerticalAlignment="Center"/></StackPanel>
        <ControlTemplate.Triggers>
          <Trigger Property="IsChecked" Value="True"><Setter TargetName="b" Property="Background" Value="{DynamicResource Acc}"/>
            <Setter TargetName="b" Property="BorderBrush" Value="{DynamicResource Acc}"/><Setter TargetName="p" Property="Visibility" Value="Visible"/></Trigger>
          <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger>
        </ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key="NavBtn" TargetType="RadioButton">
      <Setter Property="Foreground" Value="{DynamicResource Txt}"/><Setter Property="Margin" Value="0,0,0,2"/><Setter Property="Cursor" Value="Hand"/><Setter Property="GroupName" Value="nav"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="RadioButton">
        <Border x:Name="b" CornerRadius="6" Padding="10,8" Background="Transparent" BorderThickness="3,0,0,0" BorderBrush="Transparent">
          <ContentPresenter x:Name="c"/></Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsChecked" Value="True"><Setter TargetName="b" Property="Background" Value="{DynamicResource Acc2}"/>
            <Setter TargetName="b" Property="BorderBrush" Value="{DynamicResource Acc}"/><Setter Property="Foreground" Value="{DynamicResource Acc}"/><Setter Property="FontWeight" Value="SemiBold"/></Trigger>
          <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="{DynamicResource Acc2}"/></Trigger>
          <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger>
        </ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style TargetType="TextBox"><Setter Property="Background" Value="{DynamicResource BoxBg}"/><Setter Property="Foreground" Value="{DynamicResource Txt}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource Bd}"/><Setter Property="Padding" Value="3,1"/></Style>
    <Style x:Key="Log" TargetType="TextBox"><Setter Property="Background" Value="{DynamicResource LogBg}"/><Setter Property="Foreground" Value="{DynamicResource LogTxt}"/>
      <Setter Property="FontFamily" Value="Consolas"/><Setter Property="FontSize" Value="12"/><Setter Property="IsReadOnly" Value="True"/><Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="8"/><Setter Property="VerticalScrollBarVisibility" Value="Auto"/><Setter Property="HorizontalScrollBarVisibility" Value="Auto"/><Setter Property="TextWrapping" Value="NoWrap"/></Style>
    <Style x:Key="Star" TargetType="Border"><Setter Property="Background" Value="{DynamicResource Acc}"/><Setter Property="CornerRadius" Value="8"/>
      <Setter Property="Padding" Value="5,0"/><Setter Property="Margin" Value="5,1,0,0"/><Setter Property="VerticalAlignment" Value="Top"/></Style>
  </Window.Resources>

  <Grid>
    <Grid.ColumnDefinitions><ColumnDefinition Width="190"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
    <!-- navigation -->
    <Border Background="{DynamicResource Nav}" BorderBrush="{DynamicResource Line}" BorderThickness="0,0,1,0" Padding="8,10">
      <DockPanel>
        <TextBlock x:Name="VerText" DockPanel.Dock="Bottom" Style="{StaticResource Small}" Margin="10,0,0,4"/>
        <StackPanel x:Name="NavPanel">
          <RadioButton x:Name="NavRec" Style="{StaticResource NavBtn}" Content="Recommended" IsChecked="True"/>
          <RadioButton x:Name="NavSet" Style="{StaticResource NavBtn}" Content="Settings"/>
          <RadioButton x:Name="NavSta" Style="{StaticResource NavBtn}" Content="Status"/>
          <RadioButton x:Name="NavChk" Style="{StaticResource NavBtn}" Content="Check &amp; repair"/>
          <Border BorderBrush="{DynamicResource Line}" BorderThickness="0,1,0,0" Margin="4,8"/>
          <RadioButton x:Name="NavSw" Style="{StaticResource NavBtn}" Content="Quick switch"/>
          <RadioButton x:Name="NavRes" Style="{StaticResource NavBtn}" Content="Restore original"/>
          <Border BorderBrush="{DynamicResource Line}" BorderThickness="0,1,0,0" Margin="4,8"/>
          <RadioButton x:Name="NavLog" Style="{StaticResource NavBtn}" Content="Log / help"/>
        </StackPanel>
      </DockPanel>
    </Border>

    <Grid Grid.Column="1" Margin="20,14,20,14">
      <!-- license (first start of the ZIP version; the setup asks for it itself) -->
      <DockPanel x:Name="PgLic" Visibility="Collapsed">
        <TextBlock DockPanel.Dock="Top" Style="{StaticResource H2}" Text="License"/>
        <TextBlock DockPanel.Dock="Top" Style="{StaticResource Small}" Margin="0,0,0,8" Text="Please read the license before you use the tool. The hedge map data in the data folder keep the licenses of their sources (data\DATA_LICENSES.txt)."/>
        <DockPanel DockPanel.Dock="Bottom" LastChildFill="False" Margin="0,10,0,0">
          <Button x:Name="BtLicOk" DockPanel.Dock="Right" Style="{StaticResource Pri}" Content="Continue" IsEnabled="False"/>
          <Button x:Name="BtLicNo" DockPanel.Dock="Right" Content="Quit"/>
          <CheckBox x:Name="CbLic" DockPanel.Dock="Left" VerticalAlignment="Center" Content="I have read the license and accept it"/>
        </DockPanel>
        <TextBox x:Name="LicBox" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" FontSize="12.5" Padding="8"/>
      </DockPanel>

      <!-- start -->
      <Grid x:Name="PgLoad">
        <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center" Width="420">
          <TextBlock Style="{StaticResource H2}" Text="Looking at your X-Plane ..." HorizontalAlignment="Center"/>
          <ProgressBar x:Name="LoadBar" Height="8" IsIndeterminate="True" Margin="0,6"/>
          <TextBlock x:Name="LoadText" Style="{StaticResource Small}" HorizontalAlignment="Center" Text="reading the forest files"/>
        </StackPanel>
      </Grid>

      <!-- recommended -->
      <DockPanel x:Name="PgRec" Visibility="Collapsed">
        <StackPanel DockPanel.Dock="Top">
          <Border x:Name="BnUpd" Style="{StaticResource Info}" Visibility="Collapsed"><DockPanel>
            <Button x:Name="BtUpdNow" DockPanel.Dock="Right" Style="{StaticResource Pri}" Content="Update now"/>
            <Button x:Name="BtUpdLater" DockPanel.Dock="Right" Content="Later"/>
            <TextBlock x:Name="TxUpd" VerticalAlignment="Center"/></DockPanel></Border>
          <Border x:Name="BnRe" Style="{StaticResource Info}" Visibility="Collapsed"><DockPanel>
            <Button x:Name="BtReApply" DockPanel.Dock="Right" Style="{StaticResource Pri}" Content="Apply again"/>
            <Button x:Name="BtReLater" DockPanel.Dock="Right" Content="Later"/>
            <TextBlock x:Name="TxRe" VerticalAlignment="Center"/></DockPanel></Border>
          <Border x:Name="BnReset" Style="{StaticResource Banner}" Visibility="Collapsed"><DockPanel>
            <Button x:Name="BtReset" DockPanel.Dock="Right" Style="{StaticResource Pri}" Content="Apply again"/>
            <TextBlock x:Name="TxReset" VerticalAlignment="Center"/></DockPanel></Border>
          <Border x:Name="BnHint" Style="{StaticResource Banner}" Visibility="Collapsed"><DockPanel>
            <Button x:Name="BtHint" DockPanel.Dock="Right" Style="{StaticResource Pri}" Content="Bring up to date"/>
            <TextBlock x:Name="TxHint" VerticalAlignment="Center"/></DockPanel></Border>
          <Border x:Name="BnOff" Style="{StaticResource Info}" Visibility="Collapsed"><DockPanel>
            <Button x:Name="BtOffBack" DockPanel.Dock="Right" Style="{StaticResource Pri}" Content="Switch back"/>
            <TextBlock VerticalAlignment="Center" Text="Switched to original with Quick switch - your tweak is kept."/></DockPanel></Border>
          <TextBlock Style="{StaticResource H2}" Text="Recommended setup"/>
          <Border Style="{StaticResource Group}"><StackPanel>
            <Grid x:Name="RecGrid"><Grid.ColumnDefinitions><ColumnDefinition Width="150"/><ColumnDefinition/></Grid.ColumnDefinitions></Grid>
            <TextBlock x:Name="RecPlan" Style="{StaticResource Small}" Margin="0,8,0,0"/></StackPanel></Border>
          <Border Style="{StaticResource Group}"><StackPanel>
            <TextBlock Style="{StaticResource H3}" Text="Now in X-Plane"/>
            <TextBlock x:Name="RecNow"/>
            <TextBlock x:Name="RecNote" Style="{StaticResource Small}" Margin="0,4,0,0" Visibility="Collapsed"/></StackPanel></Border>
        </StackPanel>
        <DockPanel DockPanel.Dock="Bottom" VerticalAlignment="Bottom" LastChildFill="False">
          <Button x:Name="BtRecApply" DockPanel.Dock="Right" Style="{StaticResource Pri}" Content="Apply"/>
          <Button x:Name="BtRecCust" DockPanel.Dock="Right" Content="Customize..."/>
          <TextBlock x:Name="RunRec" DockPanel.Dock="Left" VerticalAlignment="Center" Foreground="{DynamicResource WarnTxt}" FontSize="12.5" Text="&#x26A0; Quit X-Plane first" Visibility="Collapsed"/>
        </DockPanel>
      </DockPanel>

      <!-- settings -->
      <DockPanel x:Name="PgSet" Visibility="Collapsed">
        <StackPanel DockPanel.Dock="Top">
          <TextBlock Style="{StaticResource H2}" Text="Settings"/>
          <Border Style="{StaticResource Group}"><StackPanel>
            <DockPanel><CheckBox x:Name="CbGf" DockPanel.Dock="Right" Content="Include Global Forests v2" FontSize="12.5" Margin="0" Visibility="Collapsed"/>
              <TextBlock Style="{StaticResource H3}" Text="Tree spacing"/></DockPanel>
            <UniformGrid Columns="5">
              <RadioButton x:Name="D10" Style="{StaticResource Opt}" GroupName="d"><StackPanel><TextBlock FontWeight="SemiBold" Text="Original"/><TextBlock Style="{StaticResource Small}" Text="as in X-Plane"/></StackPanel></RadioButton>
              <RadioButton x:Name="D08" Style="{StaticResource Opt}" GroupName="d"><StackPanel><TextBlock FontWeight="SemiBold" Text="Natural"/><TextBlock Style="{StaticResource Small}" Text="about 1.5x trees"/></StackPanel></RadioButton>
              <RadioButton x:Name="D07" Style="{StaticResource Opt}" GroupName="d"><StackPanel><StackPanel Orientation="Horizontal"><TextBlock FontWeight="SemiBold" Text="Dense"/><Border Style="{StaticResource Star}"><TextBlock Foreground="White" FontSize="10.5" Text="&#x2605;"/></Border></StackPanel><TextBlock Style="{StaticResource Small}" Text="about 2x trees"/></StackPanel></RadioButton>
              <RadioButton x:Name="D06" Style="{StaticResource Opt}" GroupName="d"><StackPanel><TextBlock FontWeight="SemiBold" Text="Very dense"/><TextBlock Style="{StaticResource Small}" Text="about 2.8x trees"/></StackPanel></RadioButton>
              <RadioButton x:Name="DOwn" Style="{StaticResource Opt}" GroupName="d" Margin="0"><StackPanel><TextBlock FontWeight="SemiBold" Text="Own value"/><TextBox x:Name="DVal" Width="52" HorizontalAlignment="Left" Margin="0,2,0,0" Text="0.65"/></StackPanel></RadioButton>
            </UniformGrid>
            <TextBlock x:Name="DHint" Style="{StaticResource Small}" Margin="0,5,0,0" Text="More trees = more GPU load. &#x2605; = recommended"/>
          </StackPanel></Border>
          <Border Style="{StaticResource Group}"><StackPanel>
            <TextBlock Style="{StaticResource H3}" Text="Tree height"/>
            <UniformGrid Columns="5">
              <RadioButton x:Name="H10" Style="{StaticResource Opt}" GroupName="h"><StackPanel><TextBlock FontWeight="SemiBold" Text="Original"/><TextBlock Style="{StaticResource Small}" Text="as in X-Plane"/></StackPanel></RadioButton>
              <RadioButton x:Name="H08" Style="{StaticResource Opt}" GroupName="h"><StackPanel><TextBlock FontWeight="SemiBold" Text="Slightly smaller"/><TextBlock Style="{StaticResource Small}" Text="20 % smaller"/></StackPanel></RadioButton>
              <RadioButton x:Name="H07" Style="{StaticResource Opt}" GroupName="h"><StackPanel><StackPanel Orientation="Horizontal"><TextBlock FontWeight="SemiBold" Text="Smaller"/><Border Style="{StaticResource Star}"><TextBlock Foreground="White" FontSize="10.5" Text="&#x2605;"/></Border></StackPanel><TextBlock Style="{StaticResource Small}" Text="30 % smaller"/></StackPanel></RadioButton>
              <RadioButton x:Name="H06" Style="{StaticResource Opt}" GroupName="h"><StackPanel><TextBlock FontWeight="SemiBold" Text="Much smaller"/><TextBlock Style="{StaticResource Small}" Text="40 % smaller"/></StackPanel></RadioButton>
              <RadioButton x:Name="HOwn" Style="{StaticResource Opt}" GroupName="h" Margin="0"><StackPanel><TextBlock FontWeight="SemiBold" Text="Own value"/><TextBox x:Name="HVal" Width="52" HorizontalAlignment="Left" Margin="0,2,0,0" Text="0.75"/></StackPanel></RadioButton>
            </UniformGrid>
          </StackPanel></Border>
          <Border x:Name="GrpHedge" Style="{StaticResource Group}"><StackPanel>
            <StackPanel Orientation="Horizontal"><TextBlock Style="{StaticResource H3}" Text="Hedges"/>
              <Border x:Name="ShPill" Background="{DynamicResource Acc2}" CornerRadius="9" Padding="8,1" Margin="8,0,0,6" VerticalAlignment="Center">
                <TextBlock x:Name="ShText" Foreground="{DynamicResource Acc}" FontSize="12" FontWeight="SemiBold"/></Border></StackPanel>
            <UniformGrid Columns="3">
              <RadioButton x:Name="G0" Style="{StaticResource Opt}" GroupName="g"><StackPanel><TextBlock FontWeight="SemiBold" Text="Original"/><TextBlock x:Name="G0Txt" Style="{StaticResource Small}" Text="As simHeaven draws them"/></StackPanel></RadioButton>
              <RadioButton x:Name="G1" Style="{StaticResource Opt}" GroupName="g"><StackPanel><TextBlock FontWeight="SemiBold" Text="Green hedges"/><TextBlock Style="{StaticResource Small}" Text="4-5 m, all four seasons, visible up to 8 km"/></StackPanel></RadioButton>
              <RadioButton x:Name="G2" Style="{StaticResource Opt}" GroupName="g" Margin="0"><StackPanel><StackPanel Orientation="Horizontal"><TextBlock FontWeight="SemiBold" Text="+ Hedgebanks"/><Border Style="{StaticResource Star}"><TextBlock Foreground="White" FontSize="10.5" Text="&#x2605;"/></Border></StackPanel><TextBlock Style="{StaticResource Small}" Text="Green hedges, plus Knick look in northern Germany and Denmark: mixed bushes with single tall trees"/></StackPanel></RadioButton>
            </UniformGrid>
            <WrapPanel x:Name="CtyPanel" Margin="0,7,0,0"><TextBlock Style="{StaticResource Small}" Text="Pro countries:" Margin="0,0,10,0" VerticalAlignment="Center"/></WrapPanel>
          </StackPanel></Border>
        </StackPanel>
        <DockPanel DockPanel.Dock="Bottom" VerticalAlignment="Bottom" LastChildFill="False">
          <Button x:Name="BtSetApply" DockPanel.Dock="Right" Style="{StaticResource Pri}" Content="Apply"/>
          <TextBlock x:Name="RunSet" DockPanel.Dock="Left" VerticalAlignment="Center" Foreground="{DynamicResource WarnTxt}" FontSize="12.5" Text="&#x26A0; Quit X-Plane first   " Visibility="Collapsed"/>
          <TextBlock x:Name="Preview" DockPanel.Dock="Left" VerticalAlignment="Center" Style="{StaticResource Small}" FontSize="12.5"/>
        </DockPanel>
      </DockPanel>

      <!-- status -->
      <DockPanel x:Name="PgSta" Visibility="Collapsed">
        <TextBlock DockPanel.Dock="Top" Style="{StaticResource H2}" Text="Status"/>
        <DockPanel DockPanel.Dock="Bottom" LastChildFill="False" Margin="0,8,0,0">
          <Button x:Name="BtStaUpd" DockPanel.Dock="Right" Content="Check for update"/>
          <Button x:Name="BtStaXp" DockPanel.Dock="Right" Content="Open X-Plane folder"/>
          <Button x:Name="BtStaLog" DockPanel.Dock="Right" Content="Open tool.log"/>
          <Button x:Name="BtStaRef" DockPanel.Dock="Left" Content="Refresh" Margin="0"/>
        </DockPanel>
        <Border Style="{StaticResource Group}" Margin="0"><ScrollViewer VerticalScrollBarVisibility="Auto">
          <Grid x:Name="StaGrid"><Grid.ColumnDefinitions><ColumnDefinition Width="170"/><ColumnDefinition/></Grid.ColumnDefinitions></Grid></ScrollViewer></Border>
      </DockPanel>

      <!-- simple action pages: check & repair, quick switch, restore -->
      <DockPanel x:Name="PgAct" Visibility="Collapsed">
        <TextBlock x:Name="ActTitle" DockPanel.Dock="Top" Style="{StaticResource H2}"/>
        <DockPanel DockPanel.Dock="Bottom" VerticalAlignment="Bottom" LastChildFill="False">
          <Button x:Name="BtAct" DockPanel.Dock="Right" Style="{StaticResource Pri}"/>
          <TextBlock x:Name="RunAct" DockPanel.Dock="Left" VerticalAlignment="Center" Foreground="{DynamicResource WarnTxt}" FontSize="12.5" Text="&#x26A0; Quit X-Plane first" Visibility="Collapsed"/>
        </DockPanel>
        <StackPanel DockPanel.Dock="Top"><Border Style="{StaticResource Group}"><StackPanel>
          <TextBlock x:Name="ActText"/><TextBlock x:Name="ActState" Margin="0,8,0,0" FontWeight="SemiBold"/></StackPanel></Border></StackPanel>
      </DockPanel>

      <!-- log / help -->
      <DockPanel x:Name="PgLog" Visibility="Collapsed">
        <TextBlock DockPanel.Dock="Top" Style="{StaticResource H2}" Text="Log / help"/>
        <DockPanel DockPanel.Dock="Bottom" LastChildFill="False" Margin="0,8,0,0">
          <Button x:Name="BtLogGh" DockPanel.Dock="Right" Content="GitHub page"/>
          <Button x:Name="BtLogRd" DockPanel.Dock="Right" Content="README"/>
          <Button x:Name="BtLogTool" DockPanel.Dock="Right" Content="Open tool.log"/>
          <Button x:Name="BtLogCon" DockPanel.Dock="Left" Content="Console version" Margin="0"/>
        </DockPanel>
        <TextBox x:Name="LogBox" Style="{StaticResource Log}"/>
      </DockPanel>

      <!-- running -->
      <DockPanel x:Name="PgBusy" Visibility="Collapsed">
        <StackPanel DockPanel.Dock="Top">
          <TextBlock x:Name="BusyTitle" Style="{StaticResource H2}"/>
          <TextBlock x:Name="BusyStatus"/>
          <ProgressBar x:Name="BusyBar" Height="8" Margin="0,8" Foreground="{DynamicResource Acc}" Background="{DynamicResource Line}" BorderThickness="0"/>
          <TextBlock x:Name="BusyHint" Style="{StaticResource Small}" Margin="0,0,0,10"/>
        </StackPanel>
        <DockPanel DockPanel.Dock="Bottom" LastChildFill="False" Margin="0,10,0,0">
          <Button x:Name="BtBusyBack" DockPanel.Dock="Right" Style="{StaticResource Pri}" Content="Close" Visibility="Collapsed"/>
          <Button x:Name="BtBusyCancel" DockPanel.Dock="Right" Content="Cancel" IsEnabled="False"/>
          <TextBlock x:Name="BusyDone" DockPanel.Dock="Left" VerticalAlignment="Center" FontWeight="SemiBold"/>
        </DockPanel>
        <TextBox x:Name="BusyLog" Style="{StaticResource Log}"/>
      </DockPanel>

      <!-- update -->
      <DockPanel x:Name="PgUpd" Visibility="Collapsed">
        <StackPanel DockPanel.Dock="Top">
          <TextBlock x:Name="UpdTitle" Style="{StaticResource H2}"/>
          <Border Style="{StaticResource Group}"><StackPanel>
            <Grid x:Name="UpdGrid"><Grid.ColumnDefinitions><ColumnDefinition Width="110"/><ColumnDefinition/></Grid.ColumnDefinitions>
              <Grid.RowDefinitions><RowDefinition/><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
              <TextBlock x:Name="U1a" Text="... Download"/><TextBlock x:Name="U1b" Grid.Column="1" FontWeight="SemiBold"/>
              <TextBlock x:Name="U2a" Grid.Row="1" Text="... Check"/><TextBlock x:Name="U2b" Grid.Row="1" Grid.Column="1" FontWeight="SemiBold"/>
              <TextBlock x:Name="U3a" Grid.Row="2" Text="... Install"/><TextBlock x:Name="U3b" Grid.Row="2" Grid.Column="1" FontWeight="SemiBold"/></Grid>
            <ProgressBar x:Name="UpdBar" Height="8" Margin="0,8" Foreground="{DynamicResource Acc}" Background="{DynamicResource Line}" BorderThickness="0" Maximum="100"/>
            <TextBlock Style="{StaticResource Small}" Text="Your settings and backups are kept. X-Plane is not changed by the update."/></StackPanel></Border>
          <Border Style="{StaticResource Group}"><StackPanel>
            <TextBlock x:Name="UpdNewT" Style="{StaticResource H3}"/>
            <TextBlock x:Name="UpdNew" FontSize="12.5" MaxHeight="150"/></StackPanel></Border>
          <Border x:Name="UpdErr" Style="{StaticResource Banner}" Visibility="Collapsed"><DockPanel>
            <Button x:Name="BtUpdPage" DockPanel.Dock="Right" Content="Open the download page"/>
            <TextBlock x:Name="UpdErrT" VerticalAlignment="Center"/></DockPanel></Border>
        </StackPanel>
        <DockPanel DockPanel.Dock="Bottom" VerticalAlignment="Bottom" LastChildFill="False">
          <Button x:Name="BtUpdCancel" DockPanel.Dock="Right" Content="Cancel"/>
        </DockPanel>
      </DockPanel>
    </Grid>
  </Grid>
</Window>
'@

$AskXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="XP12 Forest Tweak" Width="620" SizeToContent="Height" ResizeMode="NoResize" WindowStartupLocation="CenterOwner"
        FontFamily="Segoe UI" FontSize="13.5" ShowInTaskbar="False">
  <StackPanel Margin="18,14">
    <TextBox x:Name="Ctx" FontFamily="Consolas" FontSize="12" IsReadOnly="True" BorderThickness="0" Padding="8" MaxHeight="300"
             VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" Margin="0,0,0,12"/>
    <TextBlock x:Name="Q" TextWrapping="Wrap" FontWeight="SemiBold" Margin="0,0,0,10"/>
    <TextBox x:Name="In" Visibility="Collapsed" Margin="0,0,0,10" Padding="3,2"/>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
      <Button x:Name="No" Content="No" MinWidth="90" Padding="14,4" Margin="0,0,8,0" IsCancel="True"/>
      <Button x:Name="Yes" Content="Yes" MinWidth="90" Padding="14,4" IsDefault="True"/>
    </StackPanel>
  </StackPanel>
</Window>
'@

try { $W = [Windows.Markup.XamlReader]::Parse($Xaml) } catch { Show-Fatal "The window could not be built: $($_.Exception.Message)"; exit 1 }
$U = @{}
foreach ($n in ([regex]::Matches($Xaml, 'x:Name="(\w+)"') | ForEach-Object { $_.Groups[1].Value })) { $U[$n] = $W.FindName($n) }
$U.VerText.Text = "Version $GuiVersion"
$Ico = Join-Path $Here 'forest.ico'
if (Test-Path -LiteralPath $Ico) { try { $W.Icon = [Windows.Media.Imaging.BitmapFrame]::Create((New-Object Uri $Ico)) } catch { } }

# ---------------------------------------------------------------- light / dark (follows the Windows setting)
function Test-DarkMode {
    try { return ((Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme -ErrorAction Stop).AppsUseLightTheme -eq 0) } catch { return $false }
}
$Dark = Test-DarkMode
if ($Dark) {
    $pal = @{ Panel = '#2B2B2B'; Nav = '#252525'; Line = '#3D3D3D'; Txt = '#F0F0F0'; Mut = '#A8A8A8'; Acc = '#6CC070'; Acc2 = '#2F3D2F'; Blue = '#3A86D4'
              Bd = '#5A5A5A'; Btn = '#373737'; WarnBg = '#3F3220'; WarnBd = '#7A5A2A'; InfoBg = '#1F3040'; InfoBd = '#3D6A94'; WarnTxt = '#E0A040'
              LogBg = '#1B1B1B'; LogTxt = '#D0D0D0'; BoxBg = '#1F1F1F' }
    foreach ($k in @($pal.Keys)) {
        $col = [Windows.Media.Color][Windows.Media.ColorConverter]::ConvertFromString($pal[$k])
        $br = [Windows.Media.SolidColorBrush]::new($col); $br.Freeze()
        $W.Resources.Remove($k); $W.Resources.Add($k, $br)
    }
}
function Set-DarkTitle($win) {
    # dark title bar (Windows 10 2004+ / 11), via the FdtWin helper compiled together with the tool
    if (-not $Dark) { return }
    try { if ('FdtWin' -as [type]) { $h = ([Windows.Interop.WindowInteropHelper]::new($win)).Handle; [FdtWin]::DarkTitle($h) } } catch { }
}

# ---------------------------------------------------------------- worker jobs
$script:Job = $null; $script:JobLines = New-Object System.Collections.Generic.List[string]; $script:AskFrom = 0
$script:SessionLog = New-Object System.Text.StringBuilder
$script:State = $null; $script:Busy = $false; $script:LastPage = 'Rec'; $script:PrevVer = $null; $script:ReLater = $false; $script:ManualUpd = $false; $script:Closing = $false; $script:SetupProc = $null

function Clean-Line([string]$t) {
    # console hints that make no sense in the window
    $t = $t -replace '\s*\[Q\] Quit', '' -replace '\s*Type Q and press Enter to close this window\.', ''
    $t = $t -replace 'Check & repair \[4\]', 'Check & repair' -replace 'with \[5\]', 'with Quick switch' -replace '\[5\] (switches|again)', 'Quick switch $1'
    return ($t -replace ' \[[0-9]\](?=[ .,)]|$)', '')
}

function Start-Work([string]$name, [string]$script, $jobArgs, [scriptblock]$done, [switch]$Quiet, [switch]$AutoYes) {
    # one job at a time in the worker runspace; $done gets the result (last output object) or $null
    if ($script:Job) {
        if (-not $script:Job.Quiet -or $script:Job.Name -ne 'plan' -or $Quiet) { return $false }
        try { $script:Job.PS.Stop(); $script:Job.PS.Dispose() } catch { }      # a preview only reads: stop it
        $script:Job = $null; $sync.Mute = $false
        Drain-Log
    }
    $rs.SessionStateProxy.SetVariable('JobArgs', $jobArgs)
    $sync.AutoYes = [bool]$AutoYes; $sync.Prog = $null
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    [void]$ps.AddScript($script)
    $script:Job = @{ Name = $name; PS = $ps; H = $ps.BeginInvoke(); Done = $done; Quiet = [bool]$Quiet }
    if (-not $Quiet) {
        $script:JobLines.Clear(); $script:AskFrom = 0
        $U.BusyTitle.Text = $name; $U.BusyStatus.Text = 'starting ...'; $U.BusyHint.Text = ''; $U.BusyDone.Text = ''
        $U.BusyLog.Text = ''; $U.BusyBar.IsIndeterminate = $true; $U.BtBusyCancel.IsEnabled = $false
        $U.BtBusyCancel.Visibility = 'Visible'; $U.BtBusyBack.Visibility = 'Collapsed'
        Show-Page 'Busy'; Set-NavEnabled $false
    }
    return $true
}

function Complete-Job {
    $j = $script:Job; $ps = $j.PS; $res = $null; $err = $null
    try { $out = $ps.EndInvoke($j.H); if ($out.Count) { $res = $out[$out.Count - 1] } } catch { $err = $_.Exception.InnerException; if (-not $err) { $err = $_.Exception } }
    if (-not $err -and $ps.Streams.Error.Count) { $err = $ps.Streams.Error[0].Exception }
    $stopped = $ps.InvocationStateInfo.State -eq 'Stopped'
    Drain-Log      # last lines still belong to this job
    if ($err -and -not $stopped) { Add-Log "  ERROR: $($err.Message)" }
    $ps.Dispose(); $script:Job = $null; $sync.AutoYes = $false; $sync.Mute = $false; $sync.Prog = $null
    if (-not $j.Quiet) {
        $U.BusyBar.IsIndeterminate = $false; $U.BusyBar.Value = 100; $U.BtBusyCancel.Visibility = 'Collapsed'; $U.BtBusyBack.Visibility = 'Visible'
        $U.BusyStatus.Text = ''
        $bad = $err -or @($script:JobLines | Where-Object { $_ -match '^\s*ERROR:' }).Count
        $U.BusyDone.Text = if ($stopped) { 'Cancelled - it goes on where it stopped next time.' } elseif ($bad) { 'Stopped with an error - see above. Details in tool.log.' } else { 'Done.' }
        $U.BusyHint.Text = ''
        Set-NavEnabled $true
    }
    if ($j.Done) { & $j.Done $res $err }
}

function Add-Log([string]$t) {
    $t = Clean-Line $t
    [void]$script:SessionLog.AppendLine($t)
    if ($script:Job -and -not $script:Job.Quiet) { $script:JobLines.Add($t); $U.BusyLog.AppendText($t + "`r`n"); $U.BusyLog.ScrollToEnd() }
}
function Drain-Log { $t = $null; while ($sync.Log.TryDequeue([ref]$t)) { Add-Log $t } }

# common end of every job that changes something: take the new state
$OnState = { param($res, $err) if ($res -and $res.PSObject.Properties['Version']) { Set-State $res } }

# ---------------------------------------------------------------- pages
$Pages = @{ Lic = 'PgLic'; Load = 'PgLoad'; Rec = 'PgRec'; Set = 'PgSet'; Sta = 'PgSta'; Act = 'PgAct'; Log = 'PgLog'; Busy = 'PgBusy'; Upd = 'PgUpd' }
function Show-Page([string]$p) {
    foreach ($k in $Pages.Keys) { $U[$Pages[$k]].Visibility = $(if ($k -eq $p) { 'Visible' } else { 'Collapsed' }) }
    if ($p -eq 'Log') { $U.LogBox.Text = $script:SessionLog.ToString(); $U.LogBox.ScrollToEnd() }
}
function Set-NavEnabled([bool]$on) { foreach ($n in 'NavRec', 'NavSet', 'NavSta', 'NavChk', 'NavSw', 'NavRes', 'NavLog') { $U[$n].IsEnabled = $on } }

function Fmt2([double]$v) { $v.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture) }
function Get-SpacingName([double]$x) { switch ($x) { 1.0 { 'Original' } 0.8 { 'Natural' } 0.7 { 'Dense' } 0.6 { 'Very dense' } default { "own value $(Fmt2 $x)" } } }
function Get-HeightName([double]$h) { switch ($h) { 1.0 { 'Original' } 0.8 { 'Slightly smaller' } 0.7 { 'Smaller' } 0.6 { 'Much smaller' } default { "own value $(Fmt2 $h)" } } }
$HedgeNames = @{ 'default' = 'Original'; 'enhanced' = 'Green hedges'; 'Knicks' = 'Green hedges + hedgebanks' }

function Add-Row($grid, [string]$k, [string]$v, [bool]$bold = $true) {
    $r = $grid.RowDefinitions.Count; $grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition))
    $a = New-Object Windows.Controls.TextBlock; $a.Text = $k; $a.Margin = '0,1'; [Windows.Controls.Grid]::SetRow($a, $r)
    $b = New-Object Windows.Controls.TextBlock; $b.Text = $v; $b.Margin = '0,1'; $b.TextWrapping = 'Wrap'
    if ($bold) { $b.FontWeight = [Windows.FontWeights]::SemiBold }
    [Windows.Controls.Grid]::SetRow($b, $r); [Windows.Controls.Grid]::SetColumn($b, 1)
    if (-not $k) { [Windows.Controls.Grid]::SetColumn($b, 1) }
    [void]$grid.Children.Add($a); [void]$grid.Children.Add($b)
}
function Clear-Grid($grid) { $grid.Children.Clear(); $grid.RowDefinitions.Clear() }

function Get-NowText($s) {
    if ($s.Off) { return 'Original (switched with Quick switch, your tweak is kept)' }
    $f = if ($s.N) { "$(Get-SpacingName $s.X) $Dot $(Get-HeightName $s.H)" } else { 'Forests original' }
    if ($s.HasSh) { $f += " $Dot hedges: $($HedgeNames[$s.Hedges])" }
    return $f
}

function Set-State($s) {
    $script:State = $s
    if ($null -eq $script:PrevVer) { $script:PrevVer = [string](Get-GuiCfg).last }
    $U.VerText.Text = "Version $($s.Version)"
    # recommended page
    Clear-Grid $U.RecGrid
    Add-Row $U.RecGrid 'Tree spacing' 'Dense (about 2x trees)'
    Add-Row $U.RecGrid 'Tree height' 'Smaller (30 %)'
    Add-Row $U.RecGrid 'Hedges' $(if ($s.HasSh) { 'Green hedges + hedgebanks' } else { '- (simHeaven X-World not found)' })
    if ($s.Pro.Count -and $s.ProCountries.Count) { Add-Row $U.RecGrid 'Pro countries' ((@($s.ProCountries | ForEach-Object { $_.Name })) -join ', ') }
    if ($s.GF.Count) { Add-Row $U.RecGrid 'Global Forests v2' $(if ($s.UseGF) { 'included' } else { 'not included (Settings)' }) }
    $U.RecNow.Text = Get-NowText $s
    $notes = @()
    if ($null -ne $s.Veg -and $s.Veg -lt 4) { $notes += 'The vegetation slider in X-Plane is not at maximum - set it to maximum (Settings > Graphics) for the full effect.' }
    if ($s.XPVer -and $s.TestedXP -and -not $s.XPVer.StartsWith($s.TestedXP)) { $notes += "Tested with X-Plane $($s.TestedXP).x, you have $($s.XPVer)." }
    if ($s.Both.Count) { $notes += "Free X-World and X-WORLD Pro are both on for $($s.Both -join ', ') - Apply offers to turn the free packs off." }
    $U.RecNote.Text = $notes -join "`n"; $U.RecNote.Visibility = $(if ($notes.Count) { 'Visible' } else { 'Collapsed' })
    # banners
    $re = (-not $s.Off) -and (($s.N -and $s.NOld) -or $s.OverlayOld) -and -not $script:ReLater
    $U.BnRe.Visibility = $(if ($re) { 'Visible' } else { 'Collapsed' })
    $U.TxRe.Text = $(if ($script:PrevVer -and $script:PrevVer -ne $s.Version) { "Updated to $($s.Version). Put your forest settings back now?" } else { 'Made with an older version. Apply your settings again for the latest improvements?' })
    $U.BnReset.Visibility = $(if (-not $s.Off -and $s.N -and $s.NReset) { 'Visible' } else { 'Collapsed' })
    $U.TxReset.Text = "An update reset $($s.NReset) forest files - they are original again."
    $U.BnHint.Visibility = $(if ($s.Hint -and -not $re) { 'Visible' } else { 'Collapsed' })
    $U.TxHint.Text = "Hedges: $($s.Hint -replace ' - run Check & repair.*$', '')"
    $U.BnOff.Visibility = $(if ($s.Off) { 'Visible' } else { 'Collapsed' })
    # settings page: current values (or the recommended ones the first time)
    Set-SettingsFrom $s
    # status page
    Clear-Grid $U.StaGrid
    Add-Row $U.StaGrid 'X-Plane' ("$($s.XP)" + $(if ($s.XPVer) { "  ($($s.XPVer))" } else { '' }))
    foreach ($l in $s.Status) {
        $l = Clean-Line $l
        if (-not $l.Trim()) { continue }
        if ($l -match '^\s{2}(\S.{0,21}?)\s*:\s(.*)$') { Add-Row $U.StaGrid $Matches[1].Trim() $Matches[2].Trim() }
        else { Add-Row $U.StaGrid '' $l.Trim() $false }
    }
    Save-GuiCfg @{ last = $s.Version }
    Update-ActionPage
    Update-Running
    Request-Plan
    Request-RecPlan
}

# ---------------------------------------------------------------- settings page
$script:Loading = $false
$CountryBoxes = @{}
function Set-SettingsFrom($s) {
    $script:Loading = $true
    $x = if ($s.N) { [double]$s.X } else { 0.7 }; $h = if ($s.N) { [double]$s.H } else { 0.7 }
    $dm = @{ 1.0 = 'D10'; 0.8 = 'D08'; 0.7 = 'D07'; 0.6 = 'D06' }; $hm = @{ 1.0 = 'H10'; 0.8 = 'H08'; 0.7 = 'H07'; 0.6 = 'H06' }
    if ($dm.ContainsKey($x)) { $U[$dm[$x]].IsChecked = $true } else { $U.DOwn.IsChecked = $true; $U.DVal.Text = Fmt2 $x }
    if ($hm.ContainsKey($h)) { $U[$hm[$h]].IsChecked = $true } else { $U.HOwn.IsChecked = $true; $U.HVal.Text = Fmt2 $h }
    $U.CbGf.Visibility = $(if ($s.GF.Count) { 'Visible' } else { 'Collapsed' }); $U.CbGf.IsChecked = [bool]$s.UseGF
    $U.GrpHedge.IsEnabled = $s.HasSh
    # hedges: the current choice; recommended only if nothing was applied yet
    $hc = if ($s.HasSh -and ($s.KnicksOn -or $s.Hedges -ne 'default' -or $s.N)) { $s.Hedges } elseif ($s.HasSh) { 'Knicks' } else { 'default' }
    switch ($hc) { 'enhanced' { $U.G1.IsChecked = $true } 'Knicks' { $U.G2.IsChecked = $true } default { $U.G0.IsChecked = $true } }
    if ($s.Pro.Count) { $U.ShText.Text = 'simHeaven X-WORLD Pro found'; $U.G0Txt.Text = 'As simHeaven draws them (Pro: flat walls, no seasons)' }
    elseif ($s.Free.Count -or $s.HedgeFiles) { $U.ShText.Text = 'simHeaven X-World found'; $U.G0Txt.Text = 'As simHeaven draws them (2-3 m)' }
    else { $U.ShText.Text = 'simHeaven X-World not found'; $U.G0Txt.Text = 'As simHeaven draws them' }
    # countries (only those with X-WORLD Pro tiles on this computer)
    $p = $U.CtyPanel; while ($p.Children.Count -gt 1) { $p.Children.RemoveAt(1) }
    $CountryBoxes.Clear()
    $cur = @($s.Countries); if (-not $cur.Count) { $cur = @($s.ProCountries | ForEach-Object { $_.Key }) }
    foreach ($c in $s.ProCountries) {
        $cb = New-Object Windows.Controls.CheckBox; $cb.Content = $c.Name; $cb.ToolTip = "$($c.Tiles) X-WORLD Pro tiles"; $cb.IsChecked = ($cur -contains $c.Key -or $cur -contains 'all')
        $cb.Add_Click({ Request-Plan }); [void]$p.Children.Add($cb); $CountryBoxes[$c.Key] = $cb
    }
    if ($s.ProCountries.Count) {
        $cb = New-Object Windows.Controls.CheckBox; $cb.Content = 'All'; $cb.ToolTip = "all $($s.ProAll) X-WORLD Pro tiles on this computer"; $cb.IsChecked = ($cur -contains 'all')
        $cb.Add_Click({ Request-Plan }); [void]$p.Children.Add($cb); $CountryBoxes['all'] = $cb
    }
    $p.Visibility = $(if ($s.Pro.Count -and $s.ProCountries.Count) { 'Visible' } else { 'Collapsed' })
    $script:Loading = $false
    Update-CountryVis
}

function Update-CountryVis { $U.CtyPanel.IsEnabled = -not $U.G0.IsChecked }

function Parse-Own([string]$a, [double]$min) {
    $s = $a.Trim().Replace(',', '.').TrimEnd('%').Trim(); $v = 0.0
    if (-not [double]::TryParse($s, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$v)) { return $null }
    if ($v -gt 1.0 -and $v -le 100.0) { $v = $v / 100.0 }
    $v = [Math]::Round($v, 3, [MidpointRounding]::AwayFromZero)
    if ($v -ge $min -and $v -le 1.0) { return $v }
    return $null
}

function Get-Chosen {
    # settings of the page as @{ Fac; H; Hedges; Countries; UseGf } or a string with what is wrong
    $s = $script:State
    $fac = if ($U.D10.IsChecked) { 1.0 } elseif ($U.D08.IsChecked) { 0.8 } elseif ($U.D07.IsChecked) { 0.7 } elseif ($U.D06.IsChecked) { 0.6 } else { Parse-Own $U.DVal.Text $s.MinFac }
    if ($null -eq $fac) { return "Tree spacing: type a value from $(Fmt2 $s.MinFac) to 1.0, e.g. 0.65" }
    $h = if ($U.H10.IsChecked) { 1.0 } elseif ($U.H08.IsChecked) { 0.8 } elseif ($U.H07.IsChecked) { 0.7 } elseif ($U.H06.IsChecked) { 0.6 } else { Parse-Own $U.HVal.Text $s.MinHeight }
    if ($null -eq $h) { return "Tree height: type a value from $(Fmt2 $s.MinHeight) to 1.0, e.g. 0.75" }
    $g = if (-not $s.HasSh) { 'default' } elseif ($U.G1.IsChecked) { 'enhanced' } elseif ($U.G2.IsChecked) { 'Knicks' } else { 'default' }
    $c = @()
    if ($CountryBoxes.ContainsKey('all') -and $CountryBoxes['all'].IsChecked) { $c = @('all') }
    else { foreach ($k in $CountryBoxes.Keys) { if ($k -ne 'all' -and $CountryBoxes[$k].IsChecked) { $c += $k } } }
    return @{ Fac = [double]$fac; H = [double]$h; Hedges = $g; Countries = @($c); UseGf = [bool]$U.CbGf.IsChecked }
}

# live preview: worked out by the tool itself (same numbers as its summary), a moment after the last change
$script:PlanDue = $null; $script:RecPlanDue = $false
function Request-Plan { if (-not $script:Loading) { $script:PlanDue = [DateTime]::Now.AddMilliseconds(400); Update-CountryVis } }
function Request-RecPlan { $script:RecPlanDue = $true }
$PlanScript = @'
$sync.Mute = $true
try {
    Set-GuiTargets $JobArgs.UseGf
    $p = Invoke-ChooseSettings $xp $targets -PlanOnly -Quick:$JobArgs.Quick -Preset $JobArgs.Preset
    if ($p) { $p | Add-Member -NotePropertyName TimeText -NotePropertyValue (Format-TimeRange $p.Sec) -PassThru | Add-Member -NotePropertyName SizeText -NotePropertyValue $(if ($p.Bytes -ge 1GB) { '{0:N1} GB' -f ($p.Bytes / 1GB) } else { '{0:N0} MB' -f [Math]::Max(1, $p.Bytes / 1MB) }) -PassThru }
} finally { $sync.Mute = $false }
'@
function Format-Plan($p) {
    if (-not $p) { return '' }
    if ($p.Nothing) { return 'Nothing to change - these settings are active.' }
    $a = @()
    if ($p.Forest) { $a += "$($p.Files) forest files" }
    if ($p.Hedge -and $p.Tiles) { $a += $(if ($p.NewTiles) { "$($p.NewTiles) hedge tiles to build" } else { 'hedge library' }) }
    elseif ($p.Hedge) { $a += 'hedges' }
    return "Will change: $($a -join " $Dot ") $Dot $($p.TimeText) $Dot up to $($p.SizeText)"
}

# ---------------------------------------------------------------- action pages
$script:ActKind = ''
function Update-ActionPage {
    $s = $script:State; if (-not $s) { return }
    switch ($script:ActKind) {
        'chk' { $U.ActTitle.Text = 'Check & repair'; $U.BtAct.Content = 'Run check'
                $U.ActText.Text = "Checks the backups and the log, removes leftovers and temp files, and finishes or updates the hedge tiles (after an interrupted build or a simHeaven update).`n`nRun it when something looks wrong, or after updating simHeaven."
                $U.ActState.Text = $(if ($s.Hint) { "Hedges: $($s.Hint -replace ' - run Check & repair.*$', '')" } else { '' }) }
        'sw'  { $U.ActTitle.Text = 'Quick switch'
                $U.ActText.Text = "Switches X-Plane between your tweak and the original forests and hedges in a few seconds, without losing your tweak - for example to compare, or to fly a scenery that should not be changed."
                if ($s.Off) { $U.BtAct.Content = 'Switch back to tweak'; $U.ActState.Text = 'Now: original (your tweak is kept)' }
                else { $U.BtAct.Content = 'Switch to original'; $U.ActState.Text = "Now: $(Get-NowText $s)" } }
        'res' { $U.ActTitle.Text = 'Restore original'; $U.BtAct.Content = 'Restore original'
                $U.ActText.Text = "Puts back the exact original forest files and hedges and removes the tweak folders from Custom Scenery. Your settings are not kept - to compare only, use Quick switch."
                $U.ActState.Text = "Now: $(Get-NowText $s)" }
    }
    if ($script:ActKind -eq 'sw') { $U.BtAct.IsEnabled = -not $script:XpRunning -and ($s.Off -or $s.N -or $s.KnicksOn) } else { $U.BtAct.IsEnabled = -not $script:XpRunning }
}

# ---------------------------------------------------------------- X-Plane running
$script:XpRunning = $false
function Update-Running {
    $script:XpRunning = [bool](Get-Process -Name 'X-Plane' -ErrorAction SilentlyContinue)
    $v = if ($script:XpRunning) { 'Visible' } else { 'Collapsed' }
    $U.RunRec.Visibility = $v; $U.RunSet.Visibility = $v; $U.RunAct.Visibility = $v
    $ok = -not $script:XpRunning -and $null -ne $script:State
    foreach ($b in 'BtRecApply', 'BtSetApply', 'BtReApply', 'BtReset', 'BtHint', 'BtOffBack') { $U[$b].IsEnabled = $ok }
    Update-ActionPage
}

# ---------------------------------------------------------------- settings file of the window (in ForestDensityTweak)
function Get-GuiCfgPath { if ($script:State) { Join-Path $script:State.TweakDir 'window.json' } else { $null } }
function Get-GuiCfg {
    $p = Get-GuiCfgPath
    try { if ($p -and (Test-Path -LiteralPath $p)) { return (Get-Content -LiteralPath $p -Raw | ConvertFrom-Json) } } catch { }
    return [pscustomobject]@{}
}
function Save-GuiCfg([hashtable]$set) {
    $p = Get-GuiCfgPath; if (-not $p) { return }
    try {
        $c = @{}; $o = Get-GuiCfg; foreach ($pr in $o.PSObject.Properties) { $c[$pr.Name] = $pr.Value }
        foreach ($k in $set.Keys) { $c[$k] = $set[$k] }
        if (-not (Test-Path -LiteralPath (Split-Path -Parent $p))) { return }
        [IO.File]::WriteAllText($p, ($c | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding($false)))
    } catch { }
}

# ---------------------------------------------------------------- update
function Get-VT([string]$s) { $n = @([regex]::Matches($s, '\d+') | Select-Object -First 3 | ForEach-Object { [int]$_.Value }); while ($n.Count -lt 3) { $n += 0 }; ($n[0] * 1000000 + $n[1] * 1000 + $n[2]) }
$script:Rel = $null; $script:UpdTask = $null
$Installed = Test-Path -LiteralPath (Join-Path $Here 'installed_by_setup.txt')
function Start-UpdCheck {
    try {
        Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $c = New-Object Net.Http.HttpClient; $c.Timeout = [TimeSpan]::FromSeconds(8)
        $c.DefaultRequestHeaders.Add('User-Agent', 'xp12-forest-tweak')
        $script:UpdTask = $c.GetStringAsync("https://api.github.com/repos/$Repo/releases/latest")
    } catch { $script:UpdTask = $null }
}
function Test-UpdDone([bool]$manual) {
    $t = $script:UpdTask; if (-not $t -or -not $t.IsCompleted) { return }
    $script:UpdTask = $null
    if ($t.IsFaulted -or $t.IsCanceled) { if ($manual) { Show-Ask 'Could not reach GitHub - please try again later.' -Ok | Out-Null }; return }
    try { $r = $t.Result | ConvertFrom-Json } catch { return }
    $tag = [string]$r.tag_name
    if (-not $tag -or (Get-VT $tag) -le (Get-VT $GuiVersion)) { if ($manual) { Show-Ask "You have the latest version ($GuiVersion)." -Ok | Out-Null }; return }
    $script:Rel = $r
    $v = $tag.TrimStart('v', 'V')
    if (-not $manual -and [string](Get-GuiCfg).skip -eq $v) { return }
    $U.TxUpd.Text = "Forest Tweak $v is available."
    $U.BnUpd.Visibility = 'Visible'
    if ($manual) { Show-Page 'Rec'; $U.NavRec.IsChecked = $true }
}

$sync2 = [hashtable]::Synchronized(@{ Step = 0; Pct = 0; Text = ''; Err = $null; Done = $false; File = '' })
$script:UpdPS = $null
$UpdScript = @'
param($url, $file, $size)
try {
    Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $c = New-Object Net.Http.HttpClient; $c.Timeout = [TimeSpan]::FromMinutes(10)
    $c.DefaultRequestHeaders.Add('User-Agent', 'xp12-forest-tweak')
    $resp = $c.GetAsync($url, [Net.Http.HttpCompletionOption]::ResponseHeadersRead).Result
    if (-not $resp.IsSuccessStatusCode) { throw "download failed ($([int]$resp.StatusCode))" }
    $in = $resp.Content.ReadAsStreamAsync().Result
    $out = [IO.File]::Create($file)
    try {
        $buf = New-Object byte[] 262144; $got = [long]0
        while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
            $out.Write($buf, 0, $n); $got += $n
            if ($size -gt 0) { $sync2.Pct = [int](100 * $got / $size) }
            if ($sync2.Cancel) { throw 'cancelled' }
        }
    } finally { $out.Close(); $in.Close() }
    $sync2.Done = $true
} catch { $sync2.Err = $_.Exception.Message }
'@

function Start-Update {
    $r = $script:Rel; if (-not $r) { return }
    $v = ([string]$r.tag_name).TrimStart('v', 'V')
    $want = if ($Installed) { '*_Setup.exe' } else { '*_Windows.zip' }
    $asset = @($r.assets | Where-Object { $_.name -like $want }) | Select-Object -First 1
    $U.UpdTitle.Text = "Updating to $v"; $U.UpdErr.Visibility = 'Collapsed'; $U.UpdBar.Value = 0
    $U.U1a.Text = '... Download'; $U.U2a.Text = '... Check'; $U.U3a.Text = '... Install'
    $U.U2b.Text = ''; $U.U3b.Text = $(if ($Installed) { 'runs the new setup, then starts again' } else { 'replaces the files of the tool, then starts again' })
    $U.UpdNewT.Text = "What's new in $v"
    $body = (([string]$r.body) -split "`r?`n" | Where-Object { $_ -match '^\s*[-*] ' } | Select-Object -First 7 | ForEach-Object { ($Bul + '  ') + (($_ -replace '^\s*[-*]\s+', '') -replace '\*\*|`|\[([^\]]+)\]\([^)]+\)', '$1') }) -join "`n"
    $U.UpdNew.Text = $(if ($body) { $body } else { 'See the changelog on GitHub.' })
    $U.BtUpdCancel.IsEnabled = $true; $U.BtUpdCancel.Content = 'Cancel'
    Show-Page 'Upd'; Set-NavEnabled $false
    if (-not $asset -or -not ([string]$asset.digest).StartsWith('sha256:')) { Fail-Update 'This release has no file with a checksum for in-app updates.'; return }
    $script:UpdAsset = $asset
    $U.U1b.Text = "$($asset.name) $Dot {0:N1} MB" -f ($asset.size / 1MB)
    $dir = Join-Path ([IO.Path]::GetTempPath()) ('xp12ft_update_' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
    [void](New-Item -ItemType Directory -Path $dir)
    $sync2.Pct = 0; $sync2.Err = $null; $sync2.Done = $false; $sync2.Cancel = $false; $sync2.File = Join-Path $dir $asset.name
    $ps = [powershell]::Create(); $ps.Runspace = [runspacefactory]::CreateRunspace(); $ps.Runspace.Open()
    $ps.Runspace.SessionStateProxy.SetVariable('sync2', $sync2)
    [void]$ps.AddScript($UpdScript).AddArgument($asset.browser_download_url).AddArgument($sync2.File).AddArgument([long]$asset.size)
    $script:UpdPS = @{ PS = $ps; H = $ps.BeginInvoke() }
}
function Fail-Update([string]$msg) {
    $U.UpdErr.Visibility = 'Visible'
    $U.UpdErrT.Text = "$([char]0x26A0) $msg"
    $U.BtUpdCancel.Content = 'OK'; $U.BtUpdCancel.IsEnabled = $true
    try { if ($script:State) { Add-Log "  Update: $msg" } } catch { }
}
function Test-UpdProgress {
    $j = $script:UpdPS; if (-not $j) { return }
    $U.UpdBar.Value = $sync2.Pct
    if (-not $j.H.IsCompleted) { return }
    try { $j.PS.EndInvoke($j.H) | Out-Null } catch { }
    $j.PS.Runspace.Close(); $j.PS.Dispose(); $script:UpdPS = $null
    if ($sync2.Err) { if ($sync2.Err -ne 'cancelled') { Fail-Update "The download did not work ($($sync2.Err))." } else { Show-Page 'Rec'; Set-NavEnabled $true }; return }
    $U.U1a.Text = "$([char]0x2713) Download"
    $hash = (Get-FileHash -LiteralPath $sync2.File -Algorithm SHA256).Hash.ToLower()
    if ('sha256:' + $hash -ne ([string]$script:UpdAsset.digest).ToLower()) {
        Remove-Item -LiteralPath $sync2.File -ErrorAction SilentlyContinue
        $U.U2a.Text = "$([char]0x2717) Check"; $U.U2b.Text = 'SHA-256 does not match GitHub - file deleted, nothing was run'
        Fail-Update 'The downloaded file is not the one published on GitHub.'; return
    }
    $U.U2a.Text = "$([char]0x2713) Check"; $U.U2b.Text = 'SHA-256 matches GitHub'; $U.BtUpdCancel.IsEnabled = $false
    $U.U3a.Text = '... Install'; $W.Dispatcher.Invoke([Action]{ }, [Windows.Threading.DispatcherPriority]::Background)
    if ($Installed) { Install-Setup $sync2.File } else { Install-Zip $sync2.File }
}
function Restart-Window {
    $gui = Join-Path $Here 'XP12_ForestTweak_Gui.ps1'
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Minimized', '-File', "`"$gui`"") -WindowStyle Minimized
    $script:Closing = $true; $W.Close()
}
function Install-Setup([string]$exe) {
    try {
        $p = Start-Process -FilePath $exe -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/NOCANCEL') -PassThru
        $null = $p.Handle      # keeps the handle, so the exit code can be read later
        $script:SetupProc = $p
    } catch { Fail-Update "The setup could not be started ($($_.Exception.Message)). Windows Smart App Control or your antivirus may block it."; return }
}
function Test-SetupDone {
    $p = $script:SetupProc; if (-not $p) { return }
    if (-not $p.HasExited) { return }
    $script:SetupProc = $null
    if ($p.ExitCode -ne 0) { Fail-Update "The setup stopped (code $($p.ExitCode)). Windows Smart App Control or your antivirus may have blocked it."; return }
    $U.U3a.Text = "$([char]0x2713) Install"; Restart-Window
}
function Install-Zip([string]$zip) {
    # replaces only the files of the tool; the old ones are kept in _update_backup until the new ones are in place
    $bk = Join-Path $Here "_update_backup\$GuiVersion"
    $done = New-Object System.Collections.Generic.List[object]
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $tmp = Join-Path (Split-Path -Parent $zip) 'x'
        [IO.Compression.ZipFile]::ExtractToDirectory($zip, $tmp)
        $root = @(Get-ChildItem -LiteralPath $tmp -Directory | Where-Object { $_.Name -like 'XP12_ForestTweak_v*_Windows' }) | Select-Object -First 1
        if (-not $root -or -not (Test-Path -LiteralPath (Join-Path $root.FullName 'XP12_ForestTweak.ps1'))) { throw 'the ZIP does not contain the Windows tool' }
        $base = $root.FullName.TrimEnd('\') + '\'
        $items = @(Get-ChildItem -LiteralPath $root.FullName -Recurse -File | ForEach-Object { @{ Src = $_.FullName; Rel = $_.FullName.Substring($base.Length) } })
        # the in-sim window too, where it is installed
        $lua = if ($script:State) { Join-Path $script:State.XP 'Resources\plugins\FlyWithLua\Scripts\ForestDensityToggle.lua' } else { '' }
        $newLua = Join-Path $root.FullName 'FlyWithLua\ForestDensityToggle.lua'
        foreach ($it in $items) {
            $dst = Join-Path $Here $it.Rel
            Copy-One $it.Src $dst (Join-Path $bk $it.Rel) $done
        }
        if ($lua -and (Test-Path -LiteralPath $lua) -and (Test-Path -LiteralPath $newLua)) { Copy-One $newLua $lua (Join-Path $bk 'FlyWithLua_Scripts\ForestDensityToggle.lua') $done }
        $U.U3a.Text = "$([char]0x2713) Install"
        Restart-Window
    } catch {
        # put the old files back
        for ($i = $done.Count - 1; $i -ge 0; $i--) {
            $d = $done[$i]
            try { if ($d.Bak) { Copy-Item -LiteralPath $d.Bak -Destination $d.Dst -Force } else { Remove-Item -LiteralPath $d.Dst -Force } } catch { }
        }
        Fail-Update "The files could not be replaced ($($_.Exception.Message)) - the old version is kept."
    }
}
function Copy-One([string]$src, [string]$dst, [string]$bak, $done) {
    $hadOld = Test-Path -LiteralPath $dst
    if ($hadOld) { $bd = Split-Path -Parent $bak; if (-not (Test-Path -LiteralPath $bd)) { [void](New-Item -ItemType Directory -Path $bd) }; Copy-Item -LiteralPath $dst -Destination $bak -Force }
    $dd = Split-Path -Parent $dst; if (-not (Test-Path -LiteralPath $dd)) { [void](New-Item -ItemType Directory -Path $dd) }
    Copy-Item -LiteralPath $src -Destination $dst -Force
    $done.Add(@{ Dst = $dst; Bak = $(if ($hadOld) { $bak } else { $null }) })
}

# ---------------------------------------------------------------- questions of the tool -> dialog
function Show-Ask([string]$q, [string]$ctx = '', [switch]$Ok, [switch]$TextAnswer) {
    $d = [Windows.Markup.XamlReader]::Parse($AskXaml); $d.Owner = $W
    foreach ($k in @($W.Resources.Keys)) { $d.Resources[$k] = $W.Resources[$k] }
    $d.Background = $W.Resources['Panel']; $d.Foreground = $W.Resources['Txt']
    $c = $d.FindName('Ctx'); $qt = $d.FindName('Q'); $yes = $d.FindName('Yes'); $no = $d.FindName('No'); $in = $d.FindName('In')
    $c.Background = $W.Resources['LogBg']; $c.Foreground = $W.Resources['LogTxt']
    if ($ctx.Trim()) { $c.Text = $ctx.TrimEnd() } else { $c.Visibility = 'Collapsed' }
    $qt.Text = $q
    $yes.Style = $W.Resources['Pri']
    if ($Ok) { $yes.Content = 'OK'; $no.Visibility = 'Collapsed' }
    $res = @{ V = $null; Input = [bool]$TextAnswer }
    if ($TextAnswer) { $in.Visibility = 'Visible'; $yes.Content = 'OK'; $no.Content = 'Cancel'; $d.Add_ContentRendered({ [void]$in.Focus() }.GetNewClosure()) }
    $yes.Add_Click({ $res.V = $(if ($res.Input) { $in.Text } else { 'y' }); $d.Close() }.GetNewClosure())
    $no.Add_Click({ $res.V = $(if ($res.Input) { '' } else { 'n' }); $d.Close() }.GetNewClosure())
    $dark = $Dark
    $d.Add_SourceInitialized({ if ($dark) { try { if ('FdtWin' -as [type]) { [FdtWin]::DarkTitle(([Windows.Interop.WindowInteropHelper]::new($d)).Handle) } } catch { } } }.GetNewClosure())
    [void]$d.ShowDialog()
    if ($null -eq $res.V) { return $(if ($TextAnswer) { '' } else { 'n' }) }
    return $res.V
}

$script:InAsk = $false
function Test-Ask {
    $p = $sync.Ask
    if ($null -eq $p -or $script:InAsk -or $null -ne $sync.Answer) { return }
    $script:InAsk = $true
    try {
        Drain-Log
        $ctx = (@($script:JobLines | Select-Object -Skip $script:AskFrom) -join "`n").Trim("`n")
        $script:AskFrom = $script:JobLines.Count
        $q = $p.Trim() -replace '\s*\[(Y/n|y/N)\]', ''
        if ($p -match 'Path to your X-Plane') {
            $fb = New-Object System.Windows.Forms.FolderBrowserDialog; $fb.Description = 'Choose your X-Plane 12 folder (contains X-Plane.exe)'
            $a = if ($fb.ShowDialog() -eq 'OK') { $fb.SelectedPath } else { '' }
            if (-not $a) { $script:Closing = $true; $W.Close(); return }
        } elseif ($p -match '\[(Y/n|y/N)\]') { $a = Show-Ask $q $ctx }
        else { $a = Show-Ask $q $ctx -TextAnswer }
        $sync.Answer = [string]$a
    } finally { $script:InAsk = $false }
}

# ---------------------------------------------------------------- jobs of the buttons
$InitScript = @'
$sync.Step = 'loading the tool (Windows prepares its fast C# part)'
. $CorePath
$sync.Step = 'looking for X-Plane 12'
# small window helpers: dark title bar, hide the console window behind the window
if (-not ('FdtWin' -as [type])) { try { Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class FdtWin { [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr h, int a, ref int v, int s); [DllImport("kernel32.dll")] static extern IntPtr GetConsoleWindow(); [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int c); public static void DarkTitle(IntPtr h) { int on = 1; if (DwmSetWindowAttribute(h, 20, ref on, 4) != 0) DwmSetWindowAttribute(h, 19, ref on, 4); } public static void HideConsole() { IntPtr h = GetConsoleWindow(); if (h != IntPtr.Zero) ShowWindow(h, 0); } }' } catch { } }
$global:xp = (Get-Item -LiteralPath (Find-XPlane $XPArg)).FullName.TrimEnd('\', '/')
$script:ToolLog = Join-Path (Get-TweakDir $xp) 'tool.log'
$sync.Step = 'reading the forest files'
$global:gf = @(Find-GFv2 $xp)
$global:useGf = [bool]$gf.Count
$global:targets = @(Get-Targets $xp $gf $global:useGf)
$ver = Get-XPVersion $xp
TLog "start $Version (Windows window, PowerShell $($PSVersionTable.PSVersion)), X-Plane $($ver[1]) at $xp, folders: $((@($targets | ForEach-Object { Rel $xp $_ })) -join ', ')"
foreach ($l in (Get-HmSourceReport $xp)) { TLog "simHeaven: $l" }
$script:StCache = $null
Get-GuiState
'@
function Wrap([string]$body) { "try {`n$body`n} catch { Write-Host `"  ERROR: `$(`$_.Exception.Message)`"; TLog `"ERROR: `$(`$_.Exception.Message)`" }`n`$script:StCache = `$null`nGet-GuiState" }

function Run-Apply([hashtable]$preset, [switch]$Quick) {
    $a = @{ Preset = $preset; Quick = [bool]$Quick; UseGf = $(if ($preset) { $preset.UseGf } else { $script:State.UseGF }) }
    [void](Start-Work $(if ($Quick) { 'Recommended setup' } else { 'Applying your settings' }) (Wrap @'
Set-GuiTargets $JobArgs.UseGf
if ($JobArgs.Quick) { Invoke-ChooseSettings $xp $targets -Quick } else { Invoke-ChooseSettings $xp $targets -Preset $JobArgs.Preset }
'@) $a $OnState)
}

# ---------------------------------------------------------------- events
$U.NavRec.Add_Checked({ Show-Page 'Rec' })
$U.NavSet.Add_Checked({ Show-Page 'Set' })
$U.NavSta.Add_Checked({ Show-Page 'Sta' })
$U.NavChk.Add_Checked({ $script:ActKind = 'chk'; Update-ActionPage; Show-Page 'Act' })
$U.NavSw.Add_Checked({ $script:ActKind = 'sw'; Update-ActionPage; Show-Page 'Act' })
$U.NavRes.Add_Checked({ $script:ActKind = 'res'; Update-ActionPage; Show-Page 'Act' })
$U.NavLog.Add_Checked({ Show-Page 'Log' })

foreach ($n in 'D10', 'D08', 'D07', 'D06', 'DOwn', 'H10', 'H08', 'H07', 'H06', 'HOwn', 'G0', 'G1', 'G2') { $U[$n].Add_Checked({ Request-Plan }) }
$U.DVal.Add_GotFocus({ $U.DOwn.IsChecked = $true }); $U.HVal.Add_GotFocus({ $U.HOwn.IsChecked = $true })
$U.DVal.Add_TextChanged({ Request-Plan }); $U.HVal.Add_TextChanged({ Request-Plan })
$U.CbGf.Add_Click({ Request-Plan; Request-RecPlan })

$U.BtRecCust.Add_Click({ $U.NavSet.IsChecked = $true })
$U.BtRecApply.Add_Click({ Run-Apply $null -Quick })
$U.BtSetApply.Add_Click({
    $c = Get-Chosen
    if ($c -is [string]) { Show-Ask $c -Ok | Out-Null; return }
    Run-Apply $c
})
$U.BtReApply.Add_Click({
    $s = $script:State
    Run-Apply @{ Fac = [double]$s.X; H = [double]$s.H; Hedges = $s.Hedges; Countries = @($s.Countries); UseGf = [bool]$s.UseGF }
})
$U.BtReLater.Add_Click({ $script:ReLater = $true; $U.BnRe.Visibility = 'Collapsed' })
$U.BtReset.Add_Click({ [void](Start-Work 'Tweaking the reset files again' (Wrap 'Invoke-StartOffers $xp $targets (Get-ForestState $xp $targets)') $null $OnState -AutoYes) })
$U.BtHint.Add_Click({ [void](Start-Work 'Bringing the hedges up to date' (Wrap 'Repair-Hedges $xp; Write-Host ''  Hedges are up to date.''') $null $OnState) })
$U.BtOffBack.Add_Click({ [void](Start-Work 'Switching back to your tweak' (Wrap 'Invoke-SwitchMenu $xp $targets') $null $OnState -AutoYes) })
$U.BtAct.Add_Click({
    switch ($script:ActKind) {
        'chk' { [void](Start-Work 'Check & repair' (Wrap 'Invoke-CheckRepair $xp $targets') $null $OnState) }
        'sw'  { [void](Start-Work 'Quick switch' (Wrap 'Invoke-SwitchMenu $xp $targets') $null $OnState -AutoYes) }
        'res' { [void](Start-Work 'Restore original' (Wrap 'Invoke-RestoreAll $xp $targets') $null $OnState) }
    }
})
$U.BtBusyBack.Add_Click({ $W.Close() })      # done: close the app (the pages on the left stay usable)
$U.BtBusyCancel.Add_Click({ if ($script:Job) { $U.BtBusyCancel.IsEnabled = $false; $U.BusyStatus.Text = 'stopping after the current tile ...'; [void]$script:Job.PS.BeginStop($null, $null) } })

$U.BtUpdNow.Add_Click({ Start-Update })
$U.BtUpdLater.Add_Click({ if ($script:Rel) { Save-GuiCfg @{ skip = ([string]$script:Rel.tag_name).TrimStart('v', 'V') } }; $U.BnUpd.Visibility = 'Collapsed' })
$U.BtUpdCancel.Add_Click({ if ($script:UpdPS) { $sync2.Cancel = $true } else { Show-Page 'Rec'; Set-NavEnabled $true; $U.NavRec.IsChecked = $true } })
$U.BtUpdPage.Add_Click({ try { Start-Process "https://github.com/$Repo/releases/latest" } catch { } })
$U.BtStaUpd.Add_Click({ $script:ManualUpd = $true; Start-UpdCheck })
$U.BtStaRef.Add_Click({ [void](Start-Work 'Reading the status' (Wrap '') $null $OnState) })
$OpenToolLog = { if ($script:State) { $p = Join-Path $script:State.TweakDir 'tool.log'; if (Test-Path -LiteralPath $p) { Start-Process notepad.exe -ArgumentList "`"$p`"" } } }
$U.BtStaLog.Add_Click($OpenToolLog); $U.BtLogTool.Add_Click($OpenToolLog)
$U.BtStaXp.Add_Click({ if ($script:State) { Start-Process explorer.exe -ArgumentList "`"$($script:State.XP)`"" } })
$U.BtLogRd.Add_Click({ $p = Join-Path $Here 'README.txt'; if (Test-Path -LiteralPath $p) { Start-Process notepad.exe -ArgumentList "`"$p`"" } })
$U.BtLogGh.Add_Click({ try { Start-Process "https://github.com/$Repo" } catch { } })
$U.BtLogCon.Add_Click({
    if ($script:Job) { return }
    $bat = Join-Path $Here 'Start_ForestTweak_Console.bat'
    if (Test-Path -LiteralPath $bat) { Start-Process -FilePath $bat; $script:Closing = $true; $W.Close() }
})

function Select-Nav([string]$p) { switch ($p) { 'Rec' { $U.NavRec.IsChecked = $true } 'Set' { $U.NavSet.IsChecked = $true } 'Sta' { $U.NavSta.IsChecked = $true } 'Log' { $U.NavLog.IsChecked = $true } default { } } }
foreach ($n in @{ NavRec = 'Rec'; NavSet = 'Set'; NavSta = 'Sta'; NavLog = 'Log'; NavChk = 'Act'; NavSw = 'Act'; NavRes = 'Act' }.GetEnumerator()) {
    $page = $n.Value; $U[$n.Key].Add_Checked([scriptblock]::Create("`$script:LastPage = '$page'"))
}

$W.Add_SourceInitialized({ Set-DarkTitle $W })
$W.Add_Closing({
    param($s, $e)
    if ($script:Closing) { return }
    if ($script:Job -and -not $script:Job.Quiet) {
        $prog = $sync.Prog
        if ($prog -and $prog.A -eq 'Hedge tiles') {
            if ((Show-Ask 'The hedge tiles are being built. Stop and close? It goes on where it stopped next time.') -ne 'y') { $e.Cancel = $true; return }
            try { $script:Job.PS.Stop() } catch { }
        } else { Show-Ask 'Please wait until the tool has finished - the files are being changed right now.' -Ok | Out-Null; $e.Cancel = $true; return }
    }
    if ($script:UpdPS -or $script:SetupProc) { $e.Cancel = $true; return }
})

# ---------------------------------------------------------------- timer: log, progress, questions, jobs
$script:Tick = 0
$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(150)
$timer.Add_Tick({
    try {
        Drain-Log
        $j = $script:Job
        if ($j -and -not $j.Quiet) {
            $p = $sync.Prog
            if ($p) {
                if ($p.P -ge 0) { $U.BusyBar.IsIndeterminate = $false; $U.BusyBar.Value = $p.P } else { $U.BusyBar.IsIndeterminate = $true }
                $rest = if ($p.R -gt 0) { if ($p.R -lt 90) { " $Dot $($p.R) s left" } else { " $Dot about $([Math]::Round($p.R / 60)) min left" } } else { '' }
                $U.BusyStatus.Text = "$($p.A): $($p.S)$rest"
                $hedge = $p.A -eq 'Hedge tiles'
                $U.BtBusyCancel.IsEnabled = $hedge -and $j.PS.InvocationStateInfo.State -eq 'Running'
                $U.BusyHint.Text = $(if ($hedge) { 'Safe to cancel - it goes on where it stopped.' } else { '' })
            } elseif ($U.BusyBar.Value -ge 100 -or -not $U.BusyStatus.Text) { $U.BusyBar.IsIndeterminate = $true }
        } elseif ($j -and $j.Name -eq 'init') {
            $p = $sync.Prog
            if ($p -and $p.P -ge 0) { $U.LoadBar.IsIndeterminate = $false; $U.LoadBar.Value = $p.P; $U.LoadText.Text = "$($p.A) $($p.S)" }
            elseif ($sync.Ask) { $U.LoadText.Text = "waiting for an answer: $($sync.Ask)" }
            elseif ($j.PS.InvocationStateInfo.State -ne 'Running') { $U.LoadText.Text = "worker: $($j.PS.InvocationStateInfo.State)" }
            else { $U.LoadText.Text = "$($sync.Step)   ($([int]([DateTime]::Now - $script:T0).TotalSeconds) s)" }
        }
        Test-Ask
        if ($j -and $j.H.IsCompleted -and $null -eq $sync.Ask) { Complete-Job }
        # live previews (quiet jobs, only while nothing else runs)
        if (-not $script:Job -and $script:State) {
            if ($script:PlanDue -and [DateTime]::Now -ge $script:PlanDue) {
                $script:PlanDue = $null
                $c = Get-Chosen
                if ($c -is [string]) { $U.Preview.Text = $c }
                else { $U.Preview.Text = 'working out what changes ...'; [void](Start-Work 'plan' $PlanScript @{ Preset = $c; Quick = $false; UseGf = $c.UseGf } { param($r, $e) $U.Preview.Text = $(if ($e) { '' } else { Format-Plan $r }) } -Quiet) }
            } elseif ($script:RecPlanDue) {
                $script:RecPlanDue = $false
                [void](Start-Work 'plan' $PlanScript @{ Preset = $null; Quick = $true; UseGf = [bool]$U.CbGf.IsChecked } { param($r, $e)
                    $U.RecPlan.Text = $(if ($e) { '' } elseif ($r -and $r.Nothing) { 'This setup is already active - nothing to change.' } elseif ($r) { (Format-Plan $r).Replace('Will change: ', 'Changes ') + '. Backups are made first.' } else { '' }) } -Quiet)
            }
        }
        if ($script:UpdTask) { Test-UpdDone ([bool]$script:ManualUpd); if (-not $script:UpdTask) { $script:ManualUpd = $false } }
        Test-UpdProgress
        Test-SetupDone
        $script:Tick++
        if ($script:Tick % 13 -eq 0) { Update-Running }
    } catch {
        # errors of the window itself: into window_errors.txt next to the tool, the first one also on screen
        $m = "$($_.Exception.Message) | $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())"
        try { [void]$script:SessionLog.AppendLine("  window: $m"); [IO.File]::AppendAllText((Join-Path $Here 'window_errors.txt'), "$(Get-Date -Format s)  $m`r`n$($_.ScriptStackTrace)`r`n") } catch { }
        if (-not $script:ErrShown) { $script:ErrShown = $true; try { Show-Fatal "Window error (please send a screenshot):`n`n$m" } catch { } }
    }
})

# ---------------------------------------------------------------- start
$AfterInit = {
    param($res, $err)
    if ($err -or -not $res) {
        $msg = if ($err) { $err.Message } else { 'unknown error' }
        $lines = $script:SessionLog.ToString().Trim()
        Show-Ask "The tool could not start: $msg" $lines -Ok | Out-Null
        $script:Closing = $true; $W.Close(); return
    }
    Set-State $res
    Set-DarkTitle $W
    try { if ('FdtWin' -as [type]) { [FdtWin]::HideConsole() } } catch { }      # the console stays visible only if the window could not start
    Show-Page 'Rec'
    Set-NavEnabled $true
    if ($UninstallRestore) {
        $s = $script:State
        if ($s.Off -or $s.N -or $s.KnicksOn -or $s.Hedges -ne 'default') {
            while ([bool](Get-Process -Name 'X-Plane' -ErrorAction SilentlyContinue)) {
                if ((Show-Ask 'X-Plane is running. Quit X-Plane, then click Yes to restore the original forests. No = uninstall without restoring.') -ne 'y') { $script:Closing = $true; $W.Close(); return }
            }
            [void](Start-Work 'Restore original' (Wrap 'Invoke-RestoreAll $xp $targets') $null { param($r, $e) if ($r) { Set-State $r }; $script:Closing = $true; $W.Close() } -AutoYes)
        } else { $script:Closing = $true; $W.Close() }
        return
    }
    Start-UpdCheck
}

$sync.Log.Enqueue("  XP12 Forest Tweak $GuiVersion - Windows")
Set-NavEnabled $false
Show-Page 'Load'
$script:T0 = [DateTime]::Now
$sync.Step = 'starting'
$LicMark = Join-Path $Here 'license_accepted.txt'
function Start-Init {
    try {
        $rs.SessionStateProxy.SetVariable('JobArgs', $null)
        $ps = [powershell]::Create(); $ps.Runspace = $rs
        [void]$ps.AddScript($WorkerBoot + "`n" + $InitScript)      # one script: AddStatement() hangs in Windows PowerShell 5.1
        $script:Job = @{ Name = 'init'; PS = $ps; H = $ps.BeginInvoke(); Done = $AfterInit; Quiet = $true }
        $timer.Start()
    } catch { Show-Fatal "The tool could not be started: $($_.Exception.Message)"; $script:Closing = $true; $W.Close() }
}
$U.CbLic.Add_Click({ $U.BtLicOk.IsEnabled = [bool]$U.CbLic.IsChecked })
$U.BtLicNo.Add_Click({ $script:Closing = $true; $W.Close() })
$U.BtLicOk.Add_Click({
    try { [IO.File]::WriteAllText($LicMark, "License accepted $(Get-Date -Format s) (XP12 Forest Tweak $GuiVersion)`r`n") } catch { }
    $script:T0 = [DateTime]::Now; Show-Page 'Load'; Start-Init
})
$W.Add_ContentRendered({
    # the license is asked once: by the setup, or here at the first start of the ZIP version
    if ($Installed -or $UninstallRestore -or (Test-Path -LiteralPath $LicMark)) { Start-Init; return }
    $lt = @('LICENSE.txt', 'LICENSE') | ForEach-Object { Join-Path $Here $_ } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    $U.LicBox.Text = if ($lt) { [IO.File]::ReadAllText($lt) } else { 'CC BY-NC-SA 4.0 with additional permission - see https://github.com/E11i0t09/xp12-forest-tweak/blob/main/LICENSE' }
    Show-Page 'Lic'
})
[void]$W.ShowDialog()
$timer.Stop()
try { if ($script:Job) { $script:Job.PS.Stop() } } catch { }
try { $rs.Close() } catch { }
exit 0
