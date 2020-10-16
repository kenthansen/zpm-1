Class %ZPM.PackageManager.Client.Azure.PublishClient Extends (%ZPM.PackageManager.Client.Azure.PackageManagerClient, %ZPM.PackageManager.Core.IPublishService)
{

Property ZipCommand As %String;

Method LocationGet() As %String
{
	//TODO:org scoped ones?
	Return $$$FormatText("https://%1.pkgs.visualstudio.com/%2/_packaging/%3/", ..Organization, ..Project, ..FeedId)
}

Method PublishModule(pModule As %ZPM.PackageManager.Core.Module) As %Boolean
{
  Quit ..Publish(pModule)
}

Method PublishApplication(pApplication As %ZPM.PackageManager.Core.Application) As %Boolean
{
  Quit ..Publish(pApplication)
}

Method Publish(pModule As %ZPM.PackageManager.Core.VersionedBase) As %Boolean
{
	If (..PAT = "") {
    	$$$ThrowStatus($$$ERROR($$$GeneralError, "Publishing module, authorization required."))
    }
  
	set tPackagePublishUrl = ..GetNugetPackagePublishUrl()
	W !, "Package Publish Url: ", tPackagePublishUrl
	
	set tFile = ..WrapInNuGetPackage(pModule)
	do ..PublishNuGetPackage(tPackagePublishUrl, tFile)

	Quit 1
}

/// Take a the tgz version of the module and wrap it in NuGet
/// returns the created package as a stream
Method WrapInNuGetPackage(pModule As %ZPM.PackageManager.Core.VersionedBase) As %Stream.FileBinary [ Private ]
{
	Set tWorkingDirectory=$$$FileTempDir
  
	//Place tgz back onto disk so we can make fake NuGet
	Set tTgzStream = ##class(%Stream.FileBinary).%New()
	Set tTgzStream.Filename = ##class(%File).NormalizeFilename(tWorkingDirectory_"/"_pModule.Name_".tgz")
	w !, "Module tgz written to disk:",!,$c(9), tTgzStream.Filename
	$$$ThrowOnError(tTgzStream.CopyFromAndSave(pModule.Payload))
  
	//Create the required .nuspec file to be a valid NuGet Package
	do ..CreateNuSpecFile(pModule, tWorkingDirectory)
	
	//Zip the directory to create the NuGet
	Set tNuGetFilename=##class(%File).NormalizeDirectory(tWorkingDirectory_"/..")_pModule.Name_".zip"	
	set tNuGetStream = ..ZipDirectory(tWorkingDirectory, tNuGetFilename)
	return tNuGetStream
}

/// Given a directory it will create a zip archive of it output to the specified output location
/// returns the created archive as a stream
Method ZipDirectory(pSourceDirectory, pOutputFilename) As %Stream.FileBinary [ Private ]
{
	w !, "Creating Zip:",!,$c(9), pOutputFilename,!,$c(9),"from folder ", pSourceDirectory
	//Set tCurrentDirectory=$system.Process.CurrentDirectory(pSourceDirectory)
	//w !, tCurrentDirectory

	If (..ZipCommand=""){
		$$$ThrowStatus($$$ERROR($$$GeneralError,"Missing configuration of ZipCommand."))
	}
	Set tCMD = $$$FormatText(..ZipCommand, pOutputFilename, pSourceDirectory)
	w !,$c(9),"with cmd ", tCMD
	
	Set tRequest = ..GetHttpRequest()
  	Set tRequest.ContentType = "application/json"

	If $zf(-1,tCMD) $$$ThrowStatus($$$ERROR($$$GeneralError,"Unable to create zip archive"))

	Set tOutputFileStream=##class(%Stream.FileBinary).%New()
	$$$ThrowOnError(tOutputFileStream.LinkToFile(pOutputFilename))
	return tOutputFileStream
}

/// Creates a .nuspec file in the specified directory based on the module's info
Method CreateNuSpecFile(pModule As %ZPM.PackageManager.Core.VersionedBase, pWorkingDirectory As %String) [ Private ]
{
	
	//TODO: Think this can be done with an XSLT?
	set writer=##class(%XML.Writer).%New()
	set writer.Charset="UTF-8"
	set writer.Indent=1
	set tNuSpecFileName = ##class(%File).NormalizeFilename((pWorkingDirectory_"/"_pModule.Name_".nuspec"))
	W !, "Creating NuSpec:",!,$c(9),tNuSpecFileName
	$$$ThrowOnError(writer.OutputToFile(tNuSpecFileName))


	do writer.RootElement("package", "http://schemas.microsoft.com/packaging/2010/07/nuspec.xsd")
		do writer.Element("metadata")
			do writer.Element("id")
				do writer.Write(pModule.Name)
			do writer.EndElement()
			do writer.Element("version")
				do writer.Write(pModule.VersionString)
			do writer.EndElement()
			do writer.Element("description")
				do writer.Write(pModule.Name)
			do writer.EndElement()
			do writer.Element("authors")
				do writer.Write("Steve")
			do writer.EndElement()
		do writer.EndElement()
	$$$ThrowOnError(writer.EndRootElement())
	$$$ThrowOnError(writer.EndDocument())
}

Method PublishNuGetPackage(pPackagePublishUrl As %String, pNuGetPackageStream As %Stream.FileBinary)
{
	#Dim tRequest as %Net.HttpRequest = ..GetHttpRequest(pPackagePublishUrl)
    
	//set tRequest.Username = "VssSessionToken"
	//Set tRequest.Password = "vkjw6pprah2ij57ciju6ft6aquuksvfkchmwlg66dj7jtircrwqq"
	
	// NuGet package publish take a multipart/form-data	PUT as defined here:
	// IRIS guidance on create such a request can be found here:
	// https://docs.intersystems.com/irisforhealth20191/csp/docbook/DocBook.UI.Page.cls?KEY=GNET_http#GNET_http_post_multipart
	
	// Create root MIMEPart
	Set RootMIMEPart=##class(%Net.MIMEPart).%New()

    //Create binary subpart and insert file data
    Set BinaryMIMEPart=##class(%Net.MIMEPart).%New()
    Set contentdisp="form-data; name="_$CHAR(34)_"package"_$CHAR(34)_"; filename="
                     _$CHAR(34)_"package.nupkg"_$CHAR(34)
    Do BinaryMIMEPart.SetHeader("Content-Disposition",contentdisp)


	Set BinaryMIMEPart.Body=pNuGetPackageStream
	Do BinaryMIMEPart.SetHeader("Content-Type","application/octet-stream")
     
    // Insert both subparts into the root part
    Do RootMIMEPart.Parts.Insert(BinaryMIMEPart)

    // create MIME writer; write root MIME message
    Set writer=##class(%Net.MIMEWriter).%New()
    
    Set status=writer.OutputToStream(tRequest.EntityBody)
    if $$$ISERR(status) {do $SYSTEM.Status.DisplayError(status) Quit}

    // Now write down the content
    Set status=writer.WriteMIMEBody(RootMIMEPart)
    if $$$ISERR(status) {do $SYSTEM.Status.DisplayError(status) Quit}
	
	Set ContentType= "multipart/form-data; boundary="_RootMIMEPart.Boundary
    Set tRequest.ContentType=ContentType
    do tRequest.SetHeader("X-NuGet-ApiKey", "AzureDevOps")
	do tRequest.Put("")
	
	//202 Accepted is what we are looking for
	If (tRequest.HttpResponse.StatusCode '= 202) {
    	If tRequest.HttpResponse.StatusCode = 401 {
      		$$$ThrowStatus($$$ERROR($$$GeneralError, "Publishing module, authorization required."))
    	} Else {
      		$$$ThrowStatus($$$ERROR($$$GeneralError, "Publishing module, something went wrong. "_tRequest.HttpResponse.StatusLine))
    	}
  	}
}

/// Get the nuget package publish url since it uses the guid version of the organization, etc
Method GetNugetPackagePublishUrl() As %String [ Private ]
{
	set tPackagePublishUrl = ""
	#Dim tRequest as %Net.HttpRequest = ..GetHttpRequest()
    
	//set tRequest.Username = "VssSessionToken"
	//Set tRequest.Password = "vkjw6pprah2ij57ciju6ft6aquuksvfkchmwlg66dj7jtircrwqq"
	   
	//do tRequest.Get("ConiferRCM/_packaging/testiris%40Local/nuget/v3/index.json")
	do tRequest.Get(tRequest.Location_"nuget/v3/index.json")
	//Do tRequest.HttpResponse.OutputToDevice()
	
	If (tRequest.HttpResponse.StatusCode '= 200) {
		If tRequest.HttpResponse.StatusCode = 401 {
			$$$ThrowStatus($$$ERROR($$$GeneralError, "Publishing module, authorization required."))
		} Else {
			$$$ThrowStatus($$$ERROR($$$GeneralError, "Publishing module, unable to get Nuget Package publish url."))
		}
	}
	
	if (tRequest.HttpResponse.ContentType '[ "application/json") {
		$$$ThrowStatus($$$ERROR($$$GeneralError, "Publishing module, unexpected response type from Nuget service. "_tRequest.HttpResponse.ContentType))
	}
	
	set tResponseJsonObject={}.%FromJSON(tRequest.HttpResponse.Data)
	
	set tResourceIter = tResponseJsonObject.resources.%GetIterator()
	while tResourceIter.%GetNext(.key , .value ) {
		set tType = value.%Get("@type")
		if (tType="PackagePublish/2.0.0") {
			set tPackagePublishUrl = value.%Get("@id")
			quit
		}	      
	}
	
	if (tPackagePublishUrl = "") {
		$$$ThrowStatus($$$ERROR($$$GeneralError, "Publishing module, unable to locate package publish url."))
	}

	return tPackagePublishUrl
}

}

