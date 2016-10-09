﻿param([String]$StudioVersion = "Studio4")

if ("${Env:ProgramFiles(x86)}")
{
    $ProgramFilesDir = "${Env:ProgramFiles(x86)}"
}
else
{
    $ProgramFilesDir = "${Env:ProgramFiles}"
}

Add-Type -Path "$ProgramFilesDir\SDL\SDL Trados Studio\$StudioVersion\Sdl.ProjectAutomation.FileBased.dll";
Add-Type -Path "$ProgramFilesDir\SDL\SDL Trados Studio\$StudioVersion\Sdl.ProjectAutomation.Core.dll";

##########################################################################################################
# Due to Trados Studio bug causing new projects to be based on "Default.sdltpl" template instead of default project template,
# we need to find the real default template configured in Trados Studio by reading the configuration files
switch ($StudioVersion)
{
	"Studio2" {$StudioVersionAppData = "10.0.0.0"};
	"Studio3" {$StudioVersionAppData = "11.0.0.0"};
	"Studio4" {$StudioVersionAppData = "12.0.0.0"};
}
# Get default project template GUID from the user settings file
$DefaultProjectTemplateGuid = Select-Xml -Path "${Env:AppData}\SDL\SDL Trados Studio\$StudioVersionAppData\UserSettings.xml" -XPath "//Setting[@Id='DefaultProjectTemplateGuid']" | foreach {$_.node.InnerXml};
# Get the location of local projects storage from ProjectApi configuration file
$LocalDataFolder = Select-Xml -Path "${Env:AppData}\SDL\ProjectApi\$StudioVersionAppData\SDL.ProjectApi.xml" -XPath "//LocalProjectServerInfo/@LocalDataFolder" | foreach {$_.node.Value};
# Finally, get the default project template path from local project storage file
$DefaultProjectTemplate = Select-Xml -Path "$LocalDataFolder\projects.xml" -XPath "//ProjectTemplateListItem[@Guid='$DefaultProjectTemplateGuid']/@ProjectTemplateFilePath" | foreach {$_.node.Value};
##########################################################################################################

function Get-TaskFileInfoFiles
{
	param(
		[Sdl.Core.Globalization.Language] $language,
		[Sdl.ProjectAutomation.FileBased.FileBasedProject] $project
	)
	
	[Sdl.ProjectAutomation.Core.TaskFileInfo[]]$taskFilesList = @();
	foreach($taskfile in $project.GetTargetLanguageFiles($language))
	{
		$fileInfo = New-Object Sdl.ProjectAutomation.Core.TaskFileInfo;
		$fileInfo.ProjectFileId = $taskfile.Id;
		$fileInfo.ReadOnly = $false;
		$taskFilesList = $taskFilesList + $fileInfo;
	}
	return $taskFilesList;
}

function Validate-Task
{
	param ([Sdl.ProjectAutomation.Core.AutomaticTask] $taskToValidate)

	if($taskToValidate.Status -eq [Sdl.ProjectAutomation.Core.TaskStatus]::Failed)
	{
		Write-Host "Task"$taskToValidate.Name"not completed.";  
		foreach($message in $taskToValidate.Messages)
		{
			Write-Host $message.Message -ForegroundColor red ;
		}
	}
	if($taskToValidate.Status -eq [Sdl.ProjectAutomation.Core.TaskStatus]::Invalid)
	{
		Write-Host "Task"$taskToValidate.Name"not completed.";  
		foreach($message in $taskToValidate.Messages)
		{
			Write-Host $message.Message -ForegroundColor red ;
		}
	}
	if($taskToValidate.Status -eq [Sdl.ProjectAutomation.Core.TaskStatus]::Rejected)
	{
		Write-Host "Task"$taskToValidate.Name"not completed.";  
		foreach($message in $taskToValidate.Messages)
		{
			Write-Host $message.Message -ForegroundColor red ;
		}
	}
	if($taskToValidate.Status -eq [Sdl.ProjectAutomation.Core.TaskStatus]::Cancelled)
	{
		Write-Host "Task"$taskToValidate.Name"not completed.";  
		foreach($message in $taskToValidate.Messages)
		{
			Write-Host $message.Message -ForegroundColor red ;
		}
	}
	if($taskToValidate.Status -eq [Sdl.ProjectAutomation.Core.TaskStatus]::Completed)
	{
		Write-Host "Task"$taskToValidate.Name"successfully completed." -ForegroundColor green;  
	}
}

function New-Project
{
<#
.SYNOPSIS
Creates new Trados Studio file based project.

.DESCRIPTION
Creates new Trados Studio file based project in specified location, with specified source and target languages.
Project can be optionally based on specified project template or other reference project.
Translation memories (*.sdltm) are searched in specified location according to source and target languages.
Source files are added from specified location recursively including folders.
Following tasks are run automatically after project creation:
- Scan
- Convert to translatable format
- Copy to target languages
Optionally also following tasks can be run:
- Pretranslate
- Analyze

.PARAMETER Name
Project name. Must not contain invalid characters such as \ / : * ? " < > |

.PARAMETER ProjectLocation
Path to directory where the project should be created.
Any existing content of the directory will be deleted before creating the project.
If the directory does not exist, it will be created.

.PARAMETER SourceLanguage
Locale code of project source language.
See (incomplete) list of codes at https://www.microsoft.com/resources/msdn/goglobal/
Hint: Code for Latin American Spanish is "es-419" ;-)

.PARAMETER TargetLanguages
Space- or comma- or semicolon-separated list of locale codes of project target languages.
See (incomplete) list of codes at https://www.microsoft.com/resources/msdn/goglobal/
Hint: Code for Latin American Spanish is "es-419" ;-)

.PARAMETER TMsLocation
Path to directory containing Trados Studio translation memories for project language pairs.
Directory will be searched for all TMs with language pairs defined for the project and found TMs will be assigned to the project languages.
Additional TMs defined in project template or reference project will be retained (unless "OverrideTMs" parameter is specified).
Note: directory is NOT searched recursively!

.PARAMETER SourceLocation
Path to directory containing project source files.
Complete directory structure present in that directory will be added as project source.

.PARAMETER ProjectTemplate
Path to project template (*.sdltpl) on which the created project should be based.
If this parameter is not specified, default project template set in Trados Studio will be used.

.PARAMETER ProjectReference
Path to project file (*.sdlproj) on which the created project should be based.

.PARAMETER OverrideTMs
Ignore TMs defined in project template or reference project and use only TMs from "TMLocation" directory.

.PARAMETER Pretranslate
Run pre-translation task for each target language after project creation.

.PARAMETER Analyze
Run analysis task for each target language after project creation.

.EXAMPLE
New-Project -Name "Sample Project" -ProjectLocation "D:\Projects\Trados Studio Automation\Sample" -SourceLanguage "en-GB" -TargetLanguages "de-DE,ja-JP" -TMsLocation "D:\Projects\TMs\Samples" -ProjectTemplate "D:\ProjectTemplates\SampleTemplate.sdltpl" -SourceLocation "D:\Projects\Trados Studio Automation\Source files" -Analyze

Creates project named "Sample Project" based on "D:\ProjectTemplates\SampleTemplate.sdltpl" project template in "D:\Projects\Trados Studio Automation\Sample" folder, with British English as source language and German and Japanese as target languages; source files are taken from "D:\Projects\Trados Studio Automation\Source files" folder and translation memories are taken from "D:\Projects\TMs\Samples" folder; and runs Analyze as additional task after scanning, converting and copying to target languages.

.EXAMPLE
New-Project -Name "Project" -ProjectLocation "D:\Project" -SourceLanguage "en-US" -TargetLanguages "fi-FI" -TMsLocation "D:\TMs" -SourceLocation "D:\Sources" -Pretranslate -Analyze

Creates project named "Project" based on default Trados Studio project template in "D:\Project" folder, with American English as source language and Finnish as target language; source files are taken from "D:\Sources" folder and translation memories are taken from "D:\TMs" folder; and runs Pretranslate and Analyze as additional tasks after scanning, converting and copying to target languages.
#>

	[CmdletBinding(DefaultParametersetName="ProjectTemplate")]

	param(
		[Parameter (Mandatory = $true)]
		[String] $Name,

		[Parameter (Mandatory = $true)]
		[String] $ProjectLocation,

		[Parameter (Mandatory = $true)]
		[String] $SourceLanguage,

		[Parameter (Mandatory = $true)]
		[String] $TargetLanguages,

		[Parameter (Mandatory = $true)]
		[String] $TMsLocation,

		[Parameter (Mandatory = $true)]
		[String] $SourceLocation,

		[Parameter (Mandatory = $false, ParameterSetName = "ProjectTemplate")]
		[String] $ProjectTemplate = $DefaultProjectTemplate,

		[Parameter (Mandatory = $false, ParameterSetName = "ProjectReference")]
		[String] $ProjectReference,

		[Switch] $OverrideTMs,
		[Switch] $Pretranslate,
		[Switch] $Analyze
	)

	# If project location does not exist, create it...
	if (!(Test-Path $ProjectLocation))
	{
		New-Item -Path $ProjectLocation -Force -ItemType Directory | Out-Null
	}
	# ...and if it does exist, empty it
	else
	{
		Get-ChildItem $ProjectLocation * | Remove-Item -Force -Recurse
	}

	# Parse target languages into array
	$TargetLanguagesList = $TargetLanguages -Split " |;|,";
	
	# Create project info
	$ProjectInfo = New-Object Sdl.ProjectAutomation.Core.ProjectInfo;
	$ProjectInfo.Name = $Name;
	$ProjectInfo.LocalProjectFolder = $ProjectLocation;
	$ProjectInfo.SourceLanguage = Get-Language $SourceLanguage;
	$ProjectInfo.TargetLanguages = Get-Languages $TargetLanguagesList;

	# Create file based project
	"`nCreating new project...";
	
	switch ($PsCmdlet.ParameterSetName)
	{
		"ProjectTemplate"
		{
			$ProjectTemplate = Resolve-Path $ProjectTemplate;
			$ProjectCreationReference = New-Object Sdl.ProjectAutomation.Core.ProjectTemplateReference $ProjectTemplate;
			break
		}
		"ProjectReference"
		{
			$ProjectReference = Resolve-Path $ProjectReference;
			$ProjectCreationReference =  New-Object Sdl.ProjectAutomation.Core.ProjectReference $ProjectReference;
			break
		}
	}
	$FileBasedProject = New-Object Sdl.ProjectAutomation.FileBased.FileBasedProject ($ProjectInfo, $ProjectCreationReference);

	# Assign TMs to project languages
	"`nAssigning TMs to project...";
	
	# Loop through all TMs present in TMs location
	$TMPaths = Get-ChildItem $TMsLocation *.sdltm | foreach {$_.FullName};
	foreach($TMPath in $TMPaths)
	{
		# Get TM language pair
		$TMSourceLanguage = Get-TMSourceLanguage $TMPath | foreach {Get-Language $_.Name};
		$TMTargetLanguage = Get-TMTargetLanguage $TMPath | foreach {Get-Language $_.Name};
		
		# If TM languages are not one of the project lang pairs, skip to next TM
		if ($tmSourceLanguage -ne $SourceLanguage -or $tmTargetLanguage -notin $TargetLanguagesList) {continue};
	
		# Create new TranslationProviderCascadeEntry entry object for currently processed TM
		$TMentry = New-Object Sdl.ProjectAutomation.Core.TranslationProviderCascadeEntry ($TMPath, $true, $true, $true);
		
		# Get existing translation provider configuration which can be defined in project template or reference project
		[Sdl.ProjectAutomation.Core.TranslationProviderConfiguration] $TMConfig = $FileBasedProject.GetTranslationProviderConfiguration($TMTargetLanguage);
		
		# If $OverrideTMs parameter was specified, remove all existing TMs from translation provider configuration
		if ($OverrideTMs) {$TMConfig.Entries.Clear()}
		
		# Get list of TM URIs from existing translation provider configuration
		$TMUris = $TMConfig.Entries | foreach {$_.MainTranslationProvider.Uri};
		
		# If the TM is not in the existing TMs list, add it
		if ($TMentry.MainTranslationProvider.Uri -notin $TMUris)
		{
			$TMConfig.Entries.Add($TMentry);
			$TMConfig.OverrideParent = $true;
			$FileBasedProject.UpdateTranslationProviderConfiguration($TMTargetLanguage, $TMConfig);
			"$TMPath added to project"
		}
		else {"$TMPath already defined in project"}
	}

	# Add project source files
	"`nAdding source files...";
	$ProjectFiles = $FileBasedProject.AddFolderWithFiles($SourceLocation, $true);

	# Get source language project files IDs
	[Sdl.ProjectAutomation.Core.ProjectFile[]] $ProjectFiles = $FileBasedProject.GetSourceLanguageFiles();
	[System.Guid[]] $SourceFilesGuids = Get-Guids $ProjectFiles;

	# Run preparation tasks
	"`nRunning preparation tasks...";
	Validate-Task $FileBasedProject.RunAutomaticTask($SourceFilesGuids,[Sdl.ProjectAutomation.Core.AutomaticTaskTemplateIds]::Scan);
	Validate-Task $FileBasedProject.RunAutomaticTask($SourceFilesGuids,[Sdl.ProjectAutomation.Core.AutomaticTaskTemplateIds]::ConvertToTranslatableFormat);
	Validate-Task $FileBasedProject.RunAutomaticTask($SourceFilesGuids,[Sdl.ProjectAutomation.Core.AutomaticTaskTemplateIds]::CopyToTargetLanguages);

	# Run pretranslate and analyze
	if ($Pretranslate -or $Analyze)
	{
		"`nRunning pre-translation / analysis tasks...";
		# initialize target files guids array
		[System.Guid[]] $TargetFilesGuids = @();
		
		# loop through target languages and get target project files IDs
		foreach($TargetLanguage in $TargetLanguagesList)
		{
			$TargetFiles = $FileBasedProject.GetTargetLanguageFiles($TargetLanguage);
			$TargetFilesGuids += Get-Guids $TargetFiles;
		}

		# Run the actual pretranslate and/or analyze tasks
		if ($Pretranslate) {Validate-Task $FileBasedProject.RunAutomaticTask($TargetFilesGuids,[Sdl.ProjectAutomation.Core.AutomaticTaskTemplateIds]::PreTranslateFiles)};
		if ($Analyze) {Validate-Task $FileBasedProject.RunAutomaticTask($TargetFilesGuids,[Sdl.ProjectAutomation.Core.AutomaticTaskTemplateIds]::AnalyzeFiles)};
	}
	
	# Save the project
	"`nSaving project...";
	#"$($FileBasedProject.FilePath)";
	$FileBasedProject.Save();
}

