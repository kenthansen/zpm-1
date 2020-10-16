Class %ZPM.PackageManager.Client.Azure.PackageManagerClient Extends (%RegisteredObject, %ZPM.PackageManager.Core.IPackageService)
{

Property Organization As %String;

Property Project As %String;

Property FeedId As %String;

Property PAT As %String;

Property Location As %String;

Property UnZipCommand As %String;

Method LocationGet() As %String
{
	Return $$$FormatText("https://feeds.dev.azure.com/%1%2/_apis/packaging/Feeds/%3/",..Organization, $SELECT(..Project'="":"/"_..Project,1:""), ..FeedId)
}

Method GetInfo(url As %String) As %DynamicObject
{
 	Set tRequest = ..GetHttpRequest()
 	Set tSC = tRequest.Get()

  If $$$ISOK(tSC), tRequest.HttpResponse.StatusCode=200 {
    Set tRes = {}.%FromJSON(tRequest.HttpResponse.Data)
    Return tRes
  }

	$$$ThrowStatus($$$ERROR($$$GeneralError,"Registry server not available."))
}

Method ListModules(pSearchCriteria As %ZPM.PackageManager.Core.SearchCriteria) As %ListOfObjects(ELEMENTTYPE="%ZPM.PackageManager.Core.ResolvedModuleReference")
{
  Set tList = ##class(%Library.ListOfObjects).%New()
  Set tRequest = ..GetHttpRequest()

  Set name = $$$lcase(pSearchCriteria.Name)
  Set tVersionExpression = pSearchCriteria.VersionExpression
  Set tSC = ##class(%ZPM.PackageManager.Core.SemanticVersionExpression).FromString(pSearchCriteria.VersionExpression, .tVersionExpression)
  $$$ThrowOnError(tSC)

  If name = "" {
    Set tSC = tRequest.Get(tRequest.Location_"packages?protocolType=NuGet&includeAllVersions=true&api-version=6.0-preview.1")
  }
  Else {
    Set tSC = tRequest.Get($$$FormatText("%1packages?protocolType=NuGet&packageNameQuery=%2&includeAllVersions=true&api-version=6.0-preview.1", tRequest.Location, $$$URLENCODE(name)))
  }
  If $$$ISOK(tSC), tRequest.HttpResponse.StatusCode=200 {
    Set tRes = {}.%FromJSON(tRequest.HttpResponse.Data)
    //TODO: Not Sure if this part is needed or not
    If ('tRes.value.%IsA("%Library.DynamicArray")) {
      Set tRes = [].%Push(tRes.value)
    }
    else {
	  Set tRes = tRes.value
    }
    
    Set tIter = tRes.%GetIterator()

    While tIter.%GetNext(.key, .item) {
      Set tIterVer = item.versions.%GetIterator()
      WHILE tIterVer.%GetNext(.verkey, .versionObj) {
        Set tVersion = ##class(%ZPM.PackageManager.Core.SemanticVersion).FromString(versionObj.version)
        CONTINUE:'tVersion.Satisfies(tVersionExpression)
        Set tModRef = ##class(%ZPM.PackageManager.Core.ResolvedModuleReference).%New()
        Set tModRef.Name = item.name
        Set tModRef.Repo = item.repository
        Set tModRef.VersionString = versionObj.version
        Do tList.Insert(tModRef)
      }      
    }
  }
  
  Return tList
}

Method GetModule(pModuleReference As %ZPM.PackageManager.Core.ResolvedModuleReference, Output AsArchive As %Boolean = 1) As %Stream.Object
{
  Set tRequest = ..GetHttpRequest($$$FormatText("https://pkgs.dev.azure.com/%1%2/_apis/packaging/Feeds/%3/",..Organization, $SELECT(..Project'="":"/"_..Project,1:""), ..FeedId))
  Set tFileBinStream = ""
  Set AsArchive = 1

  Set name = pModuleReference.Name
  Set version = pModuleReference.VersionString

  set tRequestUrl = $$$FormatText("%1nuget/packages/%2/versions/%3/content?api-version=6.0-preview.1", tRequest.Location, $$$URLENCODE(name), $$$URLENCODE(version))
  w !, "URL: ", tRequestUrl
  
  //Azure Dev Ops will send a redirect and if you allow Iris to follow the redirect automatically the second request will fail
  //because the second location will reject the authorization header (it uses something different)
  set tRequest.FollowRedirect = 0  
  Set tSC = tRequest.Get(tRequestUrl)
  
  //Expect the redirect
  If $$$ISOK(tSC), tRequest.HttpResponse.StatusCode=303 {	  	
	  set tRedirectLocation = tRequest.HttpResponse.GetHeader("LOCATION")
	  Set tRequest = ..GetHttpRequest(tRedirectLocation)	  
	  w !,"Redirect Url:",$c(9),tRedirectLocation
	  //Clear out the PAT
	  set tRequest.Username = ""
	  Set tRequest.Password = ""
	  //Continue to the redirect location
	  set tSC = tRequest.Get(tRedirectLocation)
  }
  else
  {
	  $$$ThrowStatus($$$ERROR($$$GeneralError, "Download module, expected a redirect."))
  }

  Set tPackageUrl = ""
  If $$$ISOK(tSC), tRequest.HttpResponse.StatusCode=200 {
	  //Expect to retrieve a NuGet(zip), save it to disk
      Set tNuGetBinStream = ##class(%Stream.FileBinary).%New()
      Set tNuGetBinStream.Filename = ##class(%File).TempFilename("nuget")
      do tNuGetBinStream.CopyFromAndSave(tRequest.HttpResponse.Data)
      	    
      w !,"Retrieved Nuget:",!,$c(9),tNuGetBinStream.Filename
      
      Set tWorkingDirectory=$$$FileTempDir
      
      Set tCMD = $$$FormatText(..UnZipCommand, tNuGetBinStream.Filename, tWorkingDirectory)
	  Set tStatus=$zf(-1,tCMD) If tStatus Set tSC=$$$ERROR($$$GeneralError,"Unable to unzip "_tCMD) Quit
     
      set tTarFileName = ##class(%File).NormalizeFilename(tWorkingDirectory_"/"_name_".tgz")
	  Set tTarBinStream = ##class(%Stream.FileBinary).%New()
      do tTarBinStream.LinkToFile(tTarFileName)            
  }
  If tTarBinStream="" {
    $$$ThrowStatus($$$ERROR($$$GeneralError,"Download module, something went wrong."))
  }
  Quit tFileBinStream
}

Method GetModuleManifest(pModuleReference As %ZPM.PackageManager.Core.ResolvedModuleReference) As %Stream.Object
{
  $$$ThrowStatus($$$ERROR($$$GeneralError,"Not Yet Implemented."))
  Set tRequest = ..GetHttpRequest()
  Set tFileBinStream = ""

  Set name = pModuleReference.Name
  Set version = pModuleReference.VersionString

  Set tSC = tRequest.Get($$$URLENCODE(tRequest.Location_"packages/" _ name _ "/"_version_"/manifest"))
  If $$$ISOK(tSC), tRequest.HttpResponse.StatusCode=200 {
    Return tRequest.HttpResponse.Data
  }

  $$$ThrowStatus($$$ERROR($$$GeneralError,"Download package manifest, something went wrong."))
}

Method SendAnalyticsToRegistry(action As %String, data As %DynamicObject)
{
    Set tRequest = ..GetHttpRequest()
    Set tRequest.ContentType = "application/json"
    Do tRequest.SetHeader("INSTALLTOKEN", $Get(^IRIS.TempZPMRInst(data.name,data.version))) 
    Kill ^IRIS.TempZPMRInst(data.name,data.version)
    Do data.%ToJSON(tRequest.EntityBody) 
    Set tSC = tRequest.Post($$$URLENCODE(tRequest.Location_"collect/" _ action))
    If ($$$ISERR(tSC) || (tRequest.HttpResponse.StatusCode'=200)) {
        $$$ThrowStatus($$$ERROR($$$GeneralError,"Error Sending Analytics Data"))
    }
}

Method SendAnalyticsToGoogle(action As %String, data As %DynamicObject)
{
    Set TrackingID = ##class(%ZPM.PackageManager.Client.Settings).GetAnalyticsTrackingId()
    Quit:(TrackingID = "") 0
    Set tRequest = ##class(%Net.HttpRequest).%New()
    Set tRequest.FollowRedirect = 1
    Set tRequest.Server = "www.google-analytics.com"
    Set tRequest.SSLConfiguration = ..GetSSLConfiguration(tRequest.Server)

    Set status = $case($$$ISOK(data.success), 1: "Success", : "Failure")
    Set version = data.version
    Set irisPlatform = $system.Version.GetPlatform()
    Set irisVersion = $system.Version.GetNumber()
    Set irisProduct = $system.Version.GetProduct()

    Do tRequest.SetParam("v","1")
    Do tRequest.SetParam("tid",TrackingID)
    Do tRequest.SetParam("cid",##class(%SYS.System).InstanceGUID())
    Do tRequest.SetParam("ds","web")
    Do tRequest.SetParam("t","event")
    Do tRequest.SetParam("ec",data.name)
    Do tRequest.SetParam("ea",status)
    Do tRequest.SetParam("el",version_", "_irisProduct_", "_irisPlatform_", "_irisVersion)
    Return tRequest.Post("/collect")
}

Method CollectAnalytics(action As %String, name As %String, version As %String, success As %Boolean = 1, msg As %String = "") As %Status
{
    If ('##class(%ZPM.PackageManager.Client.Settings).GetAnalyticsAvailable()) {
        Return $$$OK
    }
    Set jo = {}
    Set jo.name = name
    Set jo.version = version
    Set jo.guid = ##class(%SYS.System).InstanceGUID()
    Set jo."system_version" = $ZVersion
    Set zpmVersion = ##class(%ZPM.PackageManager.Client.Utils).GetZPMVersion()
    If (zpmVersion'="") {
        Set jo."zpmclient_version" = zpmVersion
    } 
    Do jo.%Set("success",success,"boolean")
    Set jo."error_msg" = msg
    Try {
        Do ..SendAnalyticsToRegistry(action, jo)
        Do ..SendAnalyticsToGoogle(action, jo)
    } Catch ex {
        Return ex.AsStatus()
    }
    Return $$$OK
}

/// For run-time checks to ensure the service is available before attempting to invoke it.
Method IsAvailable() As %Boolean
{
  Set tAvailable = 0
  Set tRequest = ..GetHttpRequest()
  
  Set tRequest.Timeout = 1
  Set tSC = tRequest.Get(tRequest.Location_"packages?api-version=6.0-preview.1&packageNameQuery=65d6fc97c29643a5b75d286b1fa07b06&includeAllVersions=false")
  set status =tRequest.HttpResponse.StatusCode
  If $$$ISOK(tSC) && (tRequest.HttpResponse.StatusCode = 200) {
    Set tAvailable = 1
  }
  Return tAvailable
}

Method GetHttpRequest(tLocation = {..Location}) As %Net.HttpRequest
{
  Set tRequest = ##class(%Net.HttpRequest).%New()
  //TODO: Remove
  /*set tRequest.ProxyPort = "8866"
  set tRequest.ProxyServer = "127.0.0.1"
  set tRequest.ProxyHTTPS = 1
  set tRequest.ProxyTunnel = 1*/
  

  Set tRequest.FollowRedirect = 1

  Set tLocation = $$$URLDECODE(tLocation)
  If ($piece(tLocation, "://")'["http") {
    Set tLocation = "http://" _ tLocation
  }
  
  Do ##class(%Net.URLParser).Parse(tLocation,.tComponents)
  
	If ($$$lcase(tComponents("scheme")) [ "http") {
		If ($Data(tComponents("host"))#2) {
			Set tRequest.Server = tComponents("host")
		}
		If ($Data(tComponents("port"))#2) {
			Set tRequest.Port = tComponents("port")
		}
		If ($$$lcase(tComponents("scheme")) = "https") {
			Set tRequest.Https = 1
    }
    If ($Get(tComponents("path"))'="") {
			Set path = tComponents("path")
			If ($Extract(path,1,1)="/") {
				Set path = $Extract(path,2,*)	
			}
			Set tRequest.Location = path
		}
    #; in case of redirection
    Set tRequest.SSLConfiguration = ..GetSSLConfiguration(tRequest.Server)
    
	If (..PAT '= "") {
		set tRequest.Username = "PAT"
  		Set tRequest.Password = ..PAT
	}
  }
  Return tRequest
}

ClassMethod GetSSLConfiguration(host) As %String
{
  NEW $NAMESPACE
  SET $NAMESPACE = "%SYS"
  
  IF '##class(Security.SSLConfigs).Exists(host) {
    DO ##class(Security.SSLConfigs).Create(host)
  }
  QUIT host
}

/// Used for unittests, reset's external temporary registry from any packages.
Method ResetRegistry() As %Status
{
  Set debugKey = $system.Util.GetEnviron("TEST_REGISTRY_DEBUG")
  if (debugKey="") {
    Quit $$$OK
  }

  Set tRequest = ..GetHttpRequest()
  Do tRequest.SetHeader("REGISTRY_DEBUG", debugKey)
  
  Quit tRequest.Get(tRequest.Location_"_reset")
}

}

