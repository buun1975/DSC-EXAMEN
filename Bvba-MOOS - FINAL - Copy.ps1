$ConfigData = @{
    AllNodes = @(
        @{
            NodeName = 'localhost'
            Role = 'Primary DC'
            MachineName = 'DC1' 				        	# Naam van de domain controller
            DomainName = 'bvbamoos.local' 			    	# Naam van domein
            DomainNetBIOS = 'BVBAMOOS'				    	# Netbion-naam van Domein
            LabPassword = 'DSCPassword$'			    	# Paswoord voor zowel lokaal als AD
            ADAdminUser = 'bvbamoos.local\administrator'	# Username voor domein
            SafeModeAdminUser = 'administrator'			    # Username voor lokaal
            IPAddress = '192.168.30.60/24'		    		# IP-Adres voor server met subnet
            InterfaceAlias = 'Ethernet0'		    		# Naam van de netwerk-verbinding
            DefaultGateway = '192.168.30.1'		    		# Default Gateway
            SubnetMask = '24'					          	# Subnet
            AddressFamily = 'IPv4'				        	# Type IP-adres
            DNSAddress = '127.0.0.1' ,'192.168.30.60'		# DNS-Servers
            DNS_for_DHCP = '192.168.30.60'				    # DNS-Server voor DHCP
            Network_Address = '192.168.30.0'				# Netwerk-adres
            FullAccess = 'EveryOne'				        	# Acces voor de deelmappen
            PSDscAllowPlainTextPassword = $true
            PSDscAllowDomainUser = $true
        }
    )
}

#$website_header=@'
#<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
#<html xmlns="http://www.w3.org/1999/xhtml">
#<head>
#<meta http-equiv="Content-Type" content="text/html; charset=iso-8859-1" />
#<title>Welkom bij Bvba MOOS</title>
#<style type="text/css">
#<!--
#body {
#	color:#000000;
#	background-color: cornflowerblue;
#	padding-top : 20px;
#	padding-left: 100px;
#}
#h2,h3,p {
#	font-family: Verdana, Geneva, Tahoma, sans-serif;
#}
#-->
#</style>
#</head>
#<body>
#<H2>
#	Welkom bij Bvba MOOS :-)
#</H2>
#<H3>
#	Selecteer &eacute;&eacute;n van deelmappen hieronder :
#</H3>
#'@
#
#$website_data=''
#
#$website_footer=@'
#<P>&nbsp;</P>
#<P>Have a nice day !</P>
#</body>
#</html>
#'@
#
#$newLine = [Environment]::NewLine

Configuration BvbaMOOS {
    # Modules installeren
    # Modules importeren die nodig zijn. Deze moeten reeds in C:\Program Files\WindowsPowerShell\Modules staan
    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -Module xActiveDirectory, xComputerManagement, xNetworking, xDhcpServer, xSmbShare, xDnsServer, xWebAdministration
    #, xPendingReboot
    
    # Configuratie voor de server die gedefiniëerd staat hierboven in ConfigData
    Node $AllNodes.NodeName 
    {
        # Herstarten wanneer nodig
         LocalConfigurationManager 
        {
            ActionAfterReboot = 'ContinueConfiguration'            
            ConfigurationMode = 'ApplyOnly'            
            RebootNodeIfNeeded = $true  
        }

        # Paswoorden voordefiniëren
        $password = ConvertTo-SecureString $Node.LabPassword -AsPlainText -Force 
        $credentials_AD = New-Object System.Management.Automation.PSCredential($Node.ADAdminUser,$password)
        $credentials_Local = New-Object System.Management.Automation.PSCredential($Node.SafeModeAdminUser,$password)

        #SERVER
        #------

        # Computernaam instellen
        xComputer SetName { 
          Name = $Node.MachineName 
        }
        
        # IP-Adres Instellen voor netwerk
        xIPAddress SetIP {
            IPAddress = $Node.IPAddress
            InterfaceAlias = $Node.InterfaceAlias
            AddressFamily = $Node.AddressFamily
            
        }

        # Default Gateway instellen voor netwerk
        xDefaultGatewayAddress SetDefaultGateway        
        {
            Address        = $Node.DefaultGateway
            InterfaceAlias = $Node.InterfaceAlias
            AddressFamily  = $Node.AddressFamily
            DependsOn = "[xIPAddress]SetIP"
        }

        # DNS instellen voor netwerk
        xDNSServerAddress SetDNS {
            Address = $Node.DNSAddress
            InterfaceAlias = $Node.InterfaceAlias
            AddressFamily = $Node.AddressFamily
            DependsOn = "[xDefaultGatewayAddress]SetDefaultGateway"
        }

        #ACTIVE DIRECTORY
        #----------------
        
        # Installatie van de Active Directory Domain Services
        WindowsFeature ADDSInstall {
            Ensure = 'Present'
            Name = 'AD-Domain-Services'
        }

        # Installatie van de Active Directory Management tools
        WindowsFeature ADDSRSATTools            
        {             
            Ensure = "Present"             
            Name = "RSAT-ADDS" 
            IncludeAllSubFeature = $true
            DependsOn = '[WindowsFeature]ADDSInstall'            
        }   

        # Domein aanmaken
        xADDomain DC {
            DomainName = $node.DomainName
            DomainNetbiosName = $node.DomainNetBIOS
            DomainAdministratorCredential = $credentials_AD
            SafemodeAdministratorPassword = $credentials_Local
            DependsOn = '[xComputer]SetName', '[WindowsFeature]ADDSInstall'
        }

        #DNS-SERVER
        #----------

        # Installatie van DNS-Server indien deze mocht ontbreken
        WindowsFeature DNSInstall {
            Ensure = "Present"
            Name = "DNS"
            DependsOn = "[xComputer]SetName", '[WindowsFeature]ADDSInstall'
        }

        # Installatie van DNS-Server tools (Administrative tools)
        WindowsFeature DNSTools {
            Ensure = "Present"
            Name = 'RSAT-DNS-Server'
            DependsOn = '[WindowsFeature]ADDSRSATTools'
        }

        #ADMINISTRATIE
        #-------------
        
        # Aanmaken van het default 'administrator' account in de AD
        xADUser FirstUser
        {
            DomainAdministratorCredential = $credentials_AD
            DomainName = $Node.DomainName
            UserName = $Node.ADAdminUser
            Password = $LabPassword
            Ensure = 'Present'
        }

        # Toevoegen van administrator in de 'Domain Admins'
        Script NewADAdminUser
        {
            SetScript = { Add-ADGroupMember -Identity "Domain Admins" -Members $Using:Node.ADAdminUser }
            TestScript = { $false }
            GetScript = { }
        }

        
        #SHARES
        #------

        # Basismap voor de shares aanmaken
        File Shares
        {
            DestinationPath = 'C:\Shares'
            Type = 'Directory'
            Ensure = 'Present'
        }

        #HR + Sharing
        File HR
        {
            DestinationPath = 'C:\Shares\HR'
            Type = 'Directory'
            Ensure = 'Present'
            DependsOn = "[File]Shares"
        }

        xSmbShare HR_Share 
        { 
            Ensure = "Present"  
            Name   = "HR" 
            Path = "C:\Shares\HR"   
            FullAccess = 'EveryOne'
            Description = "Deelmap voor HR" 
            DependsOn = "[File]HR" 
        }
        $website_data  += '<p>&nbsp;&nbsp;&nbsp;<a href="file://\\'+$node.MachineName+'\HR" alt="Deelmap voor HR">HR</a></p>' + $newLine

        #Productie + Sharing
        File Productie
        {
            DestinationPath = 'C:\Shares\Productie'
            Type = 'Directory'
            Ensure = 'Present'
            DependsOn = "[File]Shares"
        }
        xSmbShare Productie_Share 
        { 
            Ensure = "Present"  
            Name   = "Productie" 
            Path = "C:\Shares\Productie"   
            FullAccess = 'EveryOne'
            Description = "Deelmap voor Productie" 
            DependsOn = "[File]Productie"          
        } 
        $website_data  += '<p>&nbsp;&nbsp;&nbsp;<a href="file://\\'+$node.MachineName+'\Productie" alt="Deelmap voor Productie">Productie</a></p>' + $newLine
 
        #Marketing + Sharing
        File Marketing
        {
            DestinationPath = 'C:\Shares\Marketing'
            Type = 'Directory'
            Ensure = 'Present'
            DependsOn = "[File]Shares"
        }
        xSmbShare Marketing_Share 
        { 
            Ensure = "Present"  
            Name   = "Marketing" 
            Path = "C:\Shares\Marketing"   
            FullAccess = 'EveryOne'
            Description = "Deelmap voor Marketing" 
            DependsOn = "[File]Marketing"          
        }
        $website_data  += '<p>&nbsp;&nbsp;&nbsp;<a href="file://\\'+$node.MachineName+'\Marketing" alt="Deelmap voor Marketing">Marketing</a></p>' + $newLine

        #Logistiek + Sharing
        File Logistiek
        {
            DestinationPath = 'C:\Shares\Logistiek'
            Type = 'Directory'
            Ensure = 'Present'
            DependsOn = "[File]Shares"
        }
        xSmbShare Logistiek_Share 
        { 
            Ensure = "Present"  
            Name   = "Logistiek" 
            Path = "C:\Shares\Logistiek"   
            FullAccess = 'EveryOne'
            Description = "Deelmap voor Logistiek" 
            DependsOn = "[File]Logistiek"          
        } 
        $website_data  += '<p>&nbsp;&nbsp;&nbsp;<a href="file://\\'+$node.MachineName+'\Logistiek" alt="Deelmap voor Logistiek">Logistiek</a></p>' + $newLine

        #Onderzoek + Sharing
        File Onderzoek
        {
            DestinationPath = 'C:\Shares\Onderzoek'
            Type = 'Directory'
            Ensure = 'Present'
            DependsOn = "[File]Shares"
        }
        xSmbShare Onderzoek_Share 
        { 
            Ensure = "Present"  
            Name   = "Onderzoek" 
            Path = "C:\Shares\Onderzoek"   
            FullAccess = 'EveryOne'
            Description = "Deelmap voor Onderzoek" 
            DependsOn = "[File]Onderzoek"          
        } 
        $website_data  += '<p>&nbsp;&nbsp;&nbsp;<a href="file://\\'+$node.MachineName+'\Onderzoek" alt="Deelmap voor Onderzoek">Onderzoek</a></p>' + $newLine

        #IIS
        #---
        WindowsFeature InstallIIS
        {
            Ensure = 'Present'
            Name = "Web-Server"
            DependsOn = "[xComputer]SetName", '[WindowsFeature]ADDSInstall'
        }

        WindowsFeature IISConsole
        {
            Ensure = "Present"
            Name = 'Web-Mgmt-Console'
            DependsOn = '[WindowsFeature]InstallIIS'
        }
	File Indexfile {
            Ensure          = 'Present'
            Type            = 'file'
            DestinationPath = "C:\inetpub\wwwroot\index.html"    # you need to create the index.html file before you edit it 
            Contents        = "<html>
            <header><title>Welkom</title></header>
                <body>
                        DSC Dinges van Delander Bruno   
                </body>
            </html>"
        }
        # Authenticatie instellen
        WindowsFeature EnableWinAuth {
            Name = "Web-Windows-Auth"
            Ensure = "Present"
            DependsOn = "[WindowsFeature]InstallIIS"
        }

        WindowsFeature EnableURLAuth {
            Name = "Web-Url-Auth"
            Ensure = "Present"
            DependsOn = "[WindowsFeature]InstallIIS"
        }

        WindowsFeature HostableWebCore {
            Name = "Web-WHC"
            Ensure = "Present"
            DependsOn = "[WindowsFeature]InstallIIS"
        }
        xFirewall AllowManagementPort {
            Name = "HTTP port"
            DisplayName = "HTTP port"
            Ensure = "Present"
            Protocol = "TCP"
            Enabled = "True"
            Direction = "InBound"
            LocalPort = 80
        }
        #file WebPage
        #{
        #    DestinationPath = 'c:\inetpub\wwwroot\bvbamoos.html'
        #    Contents = $website_header+$newLine+$website_data+$website_footer
        #    Type = 'File'
        #    Ensure = "Present"
        #    DependsOn = '[WindowsFeature]InstallIIS'
       # }
       # $filter = "system.webserver/defaultdocument/files"
       # $site = "IIS:\sites\Default Web Site"
       # $file = "bvbamoos.html"
#
       # if ((Get-WebConfiguration $filter/* "$site" | where {$_.value -eq $file}).length -eq 1)
        #{
        #    Remove-WebconfigurationProperty $filter "$site" -name collection -AtElement @{value=$file}
        #}
        #Add-WebConfiguration $filter "$site" -atIndex 0 -Value @{value=$file}

        #DHCP SERVER
        #-----------

        # DHCP-Server Installeren
        WindowsFeature DHCP 
        {
            Ensure = 'Present'
            Name = 'DHCP'
            DependsOn = "[xComputer]SetName", '[WindowsFeature]ADDSInstall', '[WindowsFeature]DNSInstall'
        }

        # Installatie van DHCP-Server tools (Administrative tools)
        WindowsFeature DHCPTools
        {
            Ensure = "Present"
            Name = 'RSAT-DHCP'
            DependsOn = '[WindowsFeature]ADDSRSATTools'
        }

        # DHCP-Server scope instellen
        xDhcpServerScope Scope
        {
            Ensure = "Present"
            ScopeID = $Node.Network_Address
            IPStartRange = "192.168.30.61"
            IPEndRange = "192.168.30.99"
            Name = "BvbaMOOS"
            SubnetMask = "255.255.255.0"
            State = "Active"            
            LeaseDuration = "8:00:00"
            DependsOn = "[WindowsFeature]DHCP"
        }

        # DHCP-Server opties meegeven aan de scope van hierboven
        xDhcpServerOption ServerOpt
        {
            Ensure = "Present"
            ScopeID = $Node.Network_Address
            Router = '192.168.30.1'
            DnsServerIPAddress = '192.168.30.60'
            DnsDomain = $Node.DomainName
            AddressFamily = $Node.AddressFamily            
            DependsOn = "[xDhcpServerScope]Scope"
        }
        
        # DHCP Server 'authorizen' binnen het domein, zoniet kan deze binnen het domein geen IP-adressen uitgeven
        xDhcpServerAuthorization DhcpAuth
        {
            Ensure = "Present"
            DependsOn = "[WindowsFeature]DHCP"
        }

    }
}

# MOF-file aanmaken
BvbaMOOS -ConfigurationData $ConfigData

# De configuratie opladen
Start-DscConfiguration -Wait -Force -Path .\BvbaMOOS -Verbose