function Get-Project
{
<#
.SYNOPSIS
Opens Trados Studio file based project.

.DESCRIPTION
Opens Trados Studio file based project in specified location.

.PARAMETER ProjectLocation
Path to directory where the project file is located.

#>
	param(
		[Parameter (Mandatory = $true)]
		[String] $ProjectLocation
	)
	
	# get project file path
	$ProjectFilePath = Get-ChildItem $ProjectLocation *.sdlproj | foreach {$_.FullName}
	
	# get file based project
	$FileBasedProject = New-Object Sdl.ProjectAutomation.FileBased.FileBasedProject($ProjectFilePath);
	
	return $FileBasedProject;
}

function Remove-Project
{
<#
.SYNOPSIS
Deletes Trados Studio file based project.

.DESCRIPTION
Deletes Trados Studio file based project in specified location.
Complete project is deleted, including the project location directory.

.PARAMETER ProjectLocation
Path to directory where the project file is located.

#>
	param (
		[Parameter (Mandatory = $true)]
		[String] $ProjectLocation
	)

	$ProjectToDelete = Get-Project $ProjectLocation
	$projectToDelete.Delete();
}

function Get-AnalyzeStatistics
{
	param([Sdl.ProjectAutomation.FileBased.FileBasedProject] $project)

	$projectStatistics = $project.GetProjectStatistics();

	$targetLanguagesStatistics = $projectStatistics.TargetLanguageStatistics;

	foreach($targetLanguageStatistic in  $targetLanguagesStatistics)
	{
		Write-Host ("Exact Matches (characters): " + $targetLanguageStatistic.AnalysisStatistics.Exact.Characters);
		Write-Host ("Exact Matches (words): " + $targetLanguageStatistic.AnalysisStatistics.Exact.Words);
		Write-Host ("New Matches (characters): " + $targetLanguageStatistic.AnalysisStatistics.New.Characters);
		Write-Host ("New Matches (words): " + $targetLanguageStatistic.AnalysisStatistics.New.Words);
		Write-Host ("New Matches (segments): " + $targetLanguageStatistic.AnalysisStatistics.New.Segments);
		Write-Host ("New Matches (placeables): " + $targetLanguageStatistic.AnalysisStatistics.New.Placeables);
		Write-Host ("New Matches (tags): " + $targetLanguageStatistic.AnalysisStatistics.New.Tags);
	}
}

Export-ModuleMember New-Project;
Export-ModuleMember Get-Project;
Export-ModuleMember Remove-Project;
Export-ModuleMember Get-AnalyzeStatistics;
Export-ModuleMember Get-TaskFileInfoFiles;