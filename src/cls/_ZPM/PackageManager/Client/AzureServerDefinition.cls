Class %ZPM.PackageManager.Client.AzureServerDefinition Extends %ZPM.PackageManager.Client.ServerDefinition
{

Parameter DISPLAYNAME As STRING = "Azure Artifact Repository";

Parameter MONIKER As STRING = "azure";

Property Details As %String(MAXLEN = "") [ SqlComputeCode = {Set {*} = "Azure Artifact Feed: https://feeds.dev.azure.com/"_{Organization}_"/"_{Project}_"/_apis/packaging/Feeds/"_{FeedId}_"/"}, SqlComputed, SqlComputeOnChange = (%%INSERT, %%UPDATE) ];

Property Organization As %String(MAXLEN = "") [ Required ];

Parameter OrganizationPromptString = {$$$Text("Azure Organization:","ZPM")};

Property Project As %String(MAXLEN = "");

Parameter ProjectPromptString = {$$$Text("Azure Project:","ZPM")};

Property FeedId As %String(MAXLEN = "") [ Required ];

Parameter FeedIdPromptString = {$$$Text("Azure FeedId:","ZPM")};

Property PAT As %String(MAXLEN = "") [ Required ];

Parameter PATPromptString = {$$$Text("Azure PAT(Personal Access Token):","ZPM")};

/// TODO
Property DeploymentEnabled As %Boolean [ InitialExpression = 1 ];

Index AzureServer On DeploymentEnabled [ Unique ];

Property ZipCommand As %String(MAXLEN = "") [ Required ];

Property UnZipCommand As %String(MAXLEN = "") [ Required ];

/// This callback method is invoked by the <METHOD>%Save</METHOD> method to 
/// provide notification that the object is being saved. It is called before 
/// any data is written to disk.
/// 
/// <P><VAR>insert</VAR> will be set to 1 if this object is being saved for the first time.
/// 
/// <P>If this method returns an error then the call to <METHOD>%Save</METHOD> will fail.
Method %OnBeforeSave(insert As %Boolean) As %Status [ Private, ServerOnly = 1 ]
{
	// Leave DeploymentEnabled null to make unique index work right
	// (i.e., deployment can only be enabled for one remote server.)
	Set:..DeploymentEnabled=0 ..DeploymentEnabled=""
	Quit $$$OK
}

/// This callback method is invoked by the <METHOD>%ValidateObject</METHOD> method to 
/// provide notification that the current object is being validated.
/// 
/// <P>If this method returns an error then <METHOD>%ValidateObject</METHOD> will fail.
Method %OnValidateObject() As %Status [ Private, ServerOnly = 1 ]
{
	Set tStatus = $$$OK
	Quit tStatus
}

/// Returns a REST client to interact with this server.
Method GetPackageService() As %ZPM.PackageManager.Core.IPackageService
{
	Set tClient = ##class(%ZPM.PackageManager.Client.Azure.PackageManagerClient).%New()
	Set tClient.Organization = ..Organization
	Set tClient.Project = ..Project
	Set tClient.FeedId = ..FeedId
	set tClient.PAT = ..PAT
	set tClient.UnZipCommand = ..UnZipCommand
	Quit tClient
}

/// Returns a REST client to publish modules/applications to this server.
Method GetPublishService() As %ZPM.PackageManager.Core.IPublishService
{
	Set tClient = ##class(%ZPM.PackageManager.Client.Azure.PublishClient).%New()
	Set tClient.Organization = ..Organization
	Set tClient.Project = ..Project
	Set tClient.FeedId = ..FeedId
	set tClient.PAT = ..PAT
	set tClient.ZipCommand = ..ZipCommand
	return tClient
}

/// Outputs information about this server to the current device.
/// Subclasses may override to show additional information.
Method Display()
{
	Do ##super()

	If (..Organization '= "") {
		Write !,$c(9),"Organization:",$c(9),..Organization
	}
	
	If (..Project '= "") {
		Write !,$c(9),"Project:",$c(9),..Project
	}
	
	If (..FeedId '= "") {
		Write !,$c(9),"FeedId:",$c(9),..FeedId
	}
	
	If (..PAT '= "") {
		Write !,$c(9),"PAT:",$c(9),$Case(..PAT,"":"<unset>",:"<set>")
	}
	
	Write !,$c(9),"DeploymentEnabled:",$c(9),..DeploymentEnabled
	
	Write !,$c(9),"ZipCommand",$c(9),..ZipCommand
	
	Write !,$c(9),"UnZipCommand",$c(9),..UnZipCommand
}

/// Handles modifiers/data attributes provided from the package manager shell.
ClassMethod OnConfigure(pInstance As %ZPM.PackageManager.Client.ServerDefinition, pInteractive As %Boolean = 1, ByRef pModifiers, ByRef pData) As %Status
{
	Set tSC = $$$OK
	Try {
		Set tOrg = $Get(pModifiers("organization"), pInstance.Organization)
		If (pInteractive && (tOrg = "")) {
			Set tPrompt = ..#OrganizationPromptString
			Set tResponse = ##class(%Library.Prompt).GetString(tPrompt, .tOrg)
			If (tResponse '= $$$SuccessResponse) {
				$$$ThrowStatus($$$ERROR($$$GeneralError, "Operation cancelled."))
			}
		}
		Set pInstance.Organization = tOrg
		
			
		Set tProject = $Get(pModifiers("project"), pInstance.Project)
		If (pInteractive && (tProject = "")) {
			Set tPrompt = ..#ProjectPromptString
			Set tResponse = ##class(%Library.Prompt).GetString(tPrompt, .tProject)
			If (tResponse '= $$$SuccessResponse) {
				$$$ThrowStatus($$$ERROR($$$GeneralError, "Operation cancelled."))
			}
		}
		Set pInstance.Project = tProject
		
		
		Set tFeedId = $Get(pModifiers("feedId"), pInstance.FeedId)
		If (pInteractive && (tFeedId = "")) {
			Set tPrompt = ..#FeedIdPromptString
			Set tResponse = ##class(%Library.Prompt).GetString(tPrompt, .tFeedId)
			If (tResponse '= $$$SuccessResponse) {
				$$$ThrowStatus($$$ERROR($$$GeneralError, "Operation cancelled."))
			}
		}
		Set pInstance.FeedId = tFeedId
		
		
		Set tPat = $Get(pModifiers("pat"), pInstance.PAT)
		If (pInteractive && (tPat = "")) {
			Set tPrompt = ..#PATPromptString
			Set tResponse = ##class(%Library.Prompt).GetString(tPrompt, .tPat)
			If (tResponse '= $$$SuccessResponse) {
				$$$ThrowStatus($$$ERROR($$$GeneralError, "Operation cancelled."))
			}
		}
		Set pInstance.PAT = tPat
				

		Set tZipCommand = $Get(pModifiers("zipCommand"), pInstance.ZipCommand)
		If (tZipCommand = "") {
			set pInstance.ZipCommand = $case($system.Version.GetBuildOS(), 
				"Windows": "powershell.exe -NoP -NonI -Command ""Compress-Archive -DestinationPath %1 -Path %2\* -Force""",
				"UNIX": "zip -r %1 %2",
				"VMS":"TODO")
		} else {
			set pInstance.ZipCommand = tZipCommand
		}
		
		Set tUnZipCommand = $Get(pModifiers("unZipCommand"), pInstance.UnZipCommand)
		If (tUnZipCommand = "") {
			set pInstance.UnZipCommand = $case($system.Version.GetBuildOS(), 
				"Windows": "powershell.exe -nologo -noprofile -command ""& { Try {Add-Type -A 'System.IO.Compression.FileSystem'; [IO.Compression.ZipFile]::ExtractToDirectory('%1', '%2'); }Catch{ exit -1} }""",
				"UNIX": "unzip %1 -d %2",
				"VMS":"TODO")
		} else {
			set pInstance.UnZipCommand = tUnZipCommand
		}
			
		//TODO: Grok
		/*If ((pInstance.%Id()="")&&..DeploymentServerExists(1)) {
			$$$ThrowStatus($$$ERROR($$$GeneralError, "Unable to add new remote server."_$$$NL_" Use ""repo -r -n registry -url <new url>"" to switch to another server"_$$$NL))
		}*/
	} Catch e {
		Set tSC = e.AsStatus()
	}
	Quit tSC
}

Method GetSortOrder() As %Integer [ Private ]
{
	// TODO: Allow this to be changed dynamically.
	Quit 2 + $Case(..%Id(),"":1,:..%Id())
}

Storage Default
{
<Data name="AzureServerDefinitionDefaultData">
<Subscript>"AzureServerDefinition"</Subscript>
<Value name="1">
<Value>Organization</Value>
</Value>
<Value name="2">
<Value>Project</Value>
</Value>
<Value name="3">
<Value>FeedId</Value>
</Value>
<Value name="4">
<Value>PAT</Value>
</Value>
<Value name="5">
<Value>DeploymentEnabled</Value>
</Value>
<Value name="6">
<Value>ZipCommand</Value>
</Value>
<Value name="7">
<Value>UnZipCommand</Value>
</Value>
</Data>
<DefaultData>AzureServerDefinitionDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}

