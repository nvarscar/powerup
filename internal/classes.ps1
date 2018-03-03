class PowerUpPackageFile {
	#Regular file properties
	[string]$PSPath
	[string]$PSParentPath
	[string]$PSChildName
	[string]$PSDrive
	[bool]  $PSIsContainer
	[string]$Mode
	[string]$BaseName
	[string]$Name
	[int]$Length
	[string]$DirectoryName
	[System.IO.DirectoryInfo]$Directory
	[bool]$IsReadOnly
	[bool]$Exists
	[string]$FullName
	[string]$Extension
	[datetime]$CreationTime
	[datetime]$CreationTimeUtc
	[datetime]$LastAccessTime
	[datetime]$LastAccessTimeUtc
	[datetime]$LastWriteTime
	[datetime]$LastWriteTimeUtc
	[System.IO.FileAttributes]$Attributes

	#Custom attributes
	[psobject]$Config
	[string]$Version
	[System.Version]$ModuleVersion
	[psobject[]]$Builds

	#Constructors
	PowerUpPackageFile ([FileInfo]$FileObject) {
		$this.PSPath = $FileObject.PSPath
		$this.PSParentPath = $FileObject.PSParentPath
		$this.PSChildName = $FileObject.PSChildName
		$this.PSDrive = $FileObject.PSDrive
		$this.PSIsContainer = $FileObject.PSIsContainer
		$this.Mode = $FileObject.Mode
		$this.BaseName = $FileObject.BaseName
		$this.Name = $FileObject.Name
		$this.Length = $FileObject.Length
		$this.DirectoryName = $FileObject.DirectoryName
		$this.Directory = $FileObject.Directory
		$this.IsReadOnly = $FileObject.IsReadOnly
		$this.Exists = $FileObject.Exists
		$this.FullName = $FileObject.FullName
		$this.Extension = $FileObject.Extension
		$this.CreationTime = $FileObject.CreationTime
		$this.CreationTimeUtc = $FileObject.CreationTimeUtc
		$this.LastAccessTime = $FileObject.LastAccessTime
		$this.LastAccessTimeUtc = $FileObject.LastAccessTimeUtc
		$this.LastWriteTime = $FileObject.LastWriteTime
		$this.LastWriteTimeUtc = $FileObject.LastWriteTimeUtc
		$this.Attributes = $FileObject.Attributes
		$this | Add-Member -MemberType AliasProperty -Name Path -Value FullName
		$this | Add-Member -MemberType AliasProperty -Name Size -Value Length
	}
	PowerUpPackageFile ([System.IO.DirectoryInfo]$FileObject) {
		$this.PSPath = $FileObject.PSPath
		$this.PSParentPath = $FileObject.PSParentPath
		$this.PSChildName = $FileObject.PSChildName
		$this.PSDrive = $FileObject.PSDrive
		$this.PSIsContainer = $FileObject.PSIsContainer
		$this.Mode = $FileObject.Mode
		$this.BaseName = $FileObject.BaseName
		$this.Name = $FileObject.Name
		$this.Length = 0
		$this.Directory = $FileObject.Parent
		$this.DirectoryName = $FileObject.Parent.Name
		$this.IsReadOnly = $false
		$this.Exists = $FileObject.Exists
		$this.FullName = $FileObject.FullName
		$this.Extension = $FileObject.Extension
		$this.CreationTime = $FileObject.CreationTime
		$this.CreationTimeUtc = $FileObject.CreationTimeUtc
		$this.LastAccessTime = $FileObject.LastAccessTime
		$this.LastAccessTimeUtc = $FileObject.LastAccessTimeUtc
		$this.LastWriteTime = $FileObject.LastWriteTime
		$this.LastWriteTimeUtc = $FileObject.LastWriteTimeUtc
		$this.Attributes = $FileObject.Attributes
		$this | Add-Member -MemberType AliasProperty -Name Path -Value FullName
		$this | Add-Member -MemberType AliasProperty -Name Size -Value Length
	}

	#Methods
	[string] ToString () {
		return $this.FullName
	}
